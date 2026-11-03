@echo off
chcp 65001 > nul
title HE THONG DEMO OFFLINE-FIRST TODO APP
color 0A

echo =====================================================================
echo       KHOI DONG HE THONG DEMO DONG BO ANDROID VA FASTAPI
echo =====================================================================
echo.

cd /d "%~dp0"

echo [1/3] Thiet lap thong cong ADB (Dung cho dien thoai cam cap USB)...
where adb >nul 2>nul
if %ERRORLEVEL% equ 0 (
    adb reverse tcp:8000 tcp:8000 >nul 2>nul
    echo       Da thong cong: tcp:8000 -> tcp:8000 (Dien thoai co the dung dia chi http://localhost:8000/)
) else (
    echo       Khong tim thay lenh adb trong PATH (Bo qua thong cong USB).
)

echo.
echo [2/3] Mo trinh duyet xem API Swagger UI...
start http://localhost:8000/docs

echo.
echo [3/3] Dang khoi dong FastAPI Server tai cong 8000...
echo =====================================================================
echo   SERVER DANG CHAY! (Nhan Ctrl + C neu muon tat Server)
echo =====================================================================
echo.

cd backend
if exist venv\Scripts\python.exe (
    .\venv\Scripts\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
) else (
    python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
)

pause
