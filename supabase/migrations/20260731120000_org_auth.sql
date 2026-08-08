-- =============================================================================
-- MES — plantas (orgs), perfis e o filtro que sustenta todo o RLS
-- =============================================================================
-- O app é usado por vários aparelhos ao lado de máquinas diferentes, todos
-- enxergando o mesmo cadastro e alimentando o mesmo dashboard. O dono do dado,
-- portanto, não é o aparelho nem o usuário: é a PLANTA (org). Cada tabela do
-- domínio carrega org_id e toda policy filtra por public.current_org_id().
--
-- Sem isso, a chave publishable do cliente — que é pública por natureza —
-- daria leitura e escrita a qualquer um. É o RLS, e só ele, que a torna segura.
-- =============================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------- plantas ---
create table public.orgs (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (length(btrim(name)) > 0),
  -- código curto para um segundo aparelho entrar na mesma planta
  join_code  text not null unique default upper(substr(encode(gen_random_bytes(6), 'hex'), 1, 8)),
  created_at timestamptz not null default now()
);

comment on table  public.orgs is 'Planta / unidade fabril — dona de todos os dados do MES.';
comment on column public.orgs.join_code is 'Código de entrada, usado por public.join_org().';

-- ----------------------------------------------------------------- perfis ---
create table public.profiles (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  org_id     uuid not null references public.orgs(id) on delete cascade,
  name       text,
  role       text not null default 'operador' check (role in ('operador', 'gestor')),
  created_at timestamptz not null default now()
);

create index profiles_org_id_idx on public.profiles (org_id);

comment on table public.profiles is 'Liga um usuário do auth a uma planta. Um usuário pertence a uma planta só.';

-- ------------------------------------------------- planta do usuário atual ---
-- security definer + search_path vazio: a função precisa ler public.profiles
-- ignorando o RLS, senão a policy de profiles chamaria a si mesma.
create or replace function public.current_org_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select org_id from public.profiles where user_id = (select auth.uid());
$$;

comment on function public.current_org_id() is
  'Planta do usuário autenticado. Base de todas as policies do MES.';

-- ------------------------------------------------------------------ RLS -----
alter table public.orgs     enable row level security;
alter table public.profiles enable row level security;

-- Sem policy de insert/delete: planta e perfil só nascem pelas RPCs abaixo.
create policy "orgs_select_own" on public.orgs
  for select to authenticated
  using (id = public.current_org_id());

create policy "orgs_update_own" on public.orgs
  for update to authenticated
  using (id = public.current_org_id())
  with check (id = public.current_org_id());

create policy "profiles_select_same_org" on public.profiles
  for select to authenticated
  using (org_id = public.current_org_id());

create policy "profiles_update_self" on public.profiles
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()) and org_id = public.current_org_id());

-- ------------------------------------------------------------------ RPCs ----
-- Criar a planta: o primeiro usuário vira gestor dela.
create or replace function public.bootstrap_org(org_name text)
returns public.orgs
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  o   public.orgs;
begin
  if uid is null then
    raise exception 'é preciso estar autenticado';
  end if;
  if exists (select 1 from public.profiles where user_id = uid) then
    raise exception 'este usuário já pertence a uma planta';
  end if;

  insert into public.orgs (name)
    values (coalesce(nullif(btrim(org_name), ''), 'Minha planta'))
    returning * into o;
  insert into public.profiles (user_id, org_id, role) values (uid, o.id, 'gestor');
  return o;  -- a linha de settings nasce por trigger (ver migration do core)
end;
$$;

-- Entrar numa planta existente pelo join_code (segundo tablet, outro operador).
create or replace function public.join_org(code text)
returns public.orgs
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  o   public.orgs;
begin
  if uid is null then
    raise exception 'é preciso estar autenticado';
  end if;
  if exists (select 1 from public.profiles where user_id = uid) then
    raise exception 'este usuário já pertence a uma planta';
  end if;

  select * into o from public.orgs where join_code = upper(btrim(code));
  if o.id is null then
    raise exception 'código de planta inválido';
  end if;

  insert into public.profiles (user_id, org_id, role) values (uid, o.id, 'operador');
  return o;
end;
$$;

revoke all on function public.current_org_id()   from public;
revoke all on function public.bootstrap_org(text) from public;
revoke all on function public.join_org(text)      from public;
grant execute on function public.current_org_id()   to authenticated;
grant execute on function public.bootstrap_org(text) to authenticated;
grant execute on function public.join_org(text)      to authenticated;
