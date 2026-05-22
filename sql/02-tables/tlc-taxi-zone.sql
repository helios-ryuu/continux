CREATE TABLE IF NOT EXISTS tlc_zone (
    location_id  INT PRIMARY KEY,
    borough      VARCHAR,
    zone         VARCHAR,
    service_zone VARCHAR
) WITH (
    connector             = 's3',
    s3.region_name        = 'us-east-1',
    s3.bucket_name        = 'tlc-zone',
    s3.endpoint_url       = 'http://minio.minio.svc.cluster.local:9000',
    enable_config_load    = 'true',
    match_pattern         = 'taxi_zone_lookup.csv'
) FORMAT PLAIN ENCODE CSV (delimiter = ',', without_header = false);
