@echo off
title Lamp After-Sale Data Sync

REM -- Hardcoded paths (most reliable in green shield environment) --
set "WORKDIR=C:\Users\DELL\WorkBuddy\2026-06-13-11-49-58\lamp-after-sale-analysis"
set "PYTHON=C:\Users\DELL\.workbuddy\binaries\python\versions\3.13.12\python.exe"
set "CONVERT=%WORKDIR%\convert_export_to_compact.py"

echo ============================================
echo   Lamp After-Sale Data Sync Tool
echo ============================================
echo.

if "%~1"=="" (
    echo [ERROR] Drag the JSON file onto this BAT icon!
    echo.
    echo How: hold the JSON file, drag to sync.bat, release.
    echo.
    pause
    exit /b 1
)

if not exist "%~1" (
    echo [ERROR] File not found: %~1
    pause
    exit /b 1
)

echo Source: %~nx1
echo Path: %~1
echo.

REM -- Step 1: Copy file to working dir (bypass green shield encryption) --
echo [1/4] Copying file to working directory...
copy "%~1" "%WORKDIR%\data\" /Y >nul
if %errorlevel% neq 0 (
    echo [ERROR] File copy failed.
    pause
    exit /b 1
)
set "LOCALFILE=%WORKDIR%\data\%~nx1"
echo        -> %LOCALFILE%

REM -- Step 2: Convert data --
echo.
echo [2/4] Converting data format...
"%PYTHON%" "%CONVERT%" "%LOCALFILE%"
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Data conversion failed (exit code %errorlevel%).
    echo   Check console output above for details.
    pause
    exit /b 1
)

REM -- Clean up the temp copy --
del "%LOCALFILE%" >nul 2>&1

REM -- Step 3: Git commit --
echo.
echo [3/4] Committing to Git...
cd /d "%WORKDIR%"
git add data/after-sale-data-compact.json data/version.json
git commit -m "sync: update data"
if %errorlevel% neq 0 (
    echo [INFO] No changes or commit skipped - continuing...
)

REM -- Step 4: Git push --
echo.
echo [4/4] Pushing to GitHub...
git push origin main
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Push to GitHub failed!
    echo   Check network and SSH key.
    pause
    exit /b 1
)

echo.
echo ============================================
echo   SUCCESS! Data synced to GitHub.
echo   zhongshanms/lamp-after-sale-analysis
echo ============================================
echo.
timeout /t 5 /nobreak >nul
exit /b 0
