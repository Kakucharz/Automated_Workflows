-- Lab 05: investigation queries. Each keeps its question, parameters,
-- expected columns, empty-result interpretation and next check.
PRAGMA foreign_keys = ON;

-- 1. Which expected members have never reached an application attempt? Parameters: :batch_id.  Columns: member_id, planned_request_id. Uses planned_request_id, which exists before any processing request does. Run right after setup: all six members.  In case A (missing input): the blocked member. Empty result: every expected member has at least one non-reused attempt. Next check: for each listed member, read its newest observation (state, reason).
SELECT m.member_id, m.planned_request_id
FROM batch_members AS m
WHERE m.batch_id = :batch_id
  AND NOT EXISTS (SELECT 1 FROM processing_attempts AS a
                  WHERE a.request_id = m.planned_request_id AND a.status <> 'reused')
ORDER BY m.member_id;

-- 2. Which request failed or stopped and later produced a verified result? Parameters: :batch_id.  Columns: member, request, the earlier attempt and the later producing attempt. Counting attempts would overstate delivered work: two attempts here delivered one product. Empty result: no request in this batch needed a recovery. Next check: confirm the producing attempt's output with the newest 'complete' observation.
SELECT m.member_id, m.planned_request_id AS request_id,
       bad.attempt_id AS earlier_attempt, bad.status AS earlier_status, bad.error_code,
       good.attempt_id AS producing_attempt, good.started_at AS produced_started_at
FROM batch_members AS m
JOIN processing_attempts AS bad  ON bad.request_id  = m.planned_request_id
                                AND bad.status IN ('failed', 'interrupted')
JOIN processing_attempts AS good ON good.request_id = m.planned_request_id
                                AND good.status = 'succeeded'
                                AND good.started_at > bad.started_at
JOIN processing_outputs  AS o    ON o.attempt_id = good.attempt_id
WHERE m.batch_id = :batch_id
ORDER BY m.member_id, bad.started_at;

-- 3. Which succeeded products have no location recorded as available? Parameters: :batch_id.  Columns: member, producing attempt, artifact. This reads catalogue records only: a location status is the result of the LAST check (checked_at). A file can disappear or change after that, and an 'available' row does not prove the file exists now; only hashing the file (refresh / run) establishes present state. Empty result: every product had an available location at its last check. Next check: run `refresh` to perform current file checks, then repeat this query.
SELECT m.member_id, a.attempt_id, o.artifact_id
FROM batch_members AS m
JOIN processing_attempts AS a ON a.request_id = m.planned_request_id AND a.status = 'succeeded'
JOIN processing_outputs  AS o ON o.attempt_id = a.attempt_id
WHERE m.batch_id = :batch_id
  AND NOT EXISTS (SELECT 1 FROM processing_artifact_locations AS l
                  WHERE l.artifact_id = o.artifact_id AND l.status = 'available')
ORDER BY m.member_id;

-- 4. Which members rely on old observations? Parameters: :batch_id, :before (UTC text, e.g. '2026-11-15T12:00:00Z'). Uses observed_at of each member's NEWEST observation (largest observation_id), i.e. when the coordinator last looked, not when the report was generated and not when the satellite acquired the scene. LEFT JOIN keeps never-observed members (NULL). Empty result: every member was observed at or after :before. Next check: run `refresh` (or `plan` to look without writing) before relying on them.
SELECT m.member_id, o.observation_id, o.state, o.observed_at
FROM batch_members AS m
LEFT JOIN batch_observations AS o
       ON o.batch_id = m.batch_id AND o.member_id = m.member_id
      AND o.observation_id = (SELECT MAX(x.observation_id) FROM batch_observations AS x
                              WHERE x.batch_id = m.batch_id AND x.member_id = m.member_id)
WHERE m.batch_id = :batch_id
  AND (o.observed_at IS NULL OR o.observed_at < :before)
ORDER BY m.member_id;