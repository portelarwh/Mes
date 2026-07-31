# Banco (Supabase)

Schema do MES versionado em SQL. Projeto: `dupqpzgtcnukgusyutkg`.

```
migrations/20260731120000_org_auth.sql   plantas, perfis, current_org_id(), RPCs de entrada
migrations/20260731120100_mes_core.sql   máquinas, motivos, apontamentos, marcações, settings + RLS
tests/local_shim.sql                     shim do `auth` para testar num Postgres local
tests/rls_test.sql                       isolamento entre plantas + constraints do domínio
```

## Aplicar

**Pelo painel:** SQL Editor → cole `20260731120000_org_auth.sql`, rode; depois
`20260731120100_mes_core.sql`. A ordem importa.

**Pela CLI** (recomendado — é o que mantém o histórico batendo com o git):

```sh
supabase link --project-ref dupqpzgtcnukgusyutkg
supabase db push
```

## Criar a primeira planta

1. Authentication → Users → **Add user** (e-mail e senha do gestor).
2. Logado como esse usuário, chame a RPC uma vez:

```js
await sb.rpc('bootstrap_org', { org_name: 'Minha planta' });
```

Isso cria a planta, marca o usuário como `gestor` e devolve o **`join_code`**.
Cada aparelho ou operador novo cria a própria conta e entra com:

```js
await sb.rpc('join_org', { code: 'ABC12345' });
```

Um usuário pertence a uma planta só; chamar de novo dá erro de propósito.

## Verificar que o RLS está mesmo de pé

A chave `sb_publishable_...` do app é **pública por natureza** — vai no repo e no
`index.html` sem problema. O que a torna segura é o RLS, e só ele. Sem sessão,
nada deve sair:

```sh
curl -s "https://dupqpzgtcnukgusyutkg.supabase.co/rest/v1/machines?select=*" \
     -H "apikey: sb_publishable_..." | head
# esperado: []  (nunca uma lista de máquinas)
```

Se isso devolver dados, **pare**: alguma tabela ficou sem RLS.

A chave `sb_secret_` / `service_role` nunca entra no repo — o GitHub Pages é
público.

## Rodar o teste localmente

Precisa de um Postgres 15+ na máquina. O shim recria só o que o schema consome
do Supabase (roles `anon`/`authenticated`, schema `auth`, `auth.uid()`), então o
teste roda num banco descartável, sem tocar em produção:

```sh
createdb mestest
psql -q -v ON_ERROR_STOP=1 -d mestest \
  -f supabase/tests/local_shim.sql \
  -f supabase/migrations/20260731120000_org_auth.sql \
  -f supabase/migrations/20260731120100_mes_core.sql
psql -q -d mestest -f supabase/tests/rls_test.sql
```

O teste é escrito ao contrário do usual: os blocos marcados **"espera erro"**
precisam falhar. Ele monta duas plantas e verifica que a planta B não lê, não
altera, não apaga e não consegue forjar dado da planta A — nem inserindo um
`org_id` alheio, nem pendurando uma marcação num apontamento que não é dela.

## Decisões que valem saber

**PK `text`, não `uuid`.** Os ids vêm do `uid()` que o app já usa (`"lx3k2abc"`),
então migrar o `localStorage` de quem já usa o app é insert direto, sem
remapear referência nenhuma.

**`org_id` com `default public.current_org_id()`.** O cliente não envia o campo;
o Postgres preenche a partir do JWT. O `with check` das policies impede que ele
mande outro.

**FKs compostos `(id, org_id)`.** Sem isso um cliente poderia pendurar um
segmento da própria planta num apontamento de outra — o FK simples só olha o id.

**`deleted_at` em vez de DELETE.** Exclusão precisa sincronizar: um `delete`
físico não tem como ser propagado para o tablet que estava offline.

**`updated_at` por linha.** É o que permite last-write-wins **por linha** na
fase de sync offline, em vez de um aparelho sobrescrever a base do outro.

**Tema e período do filtro não sobem.** São preferência do aparelho, não
configuração da planta — continuam no `localStorage`.

## Fora do escopo desta etapa

Cliente, login e sincronização. O app continua 100% `localStorage`; nada nele
fala com o Supabase ainda. As próximas etapas são: camada de acesso + login,
migração one-shot da base local, outbox de sync e service worker.
