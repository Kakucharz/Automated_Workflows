-- Write your own diagnostic SQL for the five new tables.
-- One worked example follows. Add your case queries below it.
SELECT r.run_id,r.command,a.item_id,a.asset_key,s.aoi_key,d.status,d.stage,
       d.network_bytes,d.http_status,d.error_code,d.error_message
FROM download_attempts d JOIN runs r ON r.run_id=d.run_id
JOIN subset_requests s ON s.subset_id=d.subset_id
JOIN assets a ON a.asset_id=s.asset_id
ORDER BY d.started_at,d.attempt_id;

SELECT a.asset_key, l.local_path, f.sha256,f.size_bytes AS saved_bytes, d.network_bytes AS http_bytes,l.status AS location_status,l.checked_at
FROM subset_requests AS s
JOIN assets AS a ON a.asset_id = s.asset_id
JOIN artifacts AS f ON f.artifact_id = s.latest_artifact_id
JOIN artifact_locations AS l ON l.artifact_id = f.artifact_id
JOIN download_attempts AS d ON d.attempt_id  = f.created_by_attempt_id
ORDER BY a.asset_key;

-- Case A: show failed band, partial success and the later recovery history.
-- A1. Failed run, failed band, failure stage and bytes received. Rerun after recovery: the original failure stays, new attempts are added.
SELECT r.status AS run_status, a.asset_key, d.status, d.stage,
       d.network_bytes, d.http_status, d.error_code, d.error_message
FROM download_attempts AS d
JOIN runs            AS r ON r.run_id    = d.run_id
JOIN subset_requests AS s ON s.subset_id = d.subset_id
JOIN assets          AS a ON a.asset_id  = s.asset_id
ORDER BY d.started_at;
 
-- A2. Which band has an artifact and which has none. LEFT JOIN keeps every request; a missing artifact appears as NULL.
SELECT a.asset_key, s.status AS request_status, s.latest_artifact_id,
       f.size_bytes, l.status AS location_status
FROM subset_requests AS s
JOIN assets AS a ON a.asset_id = s.asset_id
LEFT JOIN artifacts          AS f ON f.artifact_id = s.latest_artifact_id
LEFT JOIN artifact_locations AS l ON l.artifact_id = f.artifact_id
ORDER BY a.asset_key;
 
-- A3. For comparison only: the same with an INNER JOIN. Before recovery, the failed nir request disappears from this result.
SELECT a.asset_key, s.status AS request_status, s.latest_artifact_id
FROM subset_requests AS s
JOIN assets    AS a ON a.asset_id    = s.asset_id
JOIN artifacts AS f ON f.artifact_id = s.latest_artifact_id;

-- Case B: show successful historical acquisition but current missing/corrupt location.
-- B1. History with the command of each run: the original successful acquire, the verify that detected FILE_MISSING, and the recovery attempts.
SELECT r.command, r.status AS run_status, a.asset_key, d.status, d.stage,
       d.network_bytes, d.error_code, d.artifact_id
FROM download_attempts AS d
JOIN runs            AS r ON r.run_id    = d.run_id
JOIN subset_requests AS s ON s.subset_id = d.subset_id
JOIN assets          AS a ON a.asset_id  = s.asset_id
ORDER BY d.started_at;
 
-- B2. Current state: the artifact (bytes that existed, and who created them) next to its location (whether the file is available now).
SELECT a.asset_key, s.status AS request_status, f.artifact_id,
       f.created_by_attempt_id, l.local_path,
       l.status AS location_status, l.checked_at
FROM subset_requests AS s
JOIN assets AS a ON a.asset_id = s.asset_id
LEFT JOIN artifacts          AS f ON f.artifact_id = s.latest_artifact_id
LEFT JOIN artifact_locations AS l ON l.artifact_id = f.artifact_id
ORDER BY a.asset_key;
 

-- AOI identity: show one source band with separate requests for two AOIs.
SELECT a.asset_key, a.asset_id, s.subset_id, s.aoi_json,
       s.status, s.latest_artifact_id, l.local_path
FROM assets AS a
JOIN subset_requests AS s ON s.asset_id = a.asset_id
LEFT JOIN artifacts          AS f ON f.artifact_id = s.latest_artifact_id
LEFT JOIN artifact_locations AS l ON l.artifact_id = f.artifact_id
ORDER BY a.asset_key, s.aoi_json;
