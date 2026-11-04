@echo off
chcp 65001 > nul
title HE THONG DEMO OFFLINE-FIRST TODO APP
color 0A

echo =====================================================================
echo       KHOI DONG HE THONG DEMO DONG BO ANDROID VA FASTAPI
echo =====================================================================
echo.

cd /d "%~dp0"

:: 1. Kiem tra Python tren may host
where python >nul 2>nul
if %ERRORLEVEL% neq 0 (
    color 0C
    echo [LOI] Khong tim thay Python tren he thong!
    echo Vui long cai dat Python 3.10+ tai https://www.python.org/
    echo LUU Y: Khi cai dat, nho tich vao o "Add python.exe to PATH".
    echo =====================================================================
    pause
    exit /b 1
)

:: 2. Thiet lap thong cong ADB (neu co cam cap USB)
echo [1/4] Thiet lap thong cong ADB (Dung cho dien thoai cam cap USB)...
where adb >nul 2>nul
if %ERRORLEVEL% equ 0 (
    adb reverse tcp:8000 tcp:8000 >nul 2>nul
    echo       Da thong cong: tcp:8000 -> tcp:8000 (Dien thoai co the dung http://localhost:8000/)
) else (
    echo       (Khong tim thay adb trong PATH - bo qua thong cong USB).
)

:: 3. Kiem tra va tu dong thiet lap moi truong ao Backend (venv)
echo.
echo [2/4] Kiem tra moi truong Backend Python...
cd backend

if not exist .env (
    if exist .env.example (
        copy .env.example .env >nul
    )
)

if not exist venv\Scripts\python.exe (
    echo       Moi truong venv chua ton tai. Dang tu dong tao venv...
    python -m venv venv
    if %ERRORLEVEL% neq 0 (
        color 0C
        echo [LOI] Khong the tao moi truong ao venv!
        pause
        exit /b 1
    )
)

:: Kiem tra neu chua cai dat thu vien thi tu dong chay pip install
if not exist venv\Scripts\uvicorn.exe (
    echo       Dang tu dong cai dat cac thu vien can thiet (FastAPI, Uvicorn, SQLAlchemy)...
    echo       (Qua trinh nay chi dien ra 1 lan duy nhat khi moi clone du an ve).
    .\venv\Scripts\python.exe -m pip install --upgrade pip >nul 2>nul
    .\venv\Scripts\pip.exe install -r requirements.txt
    if %ERRORLEVEL% neq 0 (
        color 0C
        echo [LOI] Khong the cai dat thu vien tu requirements.txt!
        pause
        exit /b 1
    )
    echo       Cai dat thu vien thanh cong!
)

:: 4. Nap du lieu mau vao Database neu chua co
echo.
echo [3/4] Kiem tra du lieu mau (Seed Data)...
.\venv\Scripts\python.exe seed.py

:: 5. Mo trinh duyet va khoi dong FastAPI Server
echo.
echo [4/4] Mo trinh duyet xem API Swagger UI va khoi dong Server...
start http://localhost:8000/docs

echo =====================================================================
echo   SERVER DANG CHAY TAI: http://localhost:8000/ (Hoac http://0.0.0.0:8000/)
echo   Swagger UI: http://localhost:8000/docs
echo   Nhan Ctrl + C neu muon tat Server
echo =====================================================================
echo.

.\venv\Scripts\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

pause
