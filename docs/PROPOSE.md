# ĐỀ CƯƠNG ĐỒ ÁN MÔN HỌC

## 1. Tên Đề Tài

- **Tiếng Việt:** Xây dựng kiến trúc Data Lakehouse thời gian thực cho hệ thống giao thông thông minh trên cụm Kubernetes.
- **Tiếng Anh:** Building a Real-Time Data Lakehouse Architecture for Intelligent Transportation Systems on a Kubernetes Cluster.

## 2. Bài Báo Nền Tảng

- **Tên bài báo:** *Ursa: A Lakehouse-Native Data Streaming Engine for Kafka*.
- **Tác giả:** Matteo Merli, Sijie Guo, Penghui Li, Hang Chen, Neng Lu.
- **Nơi công bố:** Proceedings of the VLDB Endowment, Volume 18, 08/2025.
- **Đường dẫn PDF:** <https://www.vldb.org/pvldb/vol18/p5184-guo.pdf>.

## 3. Câu Chuyện Và Vấn Đề Cốt Lõi

Trong hệ thống giao thông thông minh, dữ liệu di chuyển là một luồng sự kiện liên tục. Kiến trúc Data Lakehouse truyền thống giải quyết tốt bài toán lưu trữ và truy vấn phân tích, nhưng vẫn đặt ra câu hỏi vận hành:

> Làm thế nào để cập nhật logic phân tích luồng khi hệ thống đang phục vụ mà không làm gián đoạn truy vấn, không mất dữ liệu và vẫn giữ khả năng quan sát?

Đề tài Continux không chỉ dựng một data pipeline, mà còn kiểm chứng cách vận hành một pipeline streaming lakehouse trên Kubernetes tài nguyên giới hạn, bao gồm replay ingest, theo dõi dashboard và Blue/Green cutover ở lớp materialized view.

## 4. Dataset

Hệ thống sử dụng **NYC Taxi & Limousine Commission (TLC) Trip Record Data**:

- **Nguồn dataset:** <https://registry.opendata.aws/nyc-tlc-trip-records-pds/>
- **Bản thực nghiệm:** Yellow Taxi tháng được cấu hình trong runbook
- **Convert nguồn:** Parquet được convert sang JSONL trước khi replay
- **Dữ liệu tham chiếu:** TLC Taxi Zone lookup, upload lên MinIO trước khi RisingWave nạp vào bảng `tlc_zone`

Phân tách dữ liệu:

- **Luồng dữ liệu động:** Vector đọc JSONL và phát event vào Redpanda topic `nyc-taxi-events`.
- **Dữ liệu tham chiếu tĩnh:** Taxi Zone CSV được upload lên MinIO bucket `tlc-zone`.
- **Xử lý luồng:** RisingWave join stream với lookup table và duy trì materialized views.
- **Đầu ra lakehouse:** RisingWave sink ghi kết quả xuống Apache Iceberg trên MinIO.

## 5. Lý Do Chọn Bài Báo Và Khoảng Trống Bổ Sung

Bài báo **Ursa** phù hợp vì tập trung vào hướng lakehouse-native streaming: đưa dữ liệu từ Kafka-compatible log vào lakehouse với chi phí vận hành và độ trễ thấp hơn. Tuy nhiên, phạm vi của Ursa chủ yếu ở lớp ingestion/streaming engine, chưa đi sâu vào vận hành cập nhật logic phân tích ở lớp ứng dụng dữ liệu.

Continux bổ sung góc nhìn vận hành:

1. **Tách kho trạng thái:** RisingWave lưu trạng thái/checkpoint trên MinIO, tách compute khỏi storage để giảm rủi ro mất trạng thái khi workload thay đổi.
2. **Blue/Green trong engine:** logic SQL mới được triển khai thành materialized view song song, kiểm tra mức sẵn sàng rồi swap tên view bằng thao tác nguyên tử.
3. **GitOps + quan sát hệ thống:** Argo CD quản lý manifest, VictoriaMetrics/Grafana ghi lại mức sẵn sàng, tài nguyên, cutover và tính toàn vẹn.

## 6. Chỉ Số Và Tiêu Chí Đánh Giá

| Nhóm chỉ số | Mô tả | Cách đo |
|-------------|-------|---------|
| **Cutover Và Triển Khai GitOps** | Đo khả năng đổi logic không gián đoạn, mức sẵn sàng, thời lượng, lỗi truy vấn và số lần khởi động lại | `ALTER MATERIALIZED VIEW ... SWAP WITH ...`, query loop liên tục bắt lỗi, exporter ghi thời lượng và mốc thời gian |
| **Chất Lượng Dữ Liệu Và Đầu Ra Lakehouse** | Đối chiếu số dòng/chuyến đi, bản ghi bị loại, đầu ra Iceberg và độ lệch theo logic | SQL đếm public/blue/green; `continux_records_rejected_total`; danh sách object Iceberg trên MinIO |
| **Hiệu Năng Streaming** | Quan sát replay ingest, event đã xử lý, lag, throughput đại diện và số dòng RisingWave/s | Log Vector, offset topic Redpanda, exporter `continux_events_processed_total`, số dòng RisingWave/s đại diện |
| **Mức Dùng Tài Nguyên Và Độ Ổn Định** | Theo dõi CPU/RAM/PVC/số lần khởi động lại trên cluster tài nguyên giới hạn | Node-exporter + kube-state-metrics qua VictoriaMetrics; `bash scripts/k3s-check.sh overview` |

Số đo cụ thể của mỗi lượt thực nghiệm được lưu tại `~/continux-demo-evidence/<RUN_ID>/` ngoài repo.

## 7. Thành Phẩm Bàn Giao

1. Cụm **K3s 3 server** chạy qua Tailscale:
   `imac`, `continux-vps`, `helios-pc`.
2. Pipeline GitOps:
   `Vector -> Redpanda -> RisingWave -> Apache Iceberg on MinIO`.
3. Bộ dashboard Grafana cho 4 nhóm chỉ số:
   streaming performance, resource utilization, cutover, data integrity.
4. Runbook triển khai và thực nghiệm:
   [SETUP.md](./runbook/SETUP.md), [DEMO.md](./runbook/DEMO.md) và
   [CLEANUP.md](./runbook/CLEANUP.md).
5. Báo cáo đi kèm bằng chứng:
   [REPORT.md](./REPORT.md).
6. Paper LaTeX song ngữ:
   `paper/main_vi.pdf`, `paper/main_en.pdf`, build từ source module trong `paper/src/`.

## 8. Thuật Ngữ

- **Data Lakehouse:** Kiến trúc kết hợp lưu trữ linh hoạt của Data Lake với khả năng quản trị/truy vấn phân tích của Data Warehouse.
- **Apache Iceberg:** Table format cho object storage, hỗ trợ metadata, snapshot và thay đổi schema.
- **Redpanda:** Broker tương thích Kafka API, không cần ZooKeeper.
- **RisingWave:** Streaming database dùng SQL và materialized view để xử lý luồng.
- **Vector:** Công cụ pipeline dữ liệu dùng để đọc file JSONL và phát event.
- **GitOps:** Phương pháp dùng Git làm nguồn chân lý cho trạng thái hệ thống.
- **Blue/Green Deployment:** Chiến lược duy trì hai phiên bản logic, chuyển traffic sang phiên bản mới sau khi đã sẵn sàng.
- **Zero-downtime:** Cập nhật hệ thống không gây lỗi truy vấn hoặc gián đoạn phục vụ.
