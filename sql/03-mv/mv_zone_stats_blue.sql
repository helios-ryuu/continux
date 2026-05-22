CREATE MATERIALIZED VIEW IF NOT EXISTS mv_zone_stats_blue AS
SELECT
    z.borough,
    z.zone,
    COUNT(*)             AS trip_count,
    SUM(t.fare_amount)   AS total_fare,
    AVG(t.trip_distance) AS avg_distance
FROM nyc_taxi_src t
JOIN tlc_zone     z ON t.pu_location_id = z.location_id
GROUP BY z.borough, z.zone;

-- Public alias — tạo một lần, không drop khi swap
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_zone_stats AS
SELECT * FROM mv_zone_stats_blue;
