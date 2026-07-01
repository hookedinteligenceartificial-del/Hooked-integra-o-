# Bot de Atendimento + Base de Conhecimento (Google Sheets)

`n8n/workflows/bot-atendimento-completo.json` é o **seu workflow de
atendimento atual** (Webhook, Switch, buffer no Redis, bloqueio quando o
suporte responde manualmente, AI Agent com Gemini, envio pela Evolution
API etc.) **com os nodes novos já adicionados e conectados**.

Nada do que já existia foi alterado ou removido — só foram adicionados
nodes novos, em paralelo, nos pontos certos.

## Correção importante desta versão

Na primeira versão, o log de mensagens gravava direto no **Postgres**
dentro da própria execução do webhook (tempo real) — e isso travou um dos
nodes ("carregando infinito") e interferiu no atendimento normal. A causa
mais provável: esse novo node de Postgres competindo/travando com a mesma
conexão que o "Postgres Chat Memory1" usa para a memória do bot, dentro da
mesma execução que precisa responder o cliente rapidinho.

**Correção:** tirei o Postgres do caminho ao vivo. Agora, quando uma
mensagem chega (sua ou do cliente), a única coisa nova que acontece em
tempo real é um **push numa lista do Redis** — a mesma técnica que o
node "lista temporaria" (que já existia no seu fluxo) já usa, comprovadamente
rápida e sem travar nada. O Postgres só é usado 1x por dia, num gatilho
agendado completamente separado do webhook, isolado do atendimento ao vivo.

## O que foi adicionado

### 1. Captura em tempo real — só Redis, nada de banco

O node **"from me?1"** já existente (separa `fromMe = true` do suporte de
`fromMe = false` do cliente) agora também alimenta, em paralelo com o que já
existia:

```
from me?1 [TRUE]  → (já ia pra "criar chave block") → também vai pra "Preparar Log (Suporte)"
from me?1 [FALSE] → (já ia pra "buscar chave block") → também vai pra "Preparar Log (Cliente)"
```

Os dois alimentam **"Guardar Mensagem no Log (Redis)"**, que só empilha um
JSON da mensagem numa lista Redis (`hooked_suporte_log_mensagens`). Rápido,
sem chamada a banco, sem risco de travar o atendimento.

### 2. Job noturno — lê o Redis, arquiva em Postgres, extrai e grava no Sheets

Um gatilho independente (Schedule Trigger, 02:00) roda 1x por dia:

```
Gerar Base de Conhecimento (Diário)
  → Buscar Mensagens do Log (Redis)
  → Tem Mensagens Novas?  (se não tiver nada, para por aqui)
      → Preparar Inserts em Lote        (parseia o JSON de cada mensagem)
      → Arquivar Mensagens (Postgres)   (grava tudo de uma vez em support_messages)
      → Limpar Log (Redis)              (só limpa DEPOIS do Postgres confirmar —
                                          se o Postgres falhar, nada se perde,
                                          a lista continua lá pra próxima tentativa)
      → Agrupar em Sessões de Atendimento
      → Agente Extrator de Perguntas Frequentes  (reaproveita o MESMO Google
        Gemini Chat Model que o bot principal já usa)
      → Parsear Respostas da IA
      → Salvar Pergunta e Resposta (Sheets)
```

A IA olha o transcript de cada conversa (rotulado "Cliente:"/"Suporte:") e
extrai só as dúvidas técnicas reais com resposta útil — sem inventar nada
fora da conversa — e grava `question`, `answer` e `category` na planilha.

## Pré-requisitos

1. **Postgres**: rode `n8n/sql/schema.sql` uma vez no mesmo banco que o
   "Postgres Chat Memory1" já usa (cria a tabela `support_messages`, usada
   agora só como arquivo histórico, lido apenas pelo job noturno).
2. **Uma planilha Google Sheets nova**, com a primeira linha assim:

   | question | answer | category |
   |---|---|---|

## Passo a passo depois de importar

1. Importe `bot-atendimento-completo.json` no n8n (ele substitui/atualiza o
   workflow do bot — confira se é isso que você quer antes de sobrescrever).
2. Nos nodes novos do Postgres (**"Arquivar Mensagens (Postgres)"**) e Redis
   (**"Guardar Mensagem no Log (Redis)"**, **"Buscar Mensagens do Log
   (Redis)"**, **"Limpar Log (Redis)"**), confira se a credencial bateu
   certo — vêm apontadas para as mesmas contas ("Postgres account" e "Redis
   account") já usadas no resto do workflow.
3. No node **"Salvar Pergunta e Resposta (Sheets)"**: abra e selecione a
   sua planilha nova no seletor (os valores no JSON são só placeholder). A
   credencial do Google já vem preenchida com a mesma conta ("Google cloud
   todos") que o node "base de conhecimento" já usa.
4. Ative o workflow e acompanhe uma execução real (ou clique em "Test
   workflow" e mande uma mensagem de teste pelo WhatsApp) pra confirmar que
   nenhum node fica "carregando" — hoje, em tempo real, só roda Code +
   Redis, então não deve mais travar.

## Ajustes que você provavelmente vai querer revisar

- **Horário da mineração diária**: `0 2 * * *` no node "Gerar Base de
  Conhecimento (Diário)".
- **Prompt de extração**: `systemMessage` no node "Agente Extrator de
  Perguntas Frequentes".
- **Deduplicação na planilha**: o node de Sheets usa "Update or append"
  casando pela coluna `question` — perguntas com texto idêntico a uma linha
  já existente atualizam a resposta em vez de duplicar; variações de
  escrita da mesma dúvida ainda podem gerar linhas parecidas (vale uma
  revisada de vez em quando).
- **Nome da chave no Redis**: `hooked_suporte_log_mensagens`, usada nos 3
  nodes de Redis novos — só mude se esse nome já estiver em uso por outra
  coisa.
