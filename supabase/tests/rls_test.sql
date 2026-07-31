-- =============================================================================
-- Teste de isolamento entre plantas + constraints do domínio
-- =============================================================================
-- Rode num banco descartável (ver supabase/README.md). O que interessa é que
-- CADA bloco marcado "espera erro" realmente falhe: a chave publishable do app
-- é pública, então a única coisa entre ela e os dados de outra planta é o RLS.
-- =============================================================================
\pset pager off

-- atalho só de teste: view do dono (roda sem RLS) para o script achar ids
create view public.orgs_all_test as select * from public.orgs;
grant select on public.orgs_all_test to authenticated;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@planta.com'),
  ('22222222-2222-2222-2222-222222222222', 'b@planta.com'),
  ('33333333-3333-3333-3333-333333333333', 'c@planta.com');

\echo ''
\echo '=== 1. A e B criam suas plantas ==='
set role authenticated; set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select name, join_code from public.bootstrap_org('Planta A');
reset role;
set role authenticated; set request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select name from public.bootstrap_org('Planta B');
reset role;

\echo '=== 2. o trigger criou uma linha de settings por planta (espera 2) ==='
select count(*) as settings_rows from public.settings;

\echo '=== 3. A cadastra máquina, motivo, apontamento e marcações ==='
set role authenticated; set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
insert into public.machines (id, name, sector, rate, oee_target)
  values ('maqA1', 'Extrusora 1', 'Extrusão', 10, 85);
insert into public.stop_reasons (id, name, description, planned, std_min)
  values ('rsnA1', 'Setup / Troca', 'troca de lote', true, 10);
insert into public.stop_reason_machines (reason_id, machine_id) values ('rsnA1', 'maqA1');
insert into public.sessions (id, machine_id, start_at, end_at, theo, real_qty, scrap)
  values ('sesA1', 'maqA1', now() - interval '60 min', now(), 500, 400, 50);
insert into public.segments (session_id, seq, state, start_at, end_at) values
  ('sesA1', 0, 'prod', now() - interval '60 min', now() - interval '20 min'),
  ('sesA1', 1, 'idle', now() - interval '20 min', now() - interval '15 min');
insert into public.segments (session_id, seq, state, reason, kind, planned, std_ms, maint_at, start_at, end_at)
  values ('sesA1', 2, 'stop', 'Setup / Troca', 'op', true, 600000,
          now() - interval '13 min', now() - interval '15 min', now());
select 'A vê ' || count(*) || ' máquina(s)' as r from public.machines;

\echo '=== 4. B cadastra a sua e não enxerga nada de A ==='
reset role;
set role authenticated; set request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
insert into public.machines (id, name, rate) values ('maqB1', 'Injetora 1', 20);
select id, name from public.machines order by id;
select 'B vê ' || count(*) || ' apontamento(s) de A' as r from public.sessions where id = 'sesA1';
select 'B vê ' || count(*) || ' marcação(ões) de A' as r from public.segments where session_id = 'sesA1';

\echo '=== 5. B tenta alterar/apagar a máquina de A (espera 0 linhas nas duas) ==='
with u as (update public.machines set name = 'invadida' where id = 'maqA1' returning 1)
  select count(*) as linhas_alteradas from u;
with d as (delete from public.machines where id = 'maqA1' returning 1)
  select count(*) as linhas_apagadas from d;

\echo '=== 6. B tenta forjar o org_id da planta A (espera erro de RLS) ==='
insert into public.machines (id, org_id, name, rate)
  select 'maqX', id, 'forjada', 5 from public.orgs_all_test where name = 'Planta A';

\echo '=== 6b. B tenta mover a própria máquina para a planta A (espera erro de RLS) ==='
update public.machines set org_id = (select id from public.orgs_all_test where name = 'Planta A')
  where id = 'maqB1';

\echo '=== 7. B tenta pendurar marcação no apontamento de A (espera erro de FK) ==='
insert into public.segments (session_id, seq, state, start_at) values ('sesA1', 9, 'prod', now());

\echo '=== 8. constraints do domínio (as três devem falhar) ==='
insert into public.segments (session_id, seq, state, reason, start_at)
  values ('sesA1', 8, 'prod', 'motivo em produção', now());
insert into public.stop_reasons (id, name, planned, std_min)
  values ('rsnB9', 'não planejada com tempo padrão', false, 5);
insert into public.machines (id, name, rate) values ('maqB9', 'capacidade zero', 0);

\echo '=== 9. uma medição aberta por máquina (a segunda deve falhar) ==='
insert into public.sessions (id, machine_id, start_at) values ('sesB1', 'maqB1', now());
insert into public.sessions (id, machine_id, start_at) values ('sesB2', 'maqB1', now());

\echo '=== 10. C entra na planta de A pelo join_code ==='
reset role;
set role authenticated; set request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
select public.join_org((select join_code from public.orgs_all_test where name = 'Planta A')) is not null as entrou;
select id, name from public.machines order by id;
select 'C vê ' || count(*) || ' apontamento(s)' as r from public.sessions;

\echo '=== 11. C tenta entrar numa segunda planta (espera erro) ==='
select public.join_org('XXXXXXXX');

\echo '=== 12. updated_at se move sozinho no update ==='
reset role;
set role authenticated; set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select updated_at = created_at as igual_antes from public.machines where id = 'maqA1';
update public.machines set sector = 'Extrusão B' where id = 'maqA1';
select updated_at > created_at as maior_depois from public.machines where id = 'maqA1';

\echo '=== 13. a role anônima não lê nada (espera permission denied) ==='
reset role; set role anon; reset request.jwt.claim.sub;
select count(*) from public.machines;
reset role;

\echo '=== 14. toda tabela com RLS ligado e com policies? ==='
select relname as tabela, relrowsecurity as rls,
       (select count(*) from pg_policies p where p.tablename = c.relname) as policies
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r' order by relname;
