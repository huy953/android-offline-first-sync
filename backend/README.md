# Backend Đồng Bộ Hai Chiều Cho Ứng Dụng Android Offline-First

> **Đề tài giữa kỳ:** Xây dựng ứng dụng Android hỗ trợ hoạt động ngoại tuyến và đồng bộ dữ liệu tự động  
> **Công nghệ:** Python 3.12, FastAPI, SQLAlchemy 2.0, Pydantic v2, SQLite (tasks.db)

---

## 1. Kiến Trúc Hệ Thống (Layered Architecture)

Hệ thống được tổ chức thành các tầng phân tách độc lập (Separation of Concerns), giúp mã nguồn dễ bảo trì, mở rộng và kiểm thử:

```
backend/
├── app/
│   ├── __init__.py
│   ├── main.py               # Điểm khởi tạo FastAPI app, cấu hình CORS, lifespan
│   ├── config.py             # Cấu hình Pydantic BaseSettings, biến môi trường
│   ├── database.py           # Kết nối SQLAlchemy engine, SessionLocal, get_db
│   ├── models/               # Tầng Database Models (ORM)
│   │   ├── __init__.py
│   │   └── task.py           # SQLAlchemy Task model (id, title, is_completed, is_deleted, created_at, updated_at)
│   ├── schemas/              # Tầng Data Transfer Objects (DTO) & Pydantic Schemas
│   │   ├── __init__.py
│   │   └── task.py           # TaskBase, TaskCreate, TaskUpdate, TaskDTO, SyncPayload, SyncResult
│   ├── crud/                 # Tầng Data Access Layer (CRUD)
│   │   ├── __init__.py
│   │   └── task.py           # Các thao tác truy vấn cơ sở dữ liệu (create, get, update, soft_delete)
│   ├── services/             # Tầng Business Logic & Synchronization Engine
│   │   ├── __init__.py
│   │   └── sync_service.py   # Thuật toán Last-Write-Wins (LWW), xử lý batch sync
│   └── routers/              # Tầng Presentation / REST API Endpoints
│       ├── __init__.py
│       └── tasks.py          # Định tuyến HTTP endpoints (GET, POST, PUT, DELETE)
├── tests/
│   ├── __init__.py
│   ├── conftest.py           # Fixture SQLite in-memory & FastAPI TestClient
│   ├── test_api.py           # Unit & Integration tests cho REST API
│   └── test_sync.py          # Kiểm thử Idempotency (TC06), LWW (TC07), Soft Delete (TC08)
├── sample_data.json          # File dữ liệu mẫu tiêu chuẩn (Minh chứng D4)
├── seed.py                   # Script tự động nạp dữ liệu mẫu vào tasks.db
├── requirements.txt          # Danh sách thư viện phụ thuộc
├── tasks.db                  # File cơ sở dữ liệu SQLite cục bộ
└── README.md                 # Tài liệu hướng dẫn triển khai, tích hợp và kiểm thử
```

---

## 2. Mô Hình Dữ Liệu & Nguyên Lý Đồng Bộ

### 2.1. Thực thể Task (Database Entity)
| Thuộc tính | Kiểu dữ liệu | Phạm vi | Ý nghĩa chi tiết |
| :--- | :--- | :--- | :--- |
| `id` | `VARCHAR(36)` | Client & Server | Khóa chính, chuỗi UUIDv4 do Android client tự sinh khi tạo mới offline |
| `title` | `VARCHAR(255)` | Client & Server | Tiêu đề công việc (tối đa 255 ký tự, không rỗng) |
| `is_completed` | `BOOLEAN` | Client & Server | Trạng thái hoàn thành (`False`: chưa xong, `True`: đã xong) |
| `is_deleted` | `BOOLEAN` | Client & Server | Cờ xóa logic (**Soft Delete**). Không xóa vật lý khỏi database |
| `created_at` | `BIGINT` | Client & Server | Unix Epoch timestamp (mili-giây) thời điểm bản ghi được tạo ra (bất biến) |
| `updated_at` | `BIGINT` | Client & Server | Unix Epoch timestamp (mili-giây) dùng để so khớp xung đột (**Last-Write-Wins**) |

> 📌 **Lưu ý về `sync_status`**: Trường `sync_status` (`SYNCED`, `PENDING`, `SYNCING`, `FAILED`) **chỉ tồn tại trong Room DB trên thiết bị Android**. Database Backend không lưu trường này vì dữ liệu nằm trên Server mặc nhiên là dữ liệu chuẩn đã lưu thành công.

---

### 2.2. Chiến lược giải quyết xung đột: Last-Write-Wins (LWW)
Khi thiết bị Android đẩy danh sách công việc lên thông qua endpoint `POST /tasks/sync`:
1. **Bản ghi chưa tồn tại trên Server**: Server thực hiện `INSERT` bản ghi mới và ghi nhận ID vào danh sách `applied_ids`.
2. **Bản ghi đã tồn tại**: Server so khớp giá trị `updated_at`:
   - Nếu `client.updated_at > server.updated_at`: Bản ghi từ client mới hơn $\rightarrow$ Server ghi đè dữ liệu và ghi nhận ID vào `applied_ids`.
   - Nếu `client.updated_at == server.updated_at`: Yêu cầu gửi lặp (Idempotent retry do mạng chập chờn) $\rightarrow$ Giữ nguyên dữ liệu, phản hồi an toàn vào `applied_ids`.
   - Nếu `client.updated_at < server.updated_at`: Bản ghi trên server mới hơn bản ghi client gửi lên $\rightarrow$ Bỏ qua ghi đè để bảo toàn dữ liệu mới nhất, ghi nhận ID vào `ignored_ids`.

---

### 2.3. Xóa logic (Soft Delete)
Để hỗ trợ ứng dụng hoạt động ngoại tuyến:
- Khi người dùng bấm xóa task, hệ thống **không** xóa vật lý (`DELETE FROM tasks`).
- Bản ghi được cập nhật `is_deleted = True` và nâng `updated_at` lên thời điểm hiện tại.
- Khi các thiết bị khác thực hiện **Incremental Pull** (`GET /tasks?since={last_sync_time}`), server vẫn trả về các bản ghi này để Room SQLite phía Android nhận diện và cập nhật/xóa khỏi giao diện người dùng.

---

### 2.4. Tính Lặp An Toàn (Idempotency)
Nếu kết nối mạng chập chờn khiến client gửi lại cùng một payload nhiều lần, cơ chế LWW đảm bảo không gây ra lỗi `500`, không sinh ra các bản ghi trùng lặp (không duplicate task ID) và duy trì tính toàn vẹn dữ liệu.

---

## 3. Cài Đặt Môi Trường & Khởi Chạy (Setup & Run Guide)

### 3.1. Khởi chạy nhanh (1-Click Demo)
* **Cách nhanh nhất:** Ra thư mục gốc `Midterm-Mobile` và nhấp đúp chuột vào file **`CHAY_DEMO.bat`**:
  * Tự động khởi động máy chủ FastAPI tại cổng `8000` (lắng nghe `0.0.0.0`).
  * Tự động cấu hình chuyển tiếp cổng USB (`adb reverse tcp:8000 tcp:8000`) cho điện thoại cắm cáp.
  * Tự động mở trình duyệt web hiển thị trang **Swagger UI** tại [http://localhost:8000/docs](http://localhost:8000/docs).

### 3.2. Cài đặt thư viện thủ công
Tại thư mục `backend`:
```powershell
# Tạo môi trường ảo (nếu chưa có)
python -m venv venv

# Kích hoạt môi trường ảo:
# Windows (PowerShell):
.\venv\Scripts\Activate.ps1
# Windows (CMD):
.\venv\Scripts\activate.bat

# Cài đặt các gói phụ thuộc
pip install -r requirements.txt
```

### 3.3. Khởi chạy Server thủ công
Lắng nghe trên `0.0.0.0` để cả Emulator và điện thoại thật đều kết nối được:
```powershell
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

- **Truy cập Swagger UI trực quan:** `http://localhost:8000/docs`
- **Kiểm tra trạng thái máy chủ (Healthcheck):** `http://localhost:8000/health`

### 3.4. Nạp dữ liệu mẫu ban đầu (Sample Data Seed)
Hệ thống cung cấp sẵn file dữ liệu mẫu `sample_data.json`. Để khởi tạo bảng và nạp dữ liệu mẫu vào `tasks.db`, chạy lệnh:
```powershell
python seed.py
```
*(Ghi chú: Script `CHAY_DEMO.bat` ở thư mục gốc cũng tự động thực hiện thao tác này trước khi mở server).*

---

## 4. Hướng Dẫn Kết Nối Từ Thiết Bị Android

Ứng dụng Android hỗ trợ **Cấu hình Base URL động** ngay trên giao diện (Vào menu **⋮ > Cấu hình server**):

| Trường hợp thử nghiệm | Địa chỉ Base URL cần nhập | Ghi chú |
| :--- | :--- | :--- |
| **Máy ảo Android Emulator** | `http://10.0.2.2:8000/` | `10.0.2.2` là alias mạng đặc biệt của máy ảo trỏ về localhost máy tính host. |
| **Máy thật cắm cáp USB** | `http://localhost:8000/` | **Khuyên dùng khi demo:** Chạy lệnh `adb reverse tcp:8000 tcp:8000` (đã tích hợp trong `CHAY_DEMO.bat`), không lo đổi Wi-Fi trường. |
| **Máy thật chung Wi-Fi** | `http://192.168.x.x:8000/` | Dùng lệnh `ipconfig` trên Windows để lấy IP mạng Wi-Fi của laptop. |

---

## 5. Danh Sách API Endpoints

### 5.1. Incremental Pull (Lấy dữ liệu đồng bộ tăng dần)
- **Method**: `GET`
- **Path**: `/tasks?since={timestamp}`
- **Tham số Query**:
  - `since` (mặc định = 0): Timestamp Unix epoch tính bằng mili-giây. Server chỉ trả về các task có `updated_at > since`.
- **Phản hồi**: `200 OK`
```json
[
  {
    "id": "e4b6c968-3e4a-4a25-83e9-79f90240db71",
    "title": "Hoàn thành bài tập Mobile",
    "is_completed": true,
    "is_deleted": false,
    "created_at": 1700000001000,
    "updated_at": 1700000003000
  }
]
```

### 5.2. Batch Push Sync (Đồng bộ đẩy lên kèm Last-Write-Wins)
- **Method**: `POST`
- **Path**: `/tasks/sync`
- **Request Body** (chấp nhận object `{"tasks": [...]}` hoặc mảng `[...]`):
```json
{
  "tasks": [
    {
      "id": "e4b6c968-3e4a-4a25-83e9-79f90240db71",
      "title": "Hoàn thành bài tập Mobile (Client update)",
      "is_completed": true,
      "is_deleted": false,
      "created_at": 1700000001000,
      "updated_at": 1700000005000
    }
  ]
}
```
- **Phản hồi**: `200 OK`
```json
{
  "applied_ids": [
    "e4b6c968-3e4a-4a25-83e9-79f90240db71"
  ],
  "ignored_ids": [],
  "server_time": 1700000005120
}
```

### 5.3. Tạo Mới Task Đơn Lẻ
- **Method**: `POST`
- **Path**: `/tasks`
- **Phản hồi**: `201 Created`

### 5.4. Cập Nhật Task Đơn Lẻ
- **Method**: `PUT`
- **Path**: `/tasks/{task_id}`
- **Phản hồi**: `200 OK`

### 5.5. Xóa Logic Task (Soft Delete)
- **Method**: `DELETE`
- **Path**: `/tasks/{task_id}`
- **Phản hồi**: `200 OK` (Bản ghi được gán `is_deleted = true`)

---

## 6. Chạy Bộ Kiểm Thử Tự Động (Test Suite)

Hệ thống đi kèm bộ kiểm thử toàn diện với SQLite in-memory, kiểm chứng độc lập và không ảnh hưởng đến cơ sở dữ liệu thật:
```powershell
# Đứng tại thư mục backend và chạy pytest qua môi trường ảo:
.\venv\Scripts\python.exe -m pytest -v
```

### Các kịch bản kiểm thử trọng tâm:
1. `test_api.py`: Kiểm thử toàn diện các luồng CRUD, HTTP 404, lọc tăng dần qua query param `since`.
2. `test_sync.py::test_tc06_idempotency_repeated_sync`: Kiểm thử gửi lặp payload (Idempotency).
3. `test_sync.py::test_tc07_conflict_resolution_last_write_wins`: Kiểm thử xung đột LWW (bỏ qua bản ghi cũ, áp dụng bản ghi mới).
4. `test_sync.py::test_tc08_soft_delete_synchronization`: Kiểm thử đồng bộ xóa logic hai chiều.
5. `test_sync.py::test_tc09_batch_sync_many_records`: Kiểm thử đồng bộ theo lô số lượng lớn bản ghi.
