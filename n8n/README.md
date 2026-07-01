# Suporte - Base de Conhecimento a partir das conversas do bot

Este diretório contém dois workflows do n8n que, **juntos**, transformam as
conversas reais entre o suporte e os clientes (capturadas hoje pelo bot de
atendimento em Evolution API) em uma base de conhecimento pronta para ser
usada por RAG (busca semântica) em outro bot.

Nada disso mexe no workflow do bot de atendimento existente além de um único
node novo (explicado abaixo). São dois workflows separados, cada um com sua
responsabilidade:

| Workflow | O que faz | Quando roda |
|---|---|---|
| `1-captura-mensagens-suporte.json` | Recebe cada mensagem (sua e do cliente) e grava em `support_messages` | Tempo real, 1x por mensagem |
| `2-gerar-base-conhecimento.json` | Agrupa as conversas do dia em sessões, usa IA para extrair pares de pergunta/resposta, gera embedding e salva/atualiza em `knowledge_base` | 1x por dia (agendado, 02:00) |

## Pré-requisitos

1. **Postgres com a extensão `pgvector`** instalada (`CREATE EXTENSION vector;`).
   Rode `n8n/sql/schema.sql` uma vez no seu banco antes de tudo — ele cria as
   tabelas `support_messages` e `knowledge_base`. Testado localmente em
   Postgres 16 + pgvector 0.6.
2. Uma credencial **Postgres** cadastrada no n8n.
3. Uma credencial **OpenAI API** cadastrada no n8n (usada para extrair as
   perguntas/respostas do transcript e para gerar os embeddings).

## Passo a passo

### 1. Importar os workflows

No n8n: `Workflows > Import from File` e importe os dois arquivos desta
pasta. Depois de importar, abra cada node `Postgres` e `HTTP Request` e
selecione suas próprias credenciais (elas não vêm preenchidas — os IDs no
JSON são só placeholders).

### 2. Ligar a captura ao bot de atendimento existente

O workflow `1-captura-mensagens-suporte.json` começa com um node **Execute
Workflow Trigger** — ele não escuta o WhatsApp diretamente, ele é chamado
pelo próprio workflow do bot de atendimento. Isso evita duplicar webhook no
Evolution API ou mexer na configuração do provedor.

No workflow do **bot de atendimento** (o que já existe), adicione um node
**Execute Workflow** logo depois do node que recebe o payload do Evolution
API (`messages.upsert`), com:

- Workflow: `Suporte - Captura de Mensagens (Base de Conhecimento)`
- Mode: **Execute in background / fire-and-forget** (não precisa esperar
  resposta, é só um log)
- Input: passar o mesmo item recebido do webhook do Evolution API

Isso garante que **toda mensagem, sua e do cliente**, é espelhada para este
fluxo, incluindo `key.fromMe` (`true` = você/suporte, `false` = cliente) —
é esse campo que o node "Normalizar e Preparar Insert" usa para marcar
`is_support`.

### 3. Deixar o segundo workflow agendado

`2-gerar-base-conhecimento.json` já vem com um **Schedule Trigger** (todo dia
às 02:00). Ative o workflow (toggle "Active") para ele rodar sozinho.

## Como funciona por dentro

**Workflow 1** — por mensagem:
`Execute Workflow Trigger → Code (normaliza texto e monta o INSERT) → IF (só
segue se tiver texto) → Postgres (grava em support_messages)`. Mensagens sem
texto (áudio, figurinha, reação) são descartadas nesse IF.

**Workflow 2** — uma vez por dia:
1. Busca em `support_messages` tudo que ainda não foi processado.
2. Agrupa as mensagens por conversa em "sessões de atendimento" (uma sessão
   termina quando passam mais de 30 minutos sem mensagem — ajustável na
   constante `SESSION_GAP_MINUTES` do node "Agrupar em Sessões de
   Atendimento").
3. Manda o transcript de cada sessão para a OpenAI (`gpt-4o-mini`), pedindo
   para extrair pares de pergunta/resposta genéricos e reutilizáveis
   (ignorando saudação, cobrança, dados do cliente).
4. Para cada pergunta extraída, gera um embedding (`text-embedding-3-small`)
   e faz um "upsert por similaridade": se já existir uma pergunta muito
   parecida (distância de cosseno < 0.15) na base, só incrementa o campo
   `frequency`; senão, insere uma linha nova. É esse contador de `frequency`
   que mostra **quais são as maiores dúvidas** dos clientes.
5. Marca as mensagens da sessão como processadas — mesmo quando a sessão não
   gerou nenhuma pergunta útil — para não reprocessar o mesmo histórico
   todas as noites.

## Tabela `knowledge_base` (o que o outro bot vai consultar)

```sql
SELECT question, answer, category, frequency
FROM knowledge_base
ORDER BY embedding <=> '[...]'::vector  -- embedding da pergunta do cliente
LIMIT 3;
```

Colunas: `question`, `answer`, `category`, `confidence` (alta/média/baixa,
segundo a IA), `frequency` (quantas vezes uma dúvida parecida apareceu),
`embedding` (vector(1536), para busca semântica), `source_conversation_id`,
`first_seen`, `last_seen`.

## Ajustes que você provavelmente vai querer revisar

- **Limiar de similaridade (0.15)**: está nos nodes "Montar Query de Upsert"
  (workflow 2). Diminua para exigir mais parecença antes de agrupar como
  "mesma pergunta"; aumente para agrupar variações de forma mais agressiva.
- **Prompt de extração**: está no node "Extrair Perguntas e Respostas (IA)".
  Ajuste o tom/categorias conforme o vocabulário do sistema de ponto da
  Hooked.
- **Modelo de IA**: `gpt-4o-mini` é o padrão (custo baixo). Troque no mesmo
  node se preferir outro modelo.
- **Falha parcial na IA**: se a chamada para a OpenAI falhar no meio do
  lote da noite, a execução inteira para e nada daquele lote é marcado como
  processado — na próxima execução ele é reprocessado do zero. É um
  comportamento seguro (não perde dado), mas ineficiente; se preferir
  processar parcialmente, ative "Continue On Fail" no node HTTP Request.
