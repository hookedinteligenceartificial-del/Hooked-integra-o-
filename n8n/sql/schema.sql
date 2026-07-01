CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS support_messages (
    id BIGSERIAL PRIMARY KEY,
    message_id TEXT UNIQUE,
    conversation_id TEXT NOT NULL,
    contact_name TEXT,
    is_support BOOLEAN NOT NULL,
    message_text TEXT NOT NULL,
    message_timestamp TIMESTAMPTZ NOT NULL,
    processed BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_support_messages_conversation ON support_messages (conversation_id, message_timestamp);
CREATE INDEX IF NOT EXISTS idx_support_messages_processed ON support_messages (processed);

CREATE TABLE IF NOT EXISTS knowledge_base (
    id BIGSERIAL PRIMARY KEY,
    question TEXT NOT NULL,
    answer TEXT NOT NULL,
    category TEXT,
    confidence TEXT,
    frequency INTEGER NOT NULL DEFAULT 1,
    embedding vector(1536),
    source_conversation_id TEXT,
    first_seen TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_knowledge_base_embedding
    ON knowledge_base USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
