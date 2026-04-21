CREATE SINK sink_zone_stats FROM mv_zone_stats
WITH (
    connector            = 'iceberg',
    type                 = 'upsert',
    primary_key          = 'borough,zone',
    catalog.type         = 'hosted',
    warehouse.path       = 's3://iceberg-data/',
    s3.endpoint          = 'http://minio.minio:9000',
    s3.access.key        = 'key-risingwave',
    s3.secret.key        = 'xxx',
    s3.path.style.access = 'true',
    database.name        = 'nyc',
    table.name           = 'zone_stats'
);
