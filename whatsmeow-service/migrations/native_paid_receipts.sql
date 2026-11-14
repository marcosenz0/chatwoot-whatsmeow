CREATE TABLE IF NOT EXISTS whatsmeow_native_paid_receipts (
    channel_id text NOT NULL,
    order_id uuid NOT NULL,
    nonce text NOT NULL UNIQUE CHECK (nonce ~ '^[a-fA-F0-9]{32}$'),
    request_hash text NOT NULL CHECK (request_hash ~ '^[a-f0-9]{64}$'),
    purpose text NOT NULL CHECK (purpose IN ('v1','test-v1')),
    status text NOT NULL CHECK (status IN ('reserved','submitted','rejected_conflict','rejected_expired','uncertain','observed_on_target')),
    created_at timestamptz NOT NULL DEFAULT NOW(),
    updated_at timestamptz NOT NULL DEFAULT NOW(),
    PRIMARY KEY (channel_id, order_id)
);
