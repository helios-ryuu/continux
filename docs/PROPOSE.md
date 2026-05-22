# ĐỀ CƯƠNG ĐỒ ÁN MÔN HỌC

## 1. Tên đề tài

- **Tiếng Việt:** Xây dựng kiến trúc Data Lakehouse thời gian thực cho hệ thống giao thông thông minh trên cụm Kubernetes.
- **Tiếng Anh:** Building a Real-Time Data Lakehouse Architecture for Intelligent Transportation Systems on a Kubernetes Cluster.

---

## 2. Bài báo nền tảng

- **Tên bài báo:** *Ursa: A Lakehouse-Native Data Streaming Engine for Kafka*.
- **Tác giả:** Matteo Merli, Sijie Guo, Penghui Li, Hang Chen, Neng Lu.
- **Nơi công bố:** Kỷ yếu Hội nghị VLDB Endowment (PVLDB), Tập 18, Xuất bản tháng 08/2025 (Q1).
- **Đường dẫn PDF:** <https://www.vldb.org/pvldb/vol18/p5184-guo.pdf>.

---

## 3. Câu chuyện và vấn đề cốt lõi

Trong hệ thống giao thông thông minh, dữ liệu sinh ra là một luồng sự kiện liên tục, không ngừng nghỉ (ví dụ: tọa độ hàng vạn chuyến xe mỗi giây). Kiến trúc Data Lakehouse truyền thống giải quyết tốt bài toán lưu trữ và truy vấn, nhưng lại bộc lộ "điểm mù" về vận hành:

> *Làm thế nào để cập nhật các thuật toán phân tích luồng đang chạy trực tiếp mà tuyệt đối không làm gián đoạn dòng chảy của dữ liệu?*

Đề tài này không chỉ xây dựng một Data Pipeline, mà trọng tâm là thiết kế một **kiến trúc vận hành đám mây** giải quyết triệt để bài toán **Zero-Downtime** triển khai cho dữ liệu thời gian thực.

---

## 4. Nguồn gốc Dataset

Hệ thống sẽ sử dụng nguồn dữ liệu mở uy tín về giao thông đô thị: tập dữ liệu **NYC Taxi & Limousine Commission (TLC) Trip Record Data**, chứa hàng triệu bản ghi chi tiết về hành trình di chuyển của xe cộ.

- **Đường dẫn Dataset:** <https://registry.opendata.aws/nyc-tlc-trip-records-pds/>.

Nhằm tối ưu hóa tài nguyên và tập trung vào bài toán vận hành luồng dữ liệu, kiến trúc phân tách dữ liệu thành hai loại:

- **Luồng dữ liệu động:** Sử dụng **Vector** để đọc các file dữ liệu TLC tĩnh và mô phỏng lại thành luồng sự kiện xe cộ di chuyển theo thời gian thực, sau đó "bơm" trực tiếp vào Message Broker (**Redpanda**) với thông lượng cao và tránh hoàn toàn rủi ro rò rỉ bộ nhớ.
- **Dữ liệu tham chiếu tĩnh:** Bảng ánh xạ **TLC Taxi Zone** (LocationID → Zone Name, Borough) chứa 265 bản ghi do TLC công bố chính thức, được lưu trữ dưới định dạng CSV trực tiếp trên Object Storage (**MinIO**).

**RisingWave** đóng vai trò trung tâm, thực hiện JOIN thời gian thực giữa luồng sự kiện từ Redpanda và bảng TLC Taxi Zone (trên MinIO) để gắn nhãn địa lý cho từng chuyến đi, tạo đầu vào cho các khung nhìn phân tích theo Zone.

---

## 5. Lý do chọn bài báo và khoảng trống nghiên cứu

Bài báo **Ursa** là nền tảng phù hợp vì tập trung vào hướng **lakehouse-native streaming**: giảm chi phí vận hành, giảm độ trễ và ghi trực tiếp dữ liệu từ luồng Kafka-compatible xuống định dạng Lakehouse. Tuy nhiên, phạm vi của Ursa chủ yếu nằm ở lớp ingestion/streaming engine. Bài báo chưa đi sâu vào lớp vận hành phía trên: làm thế nào để cập nhật logic phân tích đang chạy trên luồng dữ liệu mà không làm gián đoạn hệ thống.

Vì vậy, đề tài này không thay thế hay thay đổi hướng công nghệ của Ursa, mà dùng một stack đã triển khai được trong môi trường K3s tài nguyên giới hạn (**Redpanda → RisingWave → MinIO/Iceberg**, điều phối bằng **ArgoCD**) để kiểm chứng khoảng trống bổ sung: **vận hành cập nhật thuật toán phân tích zero-downtime**.

Đề tài lấp đầy khoảng trống này bằng hai đóng góp chính:

### 5.1. Dịch chuyển trạng thái (State Offloading)

Sử dụng **RisingWave** làm lõi tính toán. Thay vì khóa trạng thái ở RAM cục bộ, RisingWave đồng bộ Checkpoint liên tục xuống Shared-Storage (**MinIO**), nhờ đó có thể tách biệt "Bộ não" tính toán và "Trí nhớ" hệ thống.

Các hệ thống truyền thống thường lưu trạng thái tính toán (ví dụ: đang đếm dở số lượng xe) ngay trên RAM của máy chủ (như các dịch vụ Redis cache hoặc ứng dụng Node.js/Python chạy tác vụ hàng đợi mà không có database trung gian). Nếu máy chủ khởi động lại để cập nhật, "trí nhớ" này sẽ mất. Nhóm khắc phục bằng cách dùng RisingWave để liên tục chép lưu "trí nhớ" này ra một két sắt độc lập bên ngoài (MinIO). Dù máy chủ tính toán có thay đổi, dữ liệu đang xử lý dở dang vẫn an toàn 100%.

### 5.2. Chuyển giao thuật toán không gián đoạn (In-Engine Blue/Green & GitOps)

Áp dụng **ArgoCD** để triển khai mô hình Blue/Green ở cấp độ cơ sở dữ liệu. Khi cập nhật thuật toán SQL mới, ArgoCD sẽ kích hoạt RisingWave tạo một **Materialized View** mới (Bản Green) chạy ngầm. Bản Green tự động nạp lại trạng thái từ MinIO và xử lý nối tiếp offset từ Redpanda song song với Bản Blue. Chỉ khi bản Green đã bắt kịp nhịp dữ liệu thời gian thực, hệ thống mới thực hiện một **giao dịch nguyên tử (Atomic Swap)** để chuyển luồng và xóa bản cũ. Quá trình này đảm bảo **thời gian chết bằng 0 (0s downtime)** và loại bỏ rủi ro trùng lặp dữ liệu.

---

## 6. Chỉ số và tiêu chí đánh giá

Để chứng minh tính hiệu quả và độ tin cậy của kiến trúc, hệ thống sẽ dùng **Vector** đọc file JSONL được convert từ bộ dữ liệu NYC TLC và bơm vào Redpanda, nhằm mô phỏng tải giao thông thực tế trên cụm **K3s** với tài nguyên giới hạn.

Hệ thống được đánh giá qua 4 nhóm chỉ số cốt lõi:

| Nhóm chỉ số | Mô tả |
|---|---|
| **Vận hành chuyển giao** *(Cutover & GitOps Deployment)* | Đo thời gian gián đoạn trong khoảnh khắc chuyển giao giữa Compute Node Blue và Green, cùng độ trễ phục hồi trạng thái để tiếp tục luồng công việc. |
| **Toàn vẹn dữ liệu** *(Data Integrity & Exactly-Once Semantics)* | Tỷ lệ mất mát dữ liệu và tỷ lệ bản ghi trùng lặp phải gần như bằng 0%, kể cả trong khoảnh khắc chuyển giao. Không xảy ra hiện tượng ghi đè, lặp bản ghi hay thất thoát sự kiện. |
| **Hiệu năng xử lý luồng** *(Streaming Performance)* | Thông lượng (events/giây); độ trễ đầu cuối; và đặc biệt là **Consumer Lag** — đo mức chênh lệch giữa dữ liệu mới vào Redpanda và khả năng xử lý của RisingWave. |
| **Tiêu thụ tài nguyên** *(Resource Utilization & Stability)* | Giám sát mức độ tiêu thụ CPU, Memory (RAM) trên toàn cụm. |

> Ghi chú triển khai v0.2.2: hoàn tất setup §1-10 mới chứng minh pipeline lakehouse chạy end-to-end. Để xem là hoàn thành đề tài theo đề cương, vẫn cần thực nghiệm và dashboard cho bốn nhóm chỉ số trên, đặc biệt là cutover Blue/Green, integrity và consumer lag/throughput.

---

## 7. Thành phẩm của đề tài

Sau khi hoàn thành, sản phẩm bàn giao bao gồm:

1. Một **cụm K3s phân tán** đang vận hành trơn tru đường ống dữ liệu với kiến trúc:
   `Vector → Redpanda → RisingWave (JOIN với TLC Taxi Zone từ MinIO) → Apache Iceberg` *(sử dụng Iceberg storage catalog trên MinIO để phù hợp RisingWave `v2.8.3`)*.
2. Một **pipeline GitOps tự động hóa** bằng ArgoCD. Khi thuật toán SQL thay đổi trên Git, ArgoCD sẽ tự động đồng bộ và kích hoạt tiến trình hoán đổi Materialized View ngầm (Background Swap) trên RisingWave, đảm bảo phiên bản mới khởi động hoàn tất trước khi thay thế bản cũ, không gián đoạn hay mất mát sự kiện.
3. Một **hệ thống giám sát thời gian thực toàn diện** (VictoriaMetrics, Grafana) trực quan hóa các biểu đồ định lượng rõ ràng, chứng minh đường ống duy trì độ trễ ổn định, kiểm soát tốt Consumer Lag và không có thời gian chết khi cập nhật thuật toán.

---

## PHỤ LỤC — THUẬT NGỮ

- **Data Warehouse (Kho dữ liệu):** Hệ thống lưu trữ dữ liệu đã được làm sạch, chuyển đổi và có cấu trúc rõ ràng (thường là dạng bảng Relational). Tối ưu hóa cho truy vấn phân tích (OLAP) và báo cáo (Business Intelligence).
- **Data Lake (Hồ dữ liệu):** Nơi lưu trữ tập trung khổng lồ chứa mọi loại dữ liệu thô: có cấu trúc (bảng SQL), bán cấu trúc (JSON, XML) và phi cấu trúc (hình ảnh, video, log files) với chi phí rất rẻ.
- **Data Lakehouse:** Kiến trúc lai kết hợp điểm mạnh của Data Warehouse và Data Lake. Cho phép lưu trữ dữ liệu thô giá rẻ của Data Lake nhưng hỗ trợ các giao dịch ACID và khả năng truy vấn nhanh của Data Warehouse.
- **MinIO:** Hệ thống lưu trữ đối tượng (Object Storage) mã nguồn mở, tương thích 100% với API của Amazon S3. Hiệu năng cao, dùng để lưu trữ file, hình ảnh, backup hoặc làm nền tảng Data Lake trên server nội bộ (On-premise).
- **Apache Iceberg (Table Format):** Định dạng bảng mã nguồn mở thế hệ mới xây dựng trên nền tảng Object Storage (như MinIO), mang lại giao dịch ACID, Time Travel và Schema Evolution. Được RisingWave hỗ trợ như một Native Engine tích hợp sâu, cho phép quản lý trực tiếp cả Checkpoint xử lý luồng lẫn Snapshot Iceberg trong cùng một giao dịch, đảm bảo tính nhất quán.
- **Data Ingestion (Thu thập dữ liệu):** Quá trình "hút" dữ liệu từ nhiều nguồn khác nhau (database, API, file, thiết bị IoT) và nạp vào hệ thống lưu trữ đích (Data Lake hoặc Database).
- **Redpanda (Message Broker):** Message Broker hiện đại tương thích hoàn toàn với API của Apache Kafka, viết bằng C++, không cần ZooKeeper hay JVM. Mọi client/tool Kafka đều hoạt động với Redpanda mà không cần thay đổi code, giảm đáng kể độ phức tạp vận hành so với stack Kafka truyền thống.
- **Offset:** Trong Kafka/Redpanda, offset là một con số nguyên (ID định danh) đánh dấu vị trí của một tin nhắn (message) cụ thể trong một hàng đợi.
- **Kubernetes (K8s):** Nền tảng mã nguồn mở tự động hóa triển khai, mở rộng quy mô và quản lý các ứng dụng được đóng gói trong container (như Docker).
- **ArgoCD (GitOps):** Công cụ triển khai liên tục (Continuous Delivery) dành riêng cho Kubernetes. Hoạt động theo nguyên tắc GitOps: Lấy repository Git làm nguồn chân lý duy nhất (Single Source of Truth).
- **Blue/Green Deployment:** Chiến lược triển khai an toàn bằng cách duy trì hai phiên bản song song: "Blue" (cũ) và "Green" (mới). Trong ngữ cảnh cơ sở dữ liệu luồng, bản Green là một Materialized View chạy ngầm; khi đã đồng bộ đầy đủ, hệ thống sẽ hoán đổi tức thì (Atomic Swap) sang Green mà không làm gián đoạn người dùng.
- **Zero-downtime (Không thời gian chết):** Kết quả của quá trình bảo trì/cập nhật mà người dùng cuối không gặp bất kỳ lỗi kết nối hay gián đoạn dịch vụ nào (uptime duy trì ở mức 99.999%).
- **RisingWave:** Cơ sở dữ liệu xử lý luồng thế hệ mới viết bằng Rust. Kiến trúc phân tách tầng tính toán (Compute) và tầng lưu trữ (Storage). Xử lý dữ liệu luồng tốc độ siêu cao bằng SQL quen thuộc, tiêu thụ cực ít RAM và không bị gián đoạn hiệu năng như các hệ thống JVM. Kể từ phiên bản 2.x, hỗ trợ Apache Iceberg như một Native Storage Engine tích hợp sâu, không cần connector trung gian.
- **Materialized View (View cụ thể hóa):** Trong bối cảnh xử lý luồng, đây là đối tượng cơ sở dữ liệu chứa kết quả của một truy vấn phân tích. Thay vì tính toán lại từ đầu, Materialized View trong RisingWave tự động cập nhật liên tục ngay khi có luồng dữ liệu mới.
- **Vector:** Công cụ xây dựng đường ống dữ liệu (Data Pipeline) siêu nhẹ và hiệu năng cao viết bằng Rust. Trong đề tài, Vector đóng vai trò trình tạo tải, đọc dữ liệu từ file tĩnh và liên tục phát thông điệp vào Redpanda để giả lập môi trường thời gian thực mà không gây tốn tài nguyên.
- **VictoriaMetrics:** Cơ sở dữ liệu chuỗi thời gian mã nguồn mở, thiết kế để xử lý lượng lớn dữ liệu giám sát nhưng tiêu thụ cực ít CPU và RAM, tối ưu tài nguyên cho cụm Kubernetes.
