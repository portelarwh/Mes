# MES — Apontamento de Produção

App web simples (um único `index.html`, sem dependências) para fazer apontamentos
manuais ao lado da máquina: **produção, paradas, ociosidade, espera e refugo** —
com dashboard de OEE, gauges e ranking de paradas.

## Como usar

Abra o `index.html` no navegador do celular. Para ter HTTPS (necessário para a
tela ficar sempre acesa / Wake Lock) e instalar como app, publique via **GitHub
Pages**: Settings → Pages → branch `main` → `/ (root)`.

### Fluxo de uma medição

1. **Máquinas** → cadastre a máquina (nome, setor, capacidade nominal em
   peças/minuto — ex.: 100 pçs/min — e **meta de OEE em %**).
2. **Apontar** → escolha a máquina e toque no estado atual:
   - ▸ **Produção** — a contagem teórica sobe (capacidade × tempo produzindo);
   - ▸ **Parada** — escolhe o motivo (com badge **planejada / não planejada**;
     motivos planejados como setup e limpeza não pedem classificação de falha)
     e, para os não planejados, o **tipo**:
     **Falha** (sensor, alarme, travamento, automação), **Quebra** (dano
     físico, troca de peça) ou **Operacional** (setup, limpeza…). Em falhas e
     quebras, toque em **“Manutenção chegou”** quando o técnico chegar — isso
     alimenta MTTA e MTTR;
   - ▸ **Ociosa** — sem insumo;
   - ▸ **Esperando** — aguardando a máquina da frente puxar.

   Um interruptor na tela permite escolher entre **parada com detalhe** (pede
   o motivo na hora) e **parada simples** (só registra que parou; o motivo
   pode ser definido depois). Todas as marcações da medição aparecem numa
   lista com botão ✎ para **corrigir** — trocar o estado (ex.: marcou Ociosa
   mas era Esperando) ou definir/alterar o motivo de uma parada.

   Tocar em qualquer estado **encerra o anterior** — apontar uma parada sempre
   interrompe a produção. Os 4 cronômetros acumulam em tempo real.
   Cada botão de estado mostra o **tempo somado** daquele estado, e o card de
   Produção aceita uma **produção parcial** a qualquer momento — dela saem a
   média real (pçs/min), as **microparadas** (tempo produzindo que não virou
   peça) e o **OEE parcial ao vivo**, real e da máquina.
3. **Finalizar** → informe a **produção real** contada e o **refugo**. O app
   mostra a diferença real × teórica e salva o apontamento.
   Um apontamento **fechado** pode ser editado depois pelo botão ✎ na lista
   do Dashboard: corrigir marcações, produção e refugo, ou **reabrir** para
   voltar a medir (o intervalo fechado→reaberto não conta em nenhum tempo).
4. **Dashboard** → OEE (gauge **verde se ≥ meta, vermelho se abaixo**),
   Disponibilidade, Performance e Qualidade lado a lado, indicadores de
   manutenção (MTBF, MTBB, MTTA, MTTR), distribuição do tempo, principais
   motivos de parada (com split planejadas × não planejadas) e resumo por
   máquina, com filtro de período (hoje / 7 / 30 dias / tudo).
5. **Manual** → digite os dados de um período já encerrado (tempo total,
   paradas, ocioso, espera, produção entregue e refugo) e veja o OEE na hora,
   com a barra "para onde foi o tempo": a diferença entre o teórico do tempo
   operando e o entregue vira o tempo equivalente de **microparadas / espera /
   ritmo reduzido não apontados**. Ex.: 60min, 10min de parada, 10 pçs/min,
   400 entregues → caberiam 500; os 100 que faltam = 10min perdidos. Dá para
   salvar o cálculo como apontamento no Dashboard.
6. **Relatório executivo** → botão no topo do Dashboard gera um relatório de
   uma página (A4 paisagem) com OEE real, Pareto de paradas, produção,
   manutenção, distribuição do tempo e tabela por máquina — exportável em
   **PNG** (download direto) ou **PDF** (diálogo de impressão do navegador).

## Dois OEEs — linha cíclica

Numa linha cíclica uma máquina não deve ser penalizada porque a máquina da
frente não puxou. Por isso o app mostra sempre dois números:

- **OEE real (linha)** — toda a janela medida entra na base: paradas,
  ociosidade e espera. É a perda real do fluxo.
- **OEE da máquina** — tira da base o que não é responsabilidade dela. Em
  **Máquinas → Cálculo do OEE** você decide se *Ociosa (sem insumo)* e
  *Esperando* contam como parada da máquina (padrão: não contam).

## Motivos de parada

Configuráveis na aba Máquinas: tipo (nome), descrição, classificação
**planejada / não planejada**, tempo padrão e **a quais máquinas se aplicam**
— uma, várias ou todas. Ao apontar, só aparecem os motivos válidos para a
máquina em medição.

## Desktop

Em telas a partir de 900px o app troca a barra inferior por um menu no topo e
distribui os cards em colunas (2 colunas até 1280px, 3 acima disso), com os
quatro estados lado a lado e os gauges numa linha só. Motivos planejados
podem ter um **tempo padrão** (ex.: 2 min): se a parada real passar disso
(ex.: 4 min), os 2 min do padrão contam como planejados e os 2 min restantes
como **não planejados** — o **estouro**, que mede a variação operacional. O
app avisa em tempo real quando a parada estoura o padrão, e o estouro aparece
destacado no Dashboard e no relatório executivo.

## Cálculos

| Métrica | Fórmula | Objetivo |
|---|---|---|
| Contagem teórica | capacidade (pçs/min) × tempo em Produção | — |
| Disponibilidade real | tempo produzindo ÷ tempo total medido | ↑ |
| Disponibilidade da máquina | tempo produzindo ÷ (total − ociosidade/espera excluídas) | ↑ |
| Performance | produção real ÷ produção teórica | ↑ |
| Qualidade | (real − refugo) ÷ real | ↑ |
| **OEE real (linha)** | Disp. real × Performance × Qualidade | ≥ meta |
| **OEE da máquina** | Disp. da máquina × Performance × Qualidade | ≥ meta |
| Tempo efetivo | produção real ÷ capacidade nominal | — |
| Microparadas | tempo produzindo − tempo efetivo | ↓ |
| MTBF | tempo produzindo ÷ nº de falhas (falhas + quebras) | ↑ |
| MTBB | tempo produzindo ÷ nº de quebras (dano físico) | ↑ |
| MTTA | média (chegada da manutenção − início da parada) | ↓ |
| MTTR | média (liberação − chegada da manutenção) | ↓ |

Sem o toque em “Manutenção chegou”, a parada inteira conta como reparo
(MTTR) e não entra no MTTA.

## Recursos

- **Tema claro e escuro** (botão ◐ no topo; segue o sistema por padrão).
- **Versão no topo direito** — constante `APP_VERSION` no início do
  `<script>` do `index.html`. **Suba o número a cada atualização.**
- **Tela sempre acesa** enquanto o app está aberto (Wake Lock API; requer
  HTTPS — o indicador “tela” fica verde quando ativo).
- **Dados no aparelho** — tudo fica em `localStorage`; funciona offline após
  o primeiro carregamento. Um apontamento em andamento sobrevive a recarregar
  a página (os tempos são derivados de timestamps).
- **Instalável** — `manifest.json` permite “Adicionar à tela inicial”.

## Estrutura

```
index.html     app completo (HTML + CSS + JS)
manifest.json  metadados PWA (instalar na tela inicial)
```
