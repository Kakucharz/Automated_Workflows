-- Lab 04: the six processing tables.
-- Order: artifacts -> locations -> requests -> inputs -> attempts -> outputs.

-- One identified byte sequence: an imported Lab 3 input or a derived NDVI output.
CREATE TABLE IF NOT EXISTS processing_artifacts (
    artifact_id        TEXT NOT NULL PRIMARY KEY,
    source_artifact_id TEXT UNIQUE REFERENCES artifacts (artifact_id),  -- NULL for derived outputs
    sha256             TEXT NOT NULL CHECK (length(sha256) = 64),
    size_bytes         INTEGER NOT NULL CHECK (size_bytes > 0),
    raster_json        TEXT NOT NULL CHECK (json_valid(raster_json)),
    lineage_json       TEXT NOT NULL CHECK (json_valid(lineage_json)),
    created_at         TEXT NOT NULL
);

-- One known path for an artifact; status is current state, updated by file checks.
CREATE TABLE IF NOT EXISTS processing_artifact_locations (
    location_id TEXT NOT NULL PRIMARY KEY,
    artifact_id TEXT NOT NULL REFERENCES processing_artifacts (artifact_id),
    local_path  TEXT NOT NULL UNIQUE,
    status      TEXT NOT NULL CHECK (status IN ('available', 'missing', 'corrupt')),
    checked_at  TEXT NOT NULL
);

-- One specified calculation; the fingerprint is the hash of normalized_json.
CREATE TABLE IF NOT EXISTS processing_requests (
    request_id      TEXT NOT NULL PRIMARY KEY,
    fingerprint     TEXT NOT NULL UNIQUE CHECK (length(fingerprint) = 64),
    stage           TEXT NOT NULL CHECK (length(stage) > 0),
    normalized_json TEXT NOT NULL CHECK (json_valid(normalized_json)),
    created_at      TEXT NOT NULL
);

-- One artifact filling one named role (red, nir) in a request.
CREATE TABLE IF NOT EXISTS processing_inputs (
    request_id  TEXT NOT NULL REFERENCES processing_requests (request_id),
    role        TEXT NOT NULL CHECK (length(role) > 0),
    artifact_id TEXT NOT NULL REFERENCES processing_artifacts (artifact_id),
    PRIMARY KEY (request_id, role)
);

-- One invocation trying to satisfy a request (history: never overwritten by later attempts).
CREATE TABLE IF NOT EXISTS processing_attempts (
    attempt_id             TEXT NOT NULL PRIMARY KEY,
    request_id             TEXT NOT NULL REFERENCES processing_requests (request_id),
    status                 TEXT NOT NULL
                           CHECK (status IN ('running', 'succeeded', 'failed', 'interrupted', 'reused')),
    stage                  TEXT NOT NULL CHECK (length(stage) > 0),
    started_at             TEXT NOT NULL,
    finished_at            TEXT,
    environment_json       TEXT NOT NULL CHECK (json_valid(environment_json)),
    original_config        TEXT NOT NULL,
    resolved_config_json   TEXT NOT NULL CHECK (json_valid(resolved_config_json)),
    temp_path              TEXT NOT NULL UNIQUE,
    final_path             TEXT NOT NULL UNIQUE,
    log_path               TEXT NOT NULL UNIQUE,
    receipt_json           TEXT CHECK (receipt_json IS NULL OR json_valid(receipt_json)),
    error_code             TEXT,
    error_message          TEXT,
    reused_from_attempt_id TEXT,
    UNIQUE (attempt_id, request_id),
    CHECK ((status = 'running') = (finished_at IS NULL)),
    CHECK (status <> 'succeeded' OR receipt_json IS NOT NULL),
    CHECK (status NOT IN ('failed', 'interrupted') OR error_code IS NOT NULL),
    CHECK ((status = 'reused') = (reused_from_attempt_id IS NOT NULL)),
    FOREIGN KEY (reused_from_attempt_id, request_id)
        REFERENCES processing_attempts (attempt_id, request_id)
);

-- One artifact returned by one attempt under one output role (ndvi).
CREATE TABLE IF NOT EXISTS processing_outputs (
    attempt_id  TEXT NOT NULL REFERENCES processing_attempts (attempt_id),
    role        TEXT NOT NULL CHECK (length(role) > 0),
    artifact_id TEXT NOT NULL REFERENCES processing_artifacts (artifact_id),
    PRIMARY KEY (attempt_id, role)
);

-- Lookups suggested by the contract.
CREATE INDEX IF NOT EXISTS idx_processing_attempts_request ON processing_attempts (request_id);
CREATE INDEX IF NOT EXISTS idx_processing_inputs_artifact  ON processing_inputs (artifact_id);
CREATE INDEX IF NOT EXISTS idx_processing_outputs_artifact ON processing_outputs (artifact_id);