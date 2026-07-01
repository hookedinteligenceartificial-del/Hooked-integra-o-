# Bot de Atendimento + Base de Conhecimento (Google Sheets)

`n8n/workflows/bot-atendimento-completo.json` é o **seu workflow de
atendimento atual** (o mesmo que você já usa em produção — Webhook, Switch,
buffer no Redis, bloqueio quando o suporte responde manualmente, AI Agent
com Gemini, envio pela Evolution API etc.) **com os nodes novos já
adicionados e conectados**, para parar de depender de você mesmo ligar os
fios entre dois workflows separados.

Nada do que já existia foi alterado ou removido — só foram adicionados
nodes novos, em paralelo, nos pontos certos.

## O que foi adicionado

### 1. Captura de toda mensagem (suporte x cliente) — tempo real

O node **"from me?1"** já existente separa `fromMe = true` (mensagem seu,
suporte) de `fromMe = false` (mensagem do cliente). Foram adicionados dois
novos ramos, em paralelo com o que já existia:

- Saída **TRUE** → também vai para **"Preparar Log (Suporte)"**
- Saída **FALSE** → também vai para **"Preparar Log (Cliente)"**

Os dois alimentam o mesmo node **"Salvar Mensagem (Base de Conhecimento)"**
(Postgres), que grava cada mensagem em uma tabela `support_messages`, já
marcando corretamente quem enviou.

Isso roda no fluxo principal, mensagem por mensagem, sem atrasar nem mudar a
resposta ao cliente — é só um "espelho" gravando em paralelo.

### 2. Mineração diária + gravação no Google Sheets

Um segundo gatilho, independente do Webhook, roda 1x por dia (02:00):

```
Gerar Base de Conhecimento (Diário)  [Schedule Trigger]
  → Definir Janela de Busca            (Code: lembra até onde já processou)
  → Buscar Mensagens Novas              (Postgres: só o que é novo desde a última vez)
      → Agrupar em Sessões de Atendimento   (Code: agrupa por conversa/tempo)
          → Agente Extrator de Perguntas Frequentes  (reaproveita o MESMO
            Google Gemini Chat Model que o bot principal já usa)
          → Parsear Respostas da IA
          → Salvar Pergunta e Resposta (Sheets)
      → Atualizar Marca D'água          (lembra até onde processou, pra não repetir)
```

A IA olha o transcript de cada conversa (rotulado "Cliente:"/"Suporte:") e
extrai só as dúvidas técnicas reais com resposta útil — sem inventar nada
que não esteja na conversa, ignorando saudação, cobrança etc. — e grava
`question`, `answer` e `category` na sua planilha.

## Pré-requisitos

1. **Postgres**: rode `n8n/sql/schema.sql` uma vez no mesmo banco que você
   já usa para o "Postgres Chat Memory1" (cria a tabela `support_messages`).
   Não precisa de extensão nenhuma, é só Postgres normal.
2. **Uma planilha Google Sheets nova**, com a primeira linha assim:

   | question | answer | category |
   |---|---|---|

   Essa é a planilha "que você vai cadastrar" — pode ser separada da
   planilha "base de conhecimento" que o bot já usa hoje para responder
   (aquela é a fonte que o bot lê para responder o cliente; esta nova é o
   destino onde a IA grava o que aprendeu das conversas reais). Depois, se
   quiser, você mesmo revisa e copia as melhores linhas para a planilha que
   o bot usa para responder.

## Passo a passo depois de importar

1. Importe `bot-atendimento-completo.json` no n8n (ele substitui/atualiza o
   workflow do bot — confira se é isso que você quer antes de sobrescrever o
   atual).
2. Nos dois nodes novos do Postgres (**"Salvar Mensagem (Base de
   Conhecimento)"** e **"Buscar Mensagens Novas"**), a credencial já vem
   apontada para "Postgres account" (a mesma que o "Postgres Chat Memory1"
   usa) — confira se o ID bateu certo depois de importar; se não, selecione
   de novo.
3. No node **"Salvar Pergunta e Resposta (Sheets)"**: abra o node e, no
   campo de planilha/aba, **selecione a sua nova planilha** de Perguntas e
   Respostas (os valores que vieram no JSON são só placeholder). A
   credencial do Google já vem preenchida com a mesma conta ("Google cloud
   todos") que o node "base de conhecimento" já usa.
4. Ative o workflow.

## Ajustes que você provavelmente vai querer revisar

- **Horário da mineração diária**: `0 2 * * *` no node "Gerar Base de
  Conhecimento (Diário)".
- **Prompt de extração**: `systemMessage` no node "Agente Extrator de
  Perguntas Frequentes".
- **Deduplicação na planilha**: o node de Sheets usa "Update or append"
  casando pela coluna `question` — perguntas com o texto idêntico ao de uma
  linha já existente atualizam a resposta em vez de duplicar linha;
  variações de escrita da mesma dúvida ainda podem gerar linhas parecidas
  (a IA tenta generalizar a pergunta, mas não é perfeito) — vale uma
  revisada de vez em quando.
