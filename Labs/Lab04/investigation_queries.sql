-- Write and retain your diagnostic queries here. Use the notebook questions.
-- Enable enforcement when opening your own SQLite session:
PRAGMA foreign_keys = ON;

-- Q1. List requests with their number of attempts, grouped by outcome.
SELECT r.request_id, r.stage, a.status, COUNT(*) AS attempts
FROM processing_requests AS r
JOIN processing_attempts AS a ON a.request_id = r.request_id
GROUP BY r.request_id, r.stage, a.status
ORDER BY r.request_id, a.status;


-- Q2. Starting from an NDVI artifact ID, find its successful producing attempt,
-- normalized request, each input role, original Lab 3 subset, scene, band and AOI.
query(CONFIG, """
SELECT o.artifact_id AS ndvi_artifact, a.attempt_id AS produced_by, a.status,
       r.request_id, r.stage, i.role, i.artifact_id AS input_artifact,
       f.artifact_id AS lab3_artifact, f.sha256 AS input_sha256,
       ast.item_id, ast.asset_key, s.aoi_json, sc.acquired_at
FROM processing_outputs   AS o
JOIN processing_attempts  AS a   ON a.attempt_id   = o.attempt_id AND a.status = 'succeeded'
JOIN processing_requests  AS r   ON r.request_id   = a.request_id
JOIN processing_inputs    AS i   ON i.request_id   = r.request_id
JOIN processing_artifacts AS pa  ON pa.artifact_id = i.artifact_id
JOIN artifacts            AS f   ON f.artifact_id  = pa.source_artifact_id
JOIN subset_requests      AS s   ON s.subset_id    = f.subset_id
JOIN assets               AS ast ON ast.asset_id   = s.asset_id
JOIN scenes               AS sc  ON sc.collection  = ast.collection AND sc.item_id = ast.item_id
WHERE o.artifact_id = ?
ORDER BY CASE i.role WHEN 'red' THEN 0 ELSE 1 END
""", (repeat["artifact_id"],))

    
-- Q3. Find failed/interrupted attempts with stage and error; retain recovery rows.
query(missing_config, """
SELECT a.attempt_id, a.status, a.stage, a.error_code,
       i.role, i.artifact_id, l.local_path, l.status AS location_status
FROM processing_attempts AS a
JOIN processing_inputs AS i ON i.request_id = a.request_id
JOIN processing_artifact_locations AS l ON l.artifact_id = i.artifact_id
WHERE a.status IN ('failed', 'interrupted')
ORDER BY a.started_at, i.role
""")

    
-- Q4. Find succeeded attempts whose returned artifact has no available location.
-- Explain why SQL alone cannot prove current filesystem availability.
    -- SQL alone cannot prove current availability: a location row is only the result of the last check. A file can be deleted or changed after checked_at; only reading the file     (size and SHA-256) establishes it now.
SELECT a.attempt_id, o.artifact_id
FROM processing_attempts AS a
JOIN processing_outputs AS o ON o.attempt_id = a.attempt_id
WHERE a.status = 'succeeded'
  AND NOT EXISTS (SELECT 1 FROM processing_artifact_locations AS l
                  WHERE l.artifact_id = o.artifact_id AND l.status = 'available');


-- Q5. Find running attempts and inspect temp/final path, receipt and output links.
SELECT a.attempt_id, a.status, a.stage, a.error_code, a.temp_path, a.final_path,
       a.receipt_json IS NOT NULL AS has_receipt, COUNT(o.role) AS output_links
FROM processing_attempts AS a
LEFT JOIN processing_outputs AS o ON o.attempt_id = a.attempt_id
WHERE a.status IN ('running', 'interrupted')
GROUP BY a.attempt_id
ORDER BY a.started_at;


-- Q6. Compare original calibration metadata with the reviewed configuration.
SELECT r.request_id, i.role,
       json_extract(pa.raster_json, '$.scale')  AS original_scale,
       json_extract(pa.raster_json, '$.offset') AS original_offset,
       json_extract(r.normalized_json, '$.settings.scaling') AS scaling,
       json_extract(r.normalized_json, '$.settings.calibration.' || i.role || '.scale')  AS reviewed_scale,
       json_extract(r.normalized_json, '$.settings.calibration.' || i.role || '.offset') AS reviewed_offset
FROM processing_requests AS r
JOIN processing_inputs    AS i  ON i.request_id   = r.request_id
JOIN processing_artifacts AS pa ON pa.artifact_id = i.artifact_id
ORDER BY r.request_id, CASE i.role WHEN 'red' THEN 0 ELSE 1 END;