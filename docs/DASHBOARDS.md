# Hướng Dẫn Đọc Dashboard Grafana

> Trạng thái `v0.2.2`: các dashboard JSON đã được chuẩn hóa để import vào Grafana với datasource `VictoriaMetrics`. Dashboard tài nguyên dùng metric Kubernetes có sẵn. Các dashboard streaming, cutover và integrity có cả panel đo từ metric hạ tầng lẫn panel thực nghiệm `continux_*` để dùng khi bổ sung exporter ứng dụng.

## 1. Cách import

1. Mở Grafana.
2. Vào **Dashboards** -> **New** -> **Import**.
3. Import lần lượt các file trong thư mục `dashboards/`.
4. Khi Grafana hỏi datasource, chọn `VictoriaMetrics`.
5. Chọn khoảng thời gian phù hợp:
   - `Last 15 minutes` khi đang replay dữ liệu hoặc chạy cutover.
   - `Last 6 hours` khi xem xu hướng tổng quát sau setup.

## 2. Quy ước đọc số liệu

Các panel dùng PromQL dạng `... or vector(0)` để dashboard không bị lỗi khi metric chưa tồn tại. Vì vậy giá trị `0` có hai khả năng:

- hệ thống thật sự đang không có lag, lỗi, mismatch hoặc throughput;
- metric tương ứng chưa được scrape hoặc exporter ứng dụng chưa chạy.

Khi một panel quan trọng luôn bằng `0`, kiểm tra lại bằng Grafana Explore với đúng tên metric trước khi kết luận.

## 3. `01-streaming-perf.json`

Dashboard này dùng để đọc hiệu năng luồng Vector -> Redpanda -> RisingWave.

| Panel | Ý nghĩa | Cách đọc |
|-------|---------|----------|
| `Scrape target health` | Tỷ lệ target Redpanda/RisingWave/observability đang trả metric | Nên gần `100%`; thấp hơn nghĩa là scrape hoặc service có vấn đề |
| `Pipeline pods ready` | Số pod chính trong `pipeline`, `redpanda`, `risingwave` đang Ready | Nên đạt `100%` trước khi đo hiệu năng |
| `Consumer lag` | Độ trễ consumer group trên topic Kafka | Nên thấp và không tăng liên tục |
| `Vector and Redpanda network bytes/s` | Proxy cho dữ liệu Vector gửi sang Redpanda | Tăng khi Vector ingest/replay dữ liệu |
| `Redpanda bytes/s` | Throughput Kafka/RPC/storage của Redpanda nếu metric được expose | Dùng để quan sát áp lực ghi vào broker |
| `Topic offsets` | Offset cuối theo partition của topic | Tăng đều khi topic nhận event |
| `RisingWave rows/s` | Tốc độ RisingWave xử lý row, có nhiều tên metric dự phòng theo phiên bản | Nên tăng khi source/MV đang nhận dữ liệu |
| `RisingWave barrier latency p95` | Độ trễ p95 của barrier hoặc processing histogram | Càng thấp càng tốt; spike cao cần đối chiếu CPU/RAM |
| `Application events/s` | Metric thực nghiệm `continux_events_ingested_total` và `continux_events_processed_total` | Chỉ có dữ liệu sau khi có exporter ứng dụng |

## 4. `02-resource-util.json`

Dashboard này là dashboard hiện có tín hiệu rõ nhất vì dựa trên metric Kubernetes/cAdvisor/kube-state-metrics.

| Panel | Ý nghĩa | Cách đọc |
|-------|---------|----------|
| `Workload availability` | Replica sẵn sàng so với replica mong muốn | Nếu thấp hơn desired, xem pod lỗi ở namespace tương ứng |
| `CPU by namespace` | CPU theo namespace | Dùng để thấy `risingwave`, `redpanda`, `pipeline` tăng tải khi ingest |
| `Memory by namespace` | RAM theo namespace | RisingWave và Redpanda tăng là bình thường khi xử lý dữ liệu |
| `Top pod CPU` | Top pod dùng CPU | Xác định pod đang chịu tải chính |
| `Top pod memory` | Top pod dùng RAM | Dùng để phát hiện memory pressure |
| `Pod restarts in selected range` | Restart trong khoảng thời gian đang chọn | Nên bằng `0` khi chạy demo ổn định |
| `PVC used percent` | Phần trăm dung lượng PVC đã dùng | Theo dõi MinIO, Redpanda, VictoriaMetrics |
| `PVC free bytes` | Dung lượng PVC còn trống | Giảm dần khi Iceberg/Redpanda/VictoriaMetrics ghi dữ liệu |

## 5. `03-cutover.json`

Dashboard này phục vụ kịch bản Blue/Green cutover. Một số panel là proxy hạ tầng, một số panel cần exporter ứng dụng để làm bằng chứng chính thức.

| Panel | Ý nghĩa | Cách đọc |
|-------|---------|----------|
| `Cutover readiness proxy` | Tỷ lệ pod Redpanda/RisingWave/Pipeline Ready | Nên là `100%` trước khi swap |
| `Green readiness` | Metric `continux_green_ready` báo view green đã bắt kịp | `1` là sẵn sàng swap, `0` là chưa sẵn sàng hoặc chưa có exporter |
| `Latest cutover duration` | Thời gian swap gần nhất | Mục tiêu là thấp và ổn định |
| `Seconds since last swap` | Tuổi của lần swap gần nhất | `0` thường nghĩa là chưa có metric swap |
| `Serving availability` | Availability scrape target RisingWave trong lúc swap | Không nên tụt về `0` khi cutover |
| `Query errors during cutover` | Lỗi truy vấn trong lúc swap | Kỳ vọng bằng `0` |
| `Consumer lag during swap` | Lag Kafka trong cửa sổ cutover | Không nên tăng kéo dài sau swap |
| `RisingWave restarts in selected range` | Restart của RisingWave trong khoảng đang xem | Nếu có restart thì chưa thể kết luận zero-downtime |
| `Blue vs green row count` | So sánh row count giữa public/blue/green view | Cần exporter `continux_mv_rows` để có dữ liệu thật |

## 6. `04-data-integrity.json`

Dashboard này đọc chất lượng dữ liệu từ RisingWave, Iceberg và MinIO.

| Panel | Ý nghĩa | Cách đọc |
|-------|---------|----------|
| `Public MV rows` | Số dòng của `mv_zone_stats` | Sau §10 kỳ vọng khoảng `260` nếu exporter SQL đã ghi metric |
| `Checksum mismatch` | Số lần lệch checksum | Kỳ vọng bằng `0` |
| `Iceberg freshness` | Thời gian từ commit Iceberg gần nhất | Tăng cao nghĩa là sink không ghi mới hoặc exporter chưa chạy |
| `MinIO PVC used` | Dung lượng PVC MinIO đã dùng | Tăng sau khi Iceberg ghi Parquet/metadata |
| `Blue/green/public row count` | So sánh row count giữa các view | Dùng để xác nhận green bắt kịp blue/public trước cutover |
| `Rejected records/s` | Bản ghi bị loại theo lý do | Kỳ vọng bằng `0` trong demo sạch |
| `RisingWave sink rows/s` | Proxy dòng vào source/sink trong RisingWave | Tăng khi source/sink đang xử lý dữ liệu |
| `MinIO storage growth` | Dung lượng object store theo thời gian | Tăng khi Iceberg ghi thêm object |
| `Data path target health` | Bảng target scrape của Redpanda/RisingWave/observability | Dùng để phân biệt lỗi metric với lỗi service |

## 7. Chỉ số đủ để kết luận đề tài

Setup §1-10 đã chứng minh pipeline end-to-end chạy được, nhưng để kết luận hoàn thành theo `docs/PROPOSE.md` cần có thêm bằng chứng đo đạc:

- throughput và lag trong lúc ingest/replay;
- độ trễ hoặc proxy latency của RisingWave;
- Blue/Green cutover với `Green readiness = 1`, `Query errors = 0`, không có RisingWave restart;
- row count public/blue/green khớp nhau;
- checksum mismatch và rejected records bằng `0`;
- Iceberg freshness hợp lý và MinIO có object Parquet/metadata mới;
- screenshot hoặc export dashboard sau khi chạy thực nghiệm.

## 8. Metric thực nghiệm cần exporter

Các metric dưới đây không tự có từ Kubernetes. Chúng cần một exporter nhỏ đọc từ `psql`, `rpk`, MinIO hoặc job kiểm thử rồi expose sang Prometheus/VictoriaMetrics:

| Metric | Nguồn đề xuất | Dùng cho |
|--------|---------------|----------|
| `continux_events_ingested_total` | Đếm event Vector/Redpanda nhận | Throughput ingest |
| `continux_events_processed_total` | Đếm row RisingWave xử lý | Throughput xử lý |
| `continux_green_ready` | Query so sánh green với public/blue | Cutover readiness |
| `continux_cutover_duration_seconds` | Script swap blue/green | Thời gian cutover |
| `continux_last_swap_timestamp_seconds` | Script swap blue/green | Tuổi lần swap |
| `continux_query_errors_total` | Script bắn query trong lúc cutover | Zero-downtime |
| `continux_mv_rows` | Query `COUNT(*)` theo view | Integrity row count |
| `continux_checksum_mismatch_total` | Query checksum giữa view/sink | Integrity |
| `continux_records_rejected_total` | Kiểm thử dữ liệu lỗi hoặc log parser | Chất lượng ingest |
| `continux_iceberg_last_commit_timestamp_seconds` | Đọc metadata Iceberg/MinIO | Freshness sink |

Khi exporter chưa chạy, các panel liên quan `continux_*` có thể hiển thị `0`. Khi exporter đã chạy, các panel này mới là bằng chứng chính cho báo cáo.
