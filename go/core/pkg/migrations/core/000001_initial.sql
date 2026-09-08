-- +goose Up

-- Kagent 1.0 baseline for fresh installations.

CREATE TABLE tool (
    id          TEXT        NOT NULL,
    server_name TEXT        NOT NULL,
    group_kind  TEXT        NOT NULL,
    created_at  TIMESTAMPTZ,
    updated_at  TIMESTAMPTZ,
    deleted_at  TIMESTAMPTZ,
    description TEXT,
    PRIMARY KEY (id, server_name, group_kind)
);
CREATE INDEX idx_tool_deleted_at ON tool(deleted_at);

CREATE TABLE toolserver (
    name           TEXT        NOT NULL,
    group_kind     TEXT        NOT NULL,
    created_at     TIMESTAMPTZ,
    updated_at     TIMESTAMPTZ,
    deleted_at     TIMESTAMPTZ,
    description    TEXT,
    last_connected TIMESTAMPTZ,
    PRIMARY KEY (name, group_kind)
);
CREATE INDEX idx_toolserver_deleted_at ON toolserver(deleted_at);

CREATE TABLE runtime_revision (
    revision                 TEXT        PRIMARY KEY,
    namespace                TEXT        NOT NULL,
    agent_template_name      TEXT        NOT NULL,
    agent_template_uid       TEXT        NOT NULL,
    harness_name             TEXT        NOT NULL,
    harness_uid              TEXT        NOT NULL,
    source_snapshot          JSONB       NOT NULL,
    egress_destinations      TEXT[]      NOT NULL DEFAULT '{}',
    actor_template_atespace  TEXT        CONSTRAINT runtime_revision_actor_template_namespace_not_null NOT NULL,
    actor_template_name      TEXT        NOT NULL,
    actor_template_uid       TEXT        NOT NULL DEFAULT '',
    created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    agent_card               BYTEA       NOT NULL,
    deletion_started_at      TIMESTAMPTZ,
    CONSTRAINT runtime_revision_actor_template_namespace_actor_template_na_key
        UNIQUE (actor_template_atespace, actor_template_name)
);

CREATE TABLE agent_template_harness_pair (
    namespace                    TEXT        NOT NULL,
    agent_template_name          TEXT        NOT NULL,
    agent_template_uid           TEXT        NOT NULL,
    harness_name                 TEXT        NOT NULL,
    harness_uid                  TEXT        NOT NULL,
    desired_revision             TEXT        NOT NULL,
    latest_successful_revision   TEXT        REFERENCES runtime_revision(revision) ON DELETE RESTRICT,
    retired_at                   TIMESTAMPTZ,
    created_at                   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    agent_template_labels        JSONB       NOT NULL DEFAULT '{}',
    PRIMARY KEY (namespace, agent_template_uid, harness_uid)
);
CREATE INDEX agent_template_harness_pair_name_idx
    ON agent_template_harness_pair (namespace, agent_template_name, harness_name);

CREATE TABLE a2a_context (
    id         UUID        PRIMARY KEY,
    user_id    TEXT        NOT NULL CHECK (user_id <> ''),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE agent_instance_checkpoint (
    id                     UUID        PRIMARY KEY,
    source_instance_id     UUID        NOT NULL,
    user_id                TEXT        NOT NULL,
    request_id             TEXT        NOT NULL,
    head_task_id           TEXT        NOT NULL,
    history_sequence       BIGINT      NOT NULL,
    snapshot_atespace      TEXT        NOT NULL,
    snapshot_uri           TEXT        NOT NULL,
    snapshot_content_scope TEXT        NOT NULL,
    tag_uid                TEXT        NOT NULL DEFAULT '',
    state                  TEXT        NOT NULL,
    data                   BYTEA       NOT NULL,
    source_context_id      UUID        NOT NULL REFERENCES a2a_context(id) ON DELETE RESTRICT,
    prepared_revision      TEXT        REFERENCES runtime_revision(revision) ON DELETE RESTRICT,
    source_labels          JSONB       NOT NULL DEFAULT '{}'
        CHECK (jsonb_typeof(source_labels) = 'object'),
    CHECK (snapshot_content_scope IN ('FULL', 'DATA')),
    CHECK (state IN ('CREATING', 'READY', 'FAILED', 'DELETING')),
    UNIQUE (user_id, request_id)
);
CREATE INDEX agent_instance_checkpoint_list_idx
    ON agent_instance_checkpoint (source_instance_id, id);
CREATE UNIQUE INDEX agent_instance_checkpoint_one_creating_idx
    ON agent_instance_checkpoint (source_instance_id)
    WHERE state = 'CREATING';

CREATE TABLE agent_instance (
    id                   UUID        PRIMARY KEY,
    user_id              TEXT        NOT NULL CHECK (user_id <> ''),
    request_id           TEXT        NOT NULL,
    prepared_revision    TEXT        REFERENCES runtime_revision(revision) ON DELETE RESTRICT,
    state                TEXT        NOT NULL,
    labels               JSONB       NOT NULL DEFAULT '{}',
    data                 BYTEA       NOT NULL,
    operation            TEXT        NOT NULL DEFAULT 'NONE',
    context_id           UUID        NOT NULL REFERENCES a2a_context(id) ON DELETE RESTRICT,
    source_checkpoint_id UUID        REFERENCES agent_instance_checkpoint(id) ON DELETE RESTRICT,
    CONSTRAINT agent_instance_operation_check
        CHECK (operation IN ('NONE', 'CREATE', 'SUSPEND', 'RESUME', 'DELETE')),
    CHECK (state IN ('CREATING', 'READY', 'SUSPENDED', 'FAILED')),
    UNIQUE (user_id, request_id)
);
CREATE INDEX agent_instance_user_id_id_idx
    ON agent_instance (user_id, id);

CREATE TABLE agent_instance_share (
    id          UUID        PRIMARY KEY,
    instance_id UUID        NOT NULL REFERENCES agent_instance(id) ON DELETE CASCADE,
    permission  TEXT        NOT NULL CHECK (permission IN ('READ_ONLY', 'READ_WRITE')),
    token_hash  BYTEA       NOT NULL UNIQUE,
    data        BYTEA       NOT NULL
);
CREATE INDEX agent_instance_share_instance_idx
    ON agent_instance_share (instance_id, id);

CREATE TABLE agent_instance_task (
    context_id             UUID        CONSTRAINT agent_instance_task_instance_id_not_null NOT NULL REFERENCES a2a_context(id) ON DELETE CASCADE,
    id                     TEXT        NOT NULL,
    state                  TEXT        NOT NULL,
    status_timestamp       TIMESTAMPTZ,
    data                   BYTEA       NOT NULL,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    initial_message_id     TEXT,
    request_hash           BYTEA,
    snapshot_atespace      TEXT,
    snapshot_uri           TEXT,
    snapshot_content_scope TEXT,
    history_sequence       BIGINT,
    PRIMARY KEY (context_id, id)
);
CREATE UNIQUE INDEX agent_instance_one_active_task_idx
    ON agent_instance_task (context_id)
    WHERE state NOT IN (
        'TASK_STATE_COMPLETED',
        'TASK_STATE_CANCELED',
        'TASK_STATE_FAILED',
        'TASK_STATE_REJECTED',
        'TASK_STATE_INPUT_REQUIRED',
        'TASK_STATE_AUTH_REQUIRED'
    );
CREATE INDEX agent_instance_task_list_idx
    ON agent_instance_task (context_id, id);
CREATE UNIQUE INDEX agent_instance_task_message_idx
    ON agent_instance_task (context_id, initial_message_id)
    WHERE initial_message_id IS NOT NULL;

CREATE TABLE agent_instance_task_event (
    sequence   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    context_id UUID        CONSTRAINT agent_instance_task_event_instance_id_not_null NOT NULL REFERENCES a2a_context(id) ON DELETE CASCADE,
    task_id    TEXT,
    data       BYTEA       NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    message_id TEXT
);
CREATE INDEX agent_instance_task_event_instance_sequence_idx
    ON agent_instance_task_event (context_id, sequence);
CREATE UNIQUE INDEX agent_instance_task_event_message_idx
    ON agent_instance_task_event (context_id, task_id, message_id)
    WHERE message_id IS NOT NULL;

CREATE VIEW unreferenced_runtime_revision AS
SELECT r.revision FROM runtime_revision r
WHERE NOT EXISTS (
    SELECT 1 FROM agent_template_harness_pair p
    WHERE p.retired_at IS NULL
      AND (p.desired_revision = r.revision OR p.latest_successful_revision = r.revision)
)
AND NOT EXISTS (
    SELECT 1 FROM agent_instance i WHERE i.prepared_revision = r.revision
)
AND NOT EXISTS (
    SELECT 1 FROM agent_instance_checkpoint c WHERE c.prepared_revision = r.revision
);

-- Reference acquisition and the GC claim serialize on the revision row.
-- FOR SHARE conflicts with the collector's FOR UPDATE, including when an
-- instance selected its revision before retirement but inserts afterward.
-- Missing desired revisions are allowed: pairs are persisted before compilation
-- creates the runtime row. The other references retain their existing FKs.
-- +goose StatementBegin
CREATE FUNCTION protect_runtime_revision_reference() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    field_name TEXT;
    deleting_at TIMESTAMPTZ;
BEGIN
    FOREACH field_name IN ARRAY TG_ARGV LOOP
        SELECT deletion_started_at INTO deleting_at
        FROM runtime_revision
        WHERE revision = to_jsonb(NEW) ->> field_name
        FOR SHARE;
        IF FOUND AND deleting_at IS NOT NULL THEN
            RAISE EXCEPTION 'runtime revision is being deleted'
                USING ERRCODE = '55000', CONSTRAINT = 'runtime_revision_not_deleting';
        END IF;
    END LOOP;
    RETURN NEW;
END;
$$;
-- +goose StatementEnd

CREATE TRIGGER protect_pair_runtime_revision
BEFORE INSERT OR UPDATE OF desired_revision, latest_successful_revision, retired_at
ON agent_template_harness_pair
FOR EACH ROW WHEN (NEW.retired_at IS NULL)
EXECUTE FUNCTION protect_runtime_revision_reference('desired_revision', 'latest_successful_revision');

CREATE TRIGGER protect_instance_runtime_revision
BEFORE INSERT OR UPDATE OF prepared_revision ON agent_instance
FOR EACH ROW EXECUTE FUNCTION protect_runtime_revision_reference('prepared_revision');

CREATE TRIGGER protect_checkpoint_runtime_revision
BEFORE INSERT OR UPDATE OF prepared_revision ON agent_instance_checkpoint
FOR EACH ROW EXECUTE FUNCTION protect_runtime_revision_reference('prepared_revision');

-- +goose Down

DROP TRIGGER protect_checkpoint_runtime_revision ON agent_instance_checkpoint;
DROP TRIGGER protect_instance_runtime_revision ON agent_instance;
DROP TRIGGER protect_pair_runtime_revision ON agent_template_harness_pair;
DROP FUNCTION protect_runtime_revision_reference();
DROP VIEW unreferenced_runtime_revision;

DROP TABLE agent_instance_share;
DROP TABLE agent_instance_task_event;
DROP TABLE agent_instance_task;
DROP TABLE agent_instance;
DROP TABLE agent_instance_checkpoint;
DROP TABLE a2a_context;
DROP TABLE agent_template_harness_pair;
DROP TABLE runtime_revision;
DROP TABLE toolserver;
DROP TABLE tool;
