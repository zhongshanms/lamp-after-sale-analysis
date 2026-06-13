@echo off
cd /d "%~dp0"

echo ============================================
echo   Lamp After-Sale Data Sync Tool
echo ============================================
echo.

if "%~1"=="" (
    echo [ERROR] Drag and drop the JSON file onto this BAT icon!
    echo.
    echo How: hold the JSON file, drag it onto sync.bat, release.
    echo.
    pause
    exit /b 1
)

echo File: %~nx1
echo Path: %~1
echo.

REM -- Find Python --
set PYTHON=
where python >nul 2>&1
if %errorlevel% equ 0 set PYTHON=python
if "%PYTHON%"=="" if exist "%UserProfile%\.workbuddy\binaries\python\versions\3.13.12\python.exe" set PYTHON=%UserProfile%\.workbuddy\binaries\python\versions\3.13.12\python.exe
if "%PYTHON%"=="" (
    echo [ERROR] Python not found!
    echo   Install Python or add it to system PATH.
    pause
    exit /b 1
)
echo Python: %PYTHON%
echo.

REM -- Step 1: Convert data --
echo [1/3] Converting data format...
echo ----------------------------------------
"%PYTHON%" convert_export_to_compact.py "%~1"
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Data conversion failed. Check JSON file integrity.
    pause
    exit /b 1
)

REM -- Step 2: Git commit --
echo.
echo [2/3] Committing to local Git...
echo ----------------------------------------
git add data/after-sale-data-compact.json data/version.json
git commit -m "sync: update data"
if %errorlevel% neq 0 (
    echo [INFO] No changes or commit failed - continuing to push...
)

REM -- Step 3: Git push --
echo.
echo [3/3] Pushing to GitHub...
echo ----------------------------------------
git push origin main
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Push to GitHub failed!
    echo   Check:
    echo   1. Network connectivity
    echo   2. Git SSH key configuration
    pause
    exit /b 1
)

echo.
echo ============================================
echo   SUCCESS! Data synced to GitHub.
echo   Repo: zhongshanms/lamp-after-sale-analysis
echo ============================================
echo.
timeout /t 5 /nobreak >nul
exit /b 0
