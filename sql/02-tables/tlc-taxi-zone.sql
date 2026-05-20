CREATE TABLE tlc_zone (
    location_id  INT PRIMARY KEY,
    borough      VARCHAR,
    zone         VARCHAR,
    service_zone VARCHAR
) WITH (
    connector             = 's3',
    s3.region_name        = 'us-east-1',
    s3.bucket_name        = 'tlc-zone',
    s3.endpoint_url       = 'http://minio.minio.svc.cluster.local:9000',
    s3.credentials.access = 'key-risingwave',
    s3.credentials.secret = '<replace: key-risingwave secret từ MinIO console SETUP §7.2>',
    s3.path               = 'taxi_zone_lookup.csv'
) FORMAT PLAIN ENCODE CSV (delimiter = ',', without_header = false);
