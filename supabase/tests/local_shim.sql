-- =============================================================================
-- Shim para rodar as migrations num Postgres local, fora do Supabase
-- =============================================================================
-- Reproduz o mínimo que o Supabase provê e de que o schema depende: as roles
-- anon/authenticated, o schema auth e auth.uid(). No Supabase real nada disso
-- é necessário — este arquivo existe só para testar o schema e o RLS na sua
-- máquina, sem tocar no projeto de produção. Veja supabase/README.md.
-- =============================================================================

create extension if not exists pgcrypto;

-- roles são do cluster, não do banco: o shim precisa ser re-executável
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
end;
$$;

create schema auth;

create table auth.users (
  id    uuid primary key default gen_random_uuid(),
  email text unique
);

-- No Supabase, auth.uid() lê o `sub` do JWT da requisição. Aqui lemos o mesmo
-- GUC, o que permite "virar" um usuário com  set request.jwt.claim.sub = '...'
create or replace function auth.uid() returns uuid
language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

grant usage on schema public to anon, authenticated;
grant usage on schema auth   to anon, authenticated;
