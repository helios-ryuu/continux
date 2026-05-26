# DASHBOARDS

Tài liệu này hướng dẫn đọc các dashboard Grafana. Dashboard dùng datasource `VictoriaMetrics`, kết hợp metric Kubernetes/Redpanda/RisingWave và metric thực nghiệm `continux_*` từ `config/metrics-exporter/`.

## 1. Import Dashboard

1. Mở Grafana tại `https://<grafana-domain>`.
2. Vào **Dashboards** -> **New** -> **Import**.
3. Import lần lượt các file trong thư mục `dashboards/`.
4. Khi Grafana hỏi datasource, chọn `VictoriaMetrics`.
5. Chọn time range:
   - `Last 15 minutes` khi replay hoặc cutover.
   - `Last 6 hours` khi xem xu hướng sau setup.

Các screenshot cuối được tham chiếu trong báo cáo bằng tên file, ví dụ:

```text
grafana-01-streaming-perf.png
grafana-02-resource-util.png
grafana-03-cutover.png
grafana-04-data-integrity.png
```

## 2. Quy Ước Đọc Số Liệu

Một số panel dùng PromQL dạng `... or vector(0)` để dashboard không vỡ khi metric chưa tồn tại. Vì vậy giá trị `0` cần đọc theo ngữ cảnh:

- `query errors = 0`, `consumer lag = 0`, `rejected records = 0` là kết quả tốt nếu target scrape healthy.
- `events_ingested_total = 0` trong bản này là giới hạn của RisingWave Kafka catalog metrics, không phải kết luận không ingest.
- `continux_green_ready = 0` trước khi tạo green MV là bình thường; sau khi green có dữ liệu, giá trị cần là `1`.

## 3. Dashboard `streaming-perf`

Dashboard này chứng minh pipeline ingest và xử lý luồng.

| Panel | Ý nghĩa | Diễn giải |
|-------|---------|-----------|
| `Scrape target health` | Tỷ lệ target được VictoriaMetrics scrape thành công | Sau khi exporter chạy, target health đạt mức quan sát được; kỳ vọng `100%` cho các target chính |
| `Pipeline pods ready` | Pod chính trong pipeline/redpanda/risingwave Ready | Có thể thấp hơn `100%` nếu Vector đã dừng sau replay, đây là chủ đích |
| `Consumer lag` | Lag Kafka trong cửa sổ đo | Kỳ vọng `0` khi consumer (RisingWave) bắt kịp producer (Vector) |
| `Vector and Redpanda network bytes/s` | Proxy traffic Vector -> Redpanda | Tăng khi Vector replay, giảm khi dừng Vector |
| `Topic offsets` | Offset topic theo partition | Có tín hiệu khi ingest; panel có thể phẳng sau khi dừng |
| `RisingWave rows/s` | Proxy tốc độ xử lý của RisingWave | Tăng trong replay, về thấp khi đã dừng |
| `Application events/s` | `continux_events_processed_total` và metric liên quan | Dùng kèm SQL count vì Kafka catalog metrics còn hạn chế |

Số đo cụ thể của từng lượt nằm trong `evidence/`.

## 4. Dashboard `resource-util`

Dashboard này đọc mức tiêu thụ tài nguyên và độ ổn định workload.

| Panel | Ý nghĩa | Cách đọc |
|-------|---------|----------|
| `Workload availability` | Replica ready/desired | Sau khi Vector dừng, số desired giảm theo chủ đích; không phải sự cố |
| `CPU by namespace` | CPU theo namespace | `risingwave`, `redpanda`, `pipeline`, `observability` tăng khi replay |
| `Memory by namespace` | RAM theo namespace | RisingWave, Redpanda và Grafana/VictoriaMetrics là nhóm dùng RAM chính |
| `Top pod CPU` | Pod dùng CPU nhiều nhất | Dùng để xác định bottleneck lúc replay |
| `Top pod memory` | Pod dùng RAM nhiều nhất | Dùng để theo dõi RAM iMac 8 GB |
| `Pod restarts in selected range` | Restart trong time range | Kỳ vọng `0` cho workload chính trong lúc cutover |
| `PVC used percent` | Phần trăm PVC đã dùng | MinIO/Redpanda/VictoriaMetrics còn nhiều dư địa |
| `PVC free bytes` | Dung lượng còn trống | Dùng để kiểm soát Iceberg và retention |

Số đo cụ thể của từng lượt nằm trong `evidence/`.

## 5. Dashboard `cutover`

Dashboard này phục vụ kịch bản Blue/Green cutover.

| Panel | Ý nghĩa | Diễn giải |
|-------|---------|-----------|
| `Cutover readiness proxy` | Tỷ lệ workload liên quan Ready | Dùng như tín hiệu hạ tầng trước swap |
| `Green readiness` | `continux_green_ready` | `1` sau khi green MV có dòng |
| `Latest cutover duration` | `continux_cutover_duration_seconds` | Duration của lần swap gần nhất |
| `Seconds since last swap` | Tuổi lần swap gần nhất | Dựa trên `continux_last_swap_timestamp_seconds` |
| `Serving availability` | Target RisingWave còn được scrape | Không tụt trong lúc swap |
| `Query errors during cutover` | `continux_query_errors_total` | Kỳ vọng `0` |
| `Consumer lag during swap` | Lag Kafka trong cửa sổ cutover | Kỳ vọng `0` khi consumer bắt kịp |
| `RisingWave restarts in selected range` | Restart của compactor/compute/frontend/meta | Kỳ vọng `0` |
| `Blue vs green row count` | Public/blue/green rows | Public chuyển sang logic green sau swap |

Số đo cụ thể của từng lượt nằm trong `evidence/`.

## 6. Dashboard `data-integrity`

Dashboard này đọc tính toàn vẹn dữ liệu và output lakehouse.

| Panel | Ý nghĩa | Diễn giải |
|-------|---------|-----------|
| `Public MV rows` | Số dòng `mv_zone_stats` | Số nhóm zone của lượt replay |
| `Checksum mismatch` | Cờ lệch checksum giữa các view | `0` khi so cùng logic; `1` sau cutover là expected nếu so logic mới với logic cũ |
| `Iceberg freshness` | Tuổi commit Iceberg gần nhất | Một số metric snapshot có thể chưa ánh xạ đủ, đối chiếu bằng MinIO listing |
| `MinIO PVC used` | Dung lượng PVC MinIO đã dùng | Tăng nhẹ khi Iceberg sinh Parquet |
| `Blue/green/public row count` | So sánh row count các view | Sau swap public và green-name có thể bằng nhau hoặc chênh tùy logic |
| `Rejected records/s` | Record lỗi parse | Kỳ vọng `0` |
| `RisingWave sink rows/s` | Proxy dòng source/sink | Có tín hiệu trong replay, về thấp sau khi dừng |
| `MinIO storage growth` | Tăng trưởng object store | Tăng khi Iceberg sinh Parquet |
| `Data path target health` | Target scrape theo service | Dùng để phân biệt lỗi metric với lỗi service |

Sau cutover, public MV mang logic green, còn view giữ tên `mv_zone_stats_green` chứa logic cũ. Vì vậy `Checksum mismatch = 1` trong ảnh sau cutover là kết quả có chủ đích của thử nghiệm đổi logic, không phải mất dữ liệu.

## 7. Metric `continux_*`

| Metric | Nguồn | Dùng cho |
|--------|-------|----------|
| `continux_exporter_up` | Exporter health | Xác nhận exporter được scrape |
| `continux_mv_rows{view="..."}` | `COUNT(*)` trên MV | Row count public/blue/green |
| `continux_mv_trips{view="..."}` | `SUM(trip_count)` trên MV | Trip count public/blue/green |
| `continux_events_processed_total` | Public MV trips | Proxy event xử lý |
| `continux_green_ready` | Green MV tồn tại và có dòng | Cutover readiness |
| `continux_checksum_mismatch_total` | So public/blue | Integrity cùng logic |
| `continux_records_rejected_total{reason="parse"}` | Mặc định `0` | Parser quality |
| `continux_cutover_duration_seconds` | Ghi bởi runbook cutover | Thời gian swap |
| `continux_last_swap_timestamp_seconds` | Ghi bởi runbook cutover | Tuổi lần swap |
| `continux_query_errors_total` | Ghi bởi query loop/cutover | Zero-downtime |
| `continux_iceberg_last_commit_timestamp_seconds` | RisingWave Iceberg catalog nếu có | Freshness |

Verify nhanh:

```bash
curl -s http://127.0.0.1:9108/metrics | grep '^continux_'

curl -G 'http://127.0.0.1:8428/api/v1/query' \
  --data-urlencode 'query=continux_exporter_up'
```

## 8. Kết Luận Từ Dashboard

- Pipeline có replay dữ liệu thật và MV tăng khi event được phát; số đo cụ thể nằm trong `evidence/`.
- Tài nguyên cluster nằm trong ngưỡng kiểm soát; PVC còn nhiều dung lượng.
- Cutover hoàn tất bằng `ALTER MATERIALIZED VIEW ... SWAP WITH ...`; tiêu chí thành công là query errors `0`, không có RisingWave restart, duration thấp.
- Data integrity cần đọc theo giai đoạn: mismatch `0` khi so cùng logic trước cutover; mismatch sau cutover là dấu hiệu logic mới đã khác logic cũ.
