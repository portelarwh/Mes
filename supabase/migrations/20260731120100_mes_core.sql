-- =============================================================================
-- MES — máquinas, motivos, apontamentos e marcações
-- =============================================================================
-- Espelha as entidades que o app já mantém no localStorage. Duas decisões
-- carregam o resto do desenho:
--
-- 1. PK `text`, reaproveitando o id que o app já gera (uid() → "lx3k2abc").
--    A migração da base local vira insert direto, sem remapear referência.
-- 2. Toda tabela tem org_id com `default public.current_org_id()`: o cliente
--    não envia o campo, o Postgres preenche, e o `with check` das policies
--    impede que ele forje outra planta.
--
-- Os FKs são compostos (id, org_id) de propósito: sem isso um cliente poderia
-- pendurar um segmento da sua planta num apontamento de outra.
-- =============================================================================

-- --------------------------------------------------------- updated_at -------
-- Marca de tempo por linha: é o que permite last-write-wins na sincronização
-- offline (fase 4), em vez de sobrescrever a base inteira.
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ------------------------------------------------------------- máquinas -----
create table public.machines (
  id         text primary key,
  org_id     uuid not null default public.current_org_id() references public.orgs(id) on delete cascade,
  name       text not null check (length(btrim(name)) > 0),
  sector     text not null default '',
  rate       numeric not null check (rate > 0),                                 -- peças por minuto
  oee_target numeric not null default 85 check (oee_target > 0 and oee_target <= 100),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,                                                       -- soft delete: exclusão precisa sincronizar
  unique (id, org_id)
);

-- --------------------------------------------------- motivos de parada ------
create table public.stop_reasons (
  id          text primary key,
  org_id      uuid not null default public.current_org_id() references public.orgs(id) on delete cascade,
  name        text not null check (length(btrim(name)) > 0),
  description text not null default '',
  planned     boolean not null default false,
  std_min     numeric check (std_min is null or std_min >= 0),                  -- tempo padrão; estouro vira não planejado
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  unique (id, org_id),
  -- tempo padrão só faz sentido em parada planejada
  constraint std_min_only_when_planned check (std_min is null or planned)
);

-- Motivo → máquinas em que ele aparece. Sem nenhuma linha = vale para todas,
-- exatamente como o `machineIds` vazio do app.
create table public.stop_reason_machines (
  reason_id  text not null,
  machine_id text not null,
  org_id     uuid not null default public.current_org_id() references public.orgs(id) on delete cascade,
  primary key (reason_id, machine_id),
  foreign key (reason_id, org_id)  references public.stop_reasons(id, org_id) on delete cascade,
  foreign key (machine_id, org_id) references public.machines(id, org_id)     on delete cascade
);

create index stop_reason_machines_machine_idx on public.stop_reason_machines (org_id, machine_id);

-- --------------------------------------------------------- apontamentos -----
create table public.sessions (
  id           text primary key,
  org_id       uuid not null default public.current_org_id() references public.orgs(id) on delete cascade,
  machine_id   text not null,
  start_at     timestamptz not null,
  end_at       timestamptz,                                                     -- null = medição em andamento
  theo         numeric not null default 0,                                      -- contagem teórica acumulada
  real_qty     integer check (real_qty is null or real_qty >= 0),               -- produção contada no fechamento
  scrap        integer not null default 0 check (scrap >= 0),
  manual       boolean not null default false,                                  -- veio da aba Manual
  partial_real integer check (partial_real is null or partial_real >= 0),       -- produção parcial durante a medição
  prev_real    integer,                                                         -- valores de antes, ao reabrir um fechado
  prev_scrap   integer,
  created_by   uuid references auth.users(id) default auth.uid(),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz,
  unique (id, org_id),
  foreign key (machine_id, org_id) references public.machines(id, org_id),
  constraint end_after_start check (end_at is null or end_at >= start_at),
  constraint scrap_within_real check (real_qty is null or scrap <= real_qty)
);

create index sessions_period_idx on public.sessions (org_id, start_at desc);
create index sessions_machine_idx on public.sessions (org_id, machine_id, start_at desc);
-- no máximo uma medição aberta por máquina
create unique index sessions_one_open_per_machine
  on public.sessions (org_id, machine_id)
  where end_at is null and deleted_at is null;

-- ------------------------------------------------------------ marcações -----
-- `seq` é a posição no array segs[] do app: o cliente reescreve os segmentos de
-- um apontamento inteiro, e a chave (session_id, seq) torna isso idempotente.
create table public.segments (
  session_id text not null,
  seq        integer not null check (seq >= 0),
  org_id     uuid not null default public.current_org_id() references public.orgs(id) on delete cascade,
  state      text not null check (state in ('prod', 'stop', 'idle', 'wait')),
  reason     text,                                                              -- nome do motivo no momento do apontamento
  kind       text check (kind is null or kind in ('fail', 'break', 'op')),
  planned    boolean,
  std_ms     integer check (std_ms is null or std_ms >= 0),
  maint_at   timestamptz,                                                       -- chegada da manutenção (MTTA / MTTR)
  start_at   timestamptz not null,
  end_at     timestamptz,                                                       -- null = segmento aberto (estado atual)
  primary key (session_id, seq),
  foreign key (session_id, org_id) references public.sessions(id, org_id) on delete cascade,
  constraint seg_end_after_start check (end_at is null or end_at >= start_at),
  -- motivo, tipo e manutenção só existem em parada
  constraint stop_only_fields check (
    state = 'stop' or (reason is null and kind is null and planned is null and maint_at is null and std_ms is null)),
  -- a manutenção chega durante a parada, nunca antes dela
  constraint maint_within_stop check (maint_at is null or maint_at >= start_at)
);

create index segments_session_idx on public.segments (org_id, session_id, seq);

-- ---------------------------------------- configuração de cálculo do OEE ----
-- Tema e período do filtro continuam no aparelho: são preferência de tela,
-- não configuração da planta.
create table public.settings (
  org_id              uuid primary key references public.orgs(id) on delete cascade,
  idle_counts_as_stop boolean not null default false,                           -- ociosa entra na base do OEE da máquina?
  wait_counts_as_stop boolean not null default false,                           -- esperando entra?
  ask_detail          boolean not null default true,                            -- pedir motivo ao marcar parada
  updated_at          timestamptz not null default now()
);

-- Toda planta nasce com uma linha de settings, venha de onde vier.
create or replace function public.orgs_default_settings()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.settings (org_id) values (new.id) on conflict do nothing;
  return new;
end;
$$;

create trigger orgs_default_settings_tr
  after insert on public.orgs
  for each row execute function public.orgs_default_settings();

-- ------------------------------------------------------------- triggers -----
create trigger machines_touch     before update on public.machines     for each row execute function public.touch_updated_at();
create trigger stop_reasons_touch before update on public.stop_reasons for each row execute function public.touch_updated_at();
create trigger sessions_touch     before update on public.sessions     for each row execute function public.touch_updated_at();
create trigger settings_touch     before update on public.settings     for each row execute function public.touch_updated_at();

-- =============================================================================
-- RLS — nenhuma linha atravessa a fronteira da planta
-- =============================================================================
do $$
declare
  t text;
begin
  foreach t in array array['machines', 'stop_reasons', 'stop_reason_machines',
                           'sessions', 'segments', 'settings']
  loop
    execute format('alter table public.%I enable row level security', t);

    execute format($f$
      create policy %I on public.%I for select to authenticated
        using (org_id = public.current_org_id())$f$, t || '_select_own_org', t);

    execute format($f$
      create policy %I on public.%I for insert to authenticated
        with check (org_id = public.current_org_id())$f$, t || '_insert_own_org', t);

    execute format($f$
      create policy %I on public.%I for update to authenticated
        using (org_id = public.current_org_id())
        with check (org_id = public.current_org_id())$f$, t || '_update_own_org', t);

    execute format($f$
      create policy %I on public.%I for delete to authenticated
        using (org_id = public.current_org_id())$f$, t || '_delete_own_org', t);

    -- o app exige login: a role anônima não enxerga nada
    execute format('revoke all on public.%I from anon', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
  end loop;
end;
$$;

revoke all on public.orgs, public.profiles from anon;
grant select, update on public.orgs     to authenticated;
grant select, update on public.profiles to authenticated;
