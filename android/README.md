# Android App – Offline-First Todo (Kotlin + Jetpack Compose)

> **Đề tài giữa kỳ:** Xây dựng ứng dụng Android hỗ trợ hoạt động ngoại tuyến và đồng bộ dữ liệu tự động  
> **Giảng viên hướng dẫn:** TS. Lê Văn Vang  
> **Sinh viên thực hiện:**  
> - PHẠM THANH NHÂN – 524H0020  
> - TRẦN GIA HUY – 524H0092  
>
> **Nền tảng:** Android SDK (API 26 - 35), Kotlin 2.x, Jetpack Compose, Room Database, WorkManager, Retrofit 2

---

Ứng dụng quản lý công việc hoạt động theo triết lý **Offline-First**, đồng bộ hai chiều với máy chủ trung tâm Python FastAPI:
* **Room SQLite (SSOT):** Nguồn chân lý duy nhất cho tầng giao diện người dùng. Mọi thao tác thêm / sửa / xóa / hoàn thành phản hồi tức thì ($< 10\text{ ms}$) mà không phụ thuộc vào kết nối mạng.
* **WorkManager (SyncWorker):** Tự động phát hiện mạng (`NetworkType.CONNECTED`), kích hoạt tiến trình ngầm đẩy dữ liệu, tự động thử lại khi lỗi với cơ chế giãn cách số mũ (**Exponential Backoff**).
* **Last-Write-Wins (LWW):** Giải thuật phân giải xung đột dựa trên dấu thời gian đơn điệu (`updatedAt`), thống nhất trạng thái dữ liệu đa thiết bị hoàn toàn tự động.

---

## ⚡ 1. Khởi Chạy Nhanh Cho Buổi Demo (1-Click)

1. **Khởi động Backend:** 
   * Tại thư mục gốc `Midterm-Mobile`, nhấp đúp chuột vào file **`CHAY_DEMO.bat`**.
   * Script sẽ tự động bật máy chủ FastAPI (cổng 8000), mở Swagger UI và thông cổng USB qua `adb reverse`.
2. **Chạy ứng dụng Android:**
   * Mở thư mục `android/` trong **Android Studio**.
   * Bấm nút **Run (Shift + F10)** để cài đặt lên Máy ảo (Emulator) hoặc Điện thoại thật.

---

## 2. Cấu Hình Địa Chỉ Máy Chủ (Dynamic Base URL)

Ứng dụng hỗ trợ đổi địa chỉ Server trực tiếp ngay trên giao diện mà không cần biên dịch lại mã nguồn:
* Mở app $\rightarrow$ Nhìn góc trên bên phải $\rightarrow$ Bấm **dấu 3 chấm (⋮) $\rightarrow$ Cấu hình server**:

| Thiết bị kiểm thử | Địa chỉ Base URL cần nhập | Ghi chú |
| :--- | :--- | :--- |
| **Máy ảo (Android Emulator)** | `http://10.0.2.2:8000/` | `10.0.2.2` là alias mạng trỏ về `localhost` của máy tính. |
| **Máy thật cắm cáp USB** | `http://localhost:8000/` | **Khuyên dùng khi demo:** Nhờ script `CHAY_DEMO.bat` đã chạy `adb reverse tcp:8000 tcp:8000`, điện thoại gọi thẳng `localhost` máy tính mà không sợ khác Wi-Fi trường. |
| **Máy thật chung Wi-Fi** | `http://192.168.x.x:8000/` | Dùng lệnh `ipconfig` trên Windows để lấy IP mạng Wi-Fi của laptop. |

---

## 3. Xuất File APK Cài Đặt (Deliverable D8)

Để xuất file `.apk` nộp bài cho Giảng viên:
1. Trong Android Studio, vào menu: **Build > Build Bundle(s) / APK(s) > Build APK(s)**.
2. Chờ Gradle biên dịch xong, bấm vào chữ **locate** ở góc dưới bên phải màn hình.
3. File APK nằm tại: `android/app/build/outputs/apk/debug/app-debug.apk`. Bản build này đã được ký bằng debug key nên có thể cài đặt trực tiếp lên bất kỳ thiết bị Android nào.

---

## 4. Kiến Trúc Phân Tầng & Luồng Dữ Liệu

```
UI Layer (Jetpack Compose)
       │
       ▼ (Sự kiện người dùng / StateFlow hiển thị)
TaskViewModel & ConnectivityObserver
       │
       ▼ (Gọi hàm CRUD / Gán trạng thái PENDING)
TaskRepository
       │
       ├─────────────────────────────────────────┐
       ▼ (Ghi trực tiếp SSOT)                    ▼ (Kích hoạt tác vụ ngầm)
Room DB (TaskDao & SyncLogDao)            SyncScheduler & WorkManager
       ▲                                         │
       │                                         ▼ (Chạy ngầm khi có mạng)
       └─────── Flow phát dữ liệu mới ────────── SyncEngine & Retrofit 2
                                                 │
                                                 ▼ (HTTP POST /sync & GET /tasks)
                                          FastAPI Server & SQLite
```

### 4.1. Bảng Trạng Thái Đồng Bộ (Chỉ Lưu Cục Bộ Trên Máy)
* **`PENDING` (Chưa đồng bộ - Màu cam):** Bản ghi có thay đổi cục bộ chưa được máy chủ xác nhận.
* **`SYNCING` (Đang đồng bộ):** Bản ghi đang được tiến trình ngầm gửi lên mạng.
* **`SYNCED` (Đã đồng bộ - Màu xanh lá):** Bản ghi đã được máy chủ ghi nhận an toàn (nằm trong `applied_ids`).
* **`FAILED` (Đồng bộ thất bại - Màu đỏ):** Phiên gửi gần nhất bị lỗi (rớt mạng, máy chủ sập), hệ thống sẽ tự động thử lại.

### 4.2. Tổ Chức Thư Mục Mã Nguồn
```
android/app/src/main/java/com/example/offlinefirsttodo/
├── data/
│   ├── local/          # AppDatabase, TaskEntity, TaskDao, SyncLogEntity, SyncLogDao (Room)
│   ├── remote/         # TaskApi (Retrofit), TaskDto, SyncRequest, SyncResponse, ApiProvider
│   └── repository/     # TaskRepository (Triết lý Offline-First, Monotonic Timestamp, Soft Delete)
├── sync/               # SyncEngine (Thuật toán Push/Pull, CAS), SyncWorker, SyncScheduler, SyncConfig
├── ui/                 # TaskScreen (Compose), TaskViewModel, Dialogs (Cấu hình Server, Nhật ký đồng bộ)
└── util/               # ConnectivityObserver (Lắng nghe mạng), AppPrefs, TimeFormat
```

---

## 5. Hướng Dẫn Thực Nghiệm 9 Kịch Bản Bắt Buộc (TC01 – TC09)

* **Cách bật/tắt mạng trên máy ảo / máy thật:** Kéo thanh thông báo trên cùng xuống $\rightarrow$ Bật/Tắt biểu tượng **Chế độ máy bay (Airplane mode)**.

| Mã TC | Kịch bản kiểm thử | Thao tác thực hiện | Hiện tượng quan sát |
| :---: | :--- | :--- | :--- |
| **TC01** | Tạo việc khi có mạng | Có kết nối mạng $\rightarrow$ Thêm task mới | Task lưu ngay vào Room, sau đó chuyển sang nhãn xanh **Đã đồng bộ** (`SYNCED`). Kiểm tra Swagger thấy task đã lưu. |
| **TC02** | Thao tác khi mất mạng | Bật Airplane mode $\rightarrow$ Thêm và sửa task | Thẻ trạng thái báo đỏ **OFFLINE**. Task hiện ngay với nhãn cam **Chưa đồng bộ** (`PENDING`), app mượt mà không crash. |
| **TC03** | Có mạng lại, tự đồng bộ | Tắt Airplane mode | Không cần chạm vào màn hình, sau vài giây WorkManager tự kích hoạt và chuyển toàn bộ task sang **Đã đồng bộ** (`SYNCED`). |
| **TC04** | Gián đoạn tiến trình (Kill app) | Offline, thêm task $\rightarrow$ Vuốt tắt ứng dụng đa nhiệm $\rightarrow$ Mở lại app | Dữ liệu cục bộ vẫn nguyên vẹn. Mở mạng app tự động tiếp tục chu trình đồng bộ. |
| **TC05** | Máy chủ tạm tắt | Tắt Server (bấm `Ctrl + C` ở terminal) $\rightarrow$ Bấm "Đồng bộ ngay" | Task chuyển nhãn đỏ **Đồng bộ thất bại** (`FAILED`). Bật lại Server $\rightarrow$ WorkManager tự động thử lại thành công. |
| **TC06** | Tính lặp an toàn (Gửi trùng) | Bấm liên tục nút **"Đồng bộ ngay"** nhiều lần | Máy chủ nhận diện đúng mốc thời gian $\rightarrow$ Không sinh thêm bản ghi trùng (Database vẫn chỉ có 1 task duy nhất). |
| **TC07** | Hai máy cùng sửa (Xung đột) | Cả 2 máy tắt mạng $\rightarrow$ Máy 1 sửa X thành "A", Máy 2 sửa X thành "B" $\rightarrow$ Lần lượt bật mạng | Cả 2 máy và Server đều hội tụ về phiên bản sửa sau ("B") theo giải thuật **Last-Write-Wins**. Menu 3 chấm > **Nhật ký đồng bộ** ghi rõ log xung đột. |
| **TC08** | Xóa khi mất mạng (Soft Delete) | Tắt mạng $\rightarrow$ Bấm nút Xóa task $\rightarrow$ Bật mạng lại | Task ẩn ngay trên màn hình (gán `is_deleted = true`). Khi đồng bộ không bị Server tải ngược lại. |
| **TC09** | Đo tải đồng bộ lô lớn | Tạo lô 50 – 100 task ngoại tuyến $\rightarrow$ Bật mạng đồng bộ | Mở **Menu ⋮ > Nhật ký đồng bộ** để xem chi tiết thời gian (ms), số lượng bản ghi đẩy/nhận, và tỷ lệ thành công 100%. |
