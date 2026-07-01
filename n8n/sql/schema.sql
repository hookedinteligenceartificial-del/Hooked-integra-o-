CREATE TABLE IF NOT EXISTS support_messages (
    id BIGSERIAL PRIMARY KEY,
    message_id TEXT UNIQUE,
    conversation_id TEXT NOT NULL,
    contact_name TEXT,
    is_support BOOLEAN NOT NULL,
    message_text TEXT NOT NULL,
    message_timestamp TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_support_messages_conversation ON support_messages (conversation_id, message_timestamp);
CREATE INDEX IF NOT EXISTS idx_support_messages_is_support ON support_messages (is_support, message_timestamp);
