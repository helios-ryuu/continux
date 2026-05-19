CREATE SOURCE nyc_taxi_src (
    event_id        VARCHAR,
    event_time      TIMESTAMPTZ,
    pickup_time     TIMESTAMPTZ,
    pu_location_id  INT,
    do_location_id  INT,
    fare_amount     DOUBLE PRECISION,
    trip_distance   DOUBLE PRECISION
) WITH (
    connector               = 'kafka',
    topic                   = 'nyc-taxi-events',
    properties.bootstrap.server = 'redpanda.redpanda:9093',
    scan.startup.mode       = 'earliest'
) FORMAT PLAIN ENCODE JSON;
