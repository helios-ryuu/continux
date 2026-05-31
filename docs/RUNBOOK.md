# RUNBOOK

Runbook Continux được chia theo ba trạng thái vận hành:

1. [SETUP.md](./runbook/SETUP.md): dựng hệ thống từ máy sạch đến trạng thái sẵn sàng chạy demo.
2. [DEMO.md](./runbook/DEMO.md): bắt đầu từ tải dataset, chạy replay và Blue/Green cutover, thu kết quả và evidence.
3. [CLEANUP.md](./runbook/CLEANUP.md): dọn state demo để trở về trạng thái sau setup, trước khi tải dataset cho lượt kế tiếp.

Luồng chuẩn:

```text
SETUP -> DEMO -> CLEANUP -> DEMO -> CLEANUP -> ...
```

Các lệnh được viết để chạy trên node quản trị `imac`; khi lệnh phụ thuộc repo, bắt đầu bằng `cd ~/continux`.
