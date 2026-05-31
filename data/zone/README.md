# Khu Vực Staging Taxi Zone

Lệnh `bash experiments/runners/demo.sh prepare-data` tải file Taxi Zone lookup
vào thư mục này và tạo thêm bản CSV tương thích với RisingWave.

Hai file CSV sinh ra chỉ là đầu vào cục bộ khi chạy và đã được Git bỏ qua. Sau khi
thực nghiệm kết thúc, chạy `bash experiments/runners/demo.sh cleanup-local` để xóa
chúng.
