# Suporte - Base de Conhecimento a partir das conversas do bot

Este diretório contém dois workflows do n8n que, **juntos**, capturam as
conversas reais entre o suporte e os clientes (via Evolution API) e deixam
você perguntar, por chat com IA, quais são as dúvidas mais frequentes.

| Workflow | O que faz | Como é acionado |
|---|---|---|
| `1-captura-mensagens-suporte.json` | Recebe cada mensagem (sua e do cliente) e grava em `support_messages` | Webhook, em tempo real, 1x por mensagem |
| `2-consultar-duvidas-frequentes.json` | Abre um chat onde você pergunta (ex: "quais as dúvidas mais frequentes esse mês?") e uma IA (Gemini) analisa as mensagens dos clientes e responde | Chat, sob demanda |

## Pré-requisitos

1. Uma tabela Postgres — rode `n8n/sql/schema.sql` uma vez no seu banco (cria
   `support_messages`).
2. Uma credencial **Postgres** cadastrada no n8n.
3. Uma credencial **Google Gemini (PaLM) API** cadastrada no n8n (a mesma que
   você já usa no bot de atendimento).

## Passo a passo

### 1. Importar os workflows

`Workflows > Import from File` e importe os dois arquivos desta pasta.
Depois de importar, abra cada node **Postgres** e o node **Google Gemini Chat
Model** e selecione suas próprias credenciais (os IDs no JSON são só
placeholders, não vêm preenchidos).

### 2. Ligar a captura ao fluxo do bot de atendimento

O workflow `1-captura-mensagens-suporte.json` tem seu **próprio Webhook**
(node "Receber Mensagem (Evolution API)"), então ele recebe o mesmo formato
de payload que o seu bot principal recebe (`messages.upsert` da Evolution
API, com os dados em `body.data`).

Para ele também receber as mensagens, você tem duas opções:

- **Opção A (mais simples):** se o seu provedor/instância Evolution API
  permitir configurar mais de uma URL de webhook para o mesmo evento,
  adicione a URL deste novo workflow como uma segunda URL.
- **Opção B:** no workflow do bot de atendimento já existente, logo depois do
  node "Webhook" original, adicione um node **HTTP Request** (POST) apontando
  para a URL deste novo webhook, repassando o mesmo `body` recebido. Assim
  toda mensagem que chega no bot principal é espelhada para cá também, sem
  depender de configuração no Evolution API.

Ative o workflow (toggle "Active") para o webhook ficar no ar.

### 3. Usar o chat de dúvidas frequentes

Ative também o workflow `2-consultar-duvidas-frequentes.json` e abra o chat
dele (botão "Chat" no editor do n8n, ou a URL pública do Chat Trigger). Pergunte,
por exemplo:

- "Quais são as 5 dúvidas mais comuns dos clientes essa semana?"
- "Os clientes têm reclamado de quê?"
- "Como o suporte costuma responder quando perguntam sobre justificar falta?"

O agente busca as últimas 500 mensagens **enviadas pelos clientes** (não as
suas) em `support_messages`, e a IA agrupa as parecidas e resume.

## Como funciona por dentro

**Workflow 1** — por mensagem:
`Webhook → Code (normaliza o payload e monta o INSERT) → IF "Tem Texto?"
(descarta áudio/figurinha sem legenda) → IF "Suporte ou Cliente?" (separa
pelo campo fromMe: true = você, false = cliente) → Postgres (grava em
support_messages, já marcando is_support corretamente)`.

O segundo IF ("Suporte ou Cliente?") hoje leva as duas saídas para o mesmo
node de insert — a coluna `is_support` já vem certa desde o node de
normalização. Ele foi deixado explícito no fluxo (em vez de eliminado) para
você poder plugar ali, no futuro, uma ação diferente por tipo de mensagem
(por exemplo, disparar um alerta só quando é o cliente que escreve).

**Workflow 2** — sob demanda, quando você pergunta no chat:
`Chat Trigger → Postgres (busca as últimas 500 mensagens de clientes) → Code
(formata como lista numerada com data) → AI Agent (Gemini + memória de
conversa), que recebe essa lista no system message e responde sua pergunta`.

Não há geração de embeddings nem tabela separada de FAQ — a IA lê o histórico
bruto de mensagens do cliente a cada pergunta seu e faz o agrupamento/análise
na hora. Isso é mais simples de manter, mas cada pergunta no chat manda até
500 mensagens de contexto para o Gemini; se o volume de mensagens crescer
muito, considere reduzir o `LIMIT 500` da query ou filtrar por período
(`WHERE message_timestamp > now() - interval '30 days'`).

## Ajustes que você provavelmente vai querer revisar

- **Quantas mensagens de cliente entram no contexto da IA**: `LIMIT 500` no
  node "Buscar Mensagens de Clientes" (workflow 2).
- **Modelo do Gemini**: `models/gemini-2.0-flash` no node "Google Gemini Chat
  Model". Troque se preferir outro modelo da família Gemini.
- **Tom/instruções da IA**: `systemMessage` no node "Agente de Perguntas
  Frequentes".
- **Caminho do webhook**: `captura-suporte` no node "Receber Mensagem
  (Evolution API)" (workflow 1) — mude se esse path já estiver em uso.
