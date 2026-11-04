import json
import os
import sys

# Đảm bảo import được app package khi chạy độc lập
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from app.database import Base, SessionLocal, engine
from app.models.task import Task


def seed_database():
    """Khởi tạo cấu trúc bảng và nạp dữ liệu mẫu ban đầu từ sample_data.json."""
    Base.metadata.create_all(bind=engine)
    
    current_dir = os.path.dirname(os.path.abspath(__file__))
    json_path = os.path.join(current_dir, "sample_data.json")
    
    if not os.path.exists(json_path):
        print(f"[!] Khong tim thay file du lieu mau: {json_path}")
        return

    with open(json_path, "r", encoding="utf-8") as f:
        tasks_data = json.load(f)

    db = SessionLocal()
    inserted_count = 0
    updated_count = 0

    try:
        for item in tasks_data:
            task_id = item["id"]
            existing = db.query(Task).filter(Task.id == task_id).first()
            if not existing:
                new_task = Task(
                    id=item["id"],
                    title=item["title"],
                    is_completed=item.get("is_completed", False),
                    is_deleted=item.get("is_deleted", False),
                    created_at=item["created_at"],
                    updated_at=item["updated_at"],
                )
                db.add(new_task)
                inserted_count += 1
            else:
                existing.title = item["title"]
                existing.is_completed = item.get("is_completed", False)
                existing.is_deleted = item.get("is_deleted", False)
                existing.created_at = item["created_at"]
                existing.updated_at = item["updated_at"]
                updated_count += 1

        db.commit()
        print(f"[+] Nap du lieu mau thanh cong! (Them moi: {inserted_count}, Cap nhat: {updated_count})")
    except Exception as e:
        db.rollback()
        print(f"[x] Loi khi nap du lieu mau: {e}")
    finally:
        db.close()


if __name__ == "__main__":
    seed_database()
