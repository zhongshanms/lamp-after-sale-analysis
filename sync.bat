@echo off
setlocal enabledelayedexpansion

REM === RE-LAUNCH with cmd /k so window NEVER auto-closes ===
if "%SYNC_LAUNCHED%"=="" (
    set "SYNC_LAUNCHED=1"
    start "" cmd /k ""%~f0" "%~1""
    exit
)

title Lamp After-Sale Data Sync

REM -- Hardcoded paths --
set "WORKDIR=C:\Users\DELL\WorkBuddy\2026-06-13-11-49-58\lamp-after-sale-analysis"
set "PYTHON=C:\Users\DELL\.workbuddy\binaries\python\versions\3.13.12\python.exe"
set "CONVERT=%WORKDIR%\convert_export_to_compact.py"
set "LOGFILE=%WORKDIR%\data\sync_log.txt"

echo ============================================
echo   Lamp After-Sale Data Sync Tool
echo ============================================
echo.

if "%~1"=="" (
    echo [ERROR] Drag the JSON file onto sync.bat!
    echo.
    echo How: Hold the JSON file, drag onto sync.bat icon, release.
    goto :end
)

if not exist "%~1" (
    echo [ERROR] File not found: %~1
    goto :end
)

echo Source: %~nx1
echo Path:   %~1
echo.

REM === Step 1: Copy to working dir (bypass green shield) ===
echo [1/4] Copying file to working directory...
copy "%~1" "%WORKDIR%\data\" /Y >nul
if %errorlevel% neq 0 (
    echo [ERROR] File copy failed (code %errorlevel%).
    echo   The file may be encrypted by green shield DLP.
    echo   Try moving the file to Desktop first, then drag again.
    goto :end
)
set "LOCALFILE=%WORKDIR%\data\%~nx1"
echo        OK

REM === Step 2: Convert data ===
echo.
echo [2/4] Converting data format...
echo        ^(24MB file takes ~30-60 seconds, please wait...^)
echo.
echo        Output also saved to: data\sync_log.txt
echo %date% %time% Sync started >>"%LOGFILE%"
"%PYTHON%" "%CONVERT%" "%LOCALFILE%" >>"%LOGFILE%" 2>&1
set "PYEXIT=!errorlevel!"
type "%LOGFILE%"
if !PYEXIT! neq 0 (
    echo.
    echo [ERROR] Conversion failed (code !PYEXIT!).
    goto :end
)

REM Clean up temp copy
del "%LOCALFILE%" >nul 2>&1

REM === Step 3: Git commit ===
echo.
echo [3/4] Committing to Git...
cd /d "%WORKDIR%"
git add data/after-sale-data-compact.json data/version.json
git commit -m "sync: update data" 2>&1
if %errorlevel% neq 0 (
    echo [INFO] No changes or commit skipped - continuing...
)

REM === Step 4: Git push ===
echo.
echo [4/4] Pushing to GitHub...
git push origin main 2>&1
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Push to GitHub failed!
    echo   Check network connection and SSH key.
    goto :end
)

echo.
echo ============================================
echo   SUCCESS!
echo   Data synced to GitHub:
echo   zhongshanms/lamp-after-sale-analysis
echo ============================================

:end
echo.
echo ========================================
echo Press any key to close this window...
pause >nul
