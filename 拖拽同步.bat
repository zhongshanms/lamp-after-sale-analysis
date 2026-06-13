@echo off
chcp 65001 >nul
cd /d "%~dp0"

echo ============================================
echo   灯饰售后数据 自动同步工具
echo ============================================
echo.

if "%~1"=="" (
    echo [错误] 请将导出的 JSON 文件拖拽到此 BAT 图标上！
    echo.
    echo 操作方法: 鼠标按住 JSON 文件不放，拖到"拖拽同步.bat"上再松开。
    echo.
    pause
    exit /b 1
)

echo 文件: %~nx1
echo 路径: %~1
echo.

REM ── 查找 Python ──
set PYTHON=
where python >nul 2>&1
if %errorlevel% equ 0 set PYTHON=python
if "%PYTHON%"=="" if exist "C:\Users\DELL\.workbuddy\binaries\python\versions\3.13.12\python.exe" set PYTHON=C:\Users\DELL\.workbuddy\binaries\python\versions\3.13.12\python.exe
if "%PYTHON%"=="" (
    echo [错误] 未找到 Python 解释器！
    echo   请安装 Python 或将其添加到系统 PATH。
    echo.
    pause
    exit /b 1
)
echo Python: %PYTHON%
echo.

REM ── 步骤1: 转换数据 ──
echo [1/3] 正在转换数据格式...
echo ----------------------------------------
"%PYTHON%" convert_export_to_compact.py "%~1"
if %errorlevel% neq 0 (
    echo.
    echo [错误] 数据转换失败，请检查 JSON 文件是否完整。
    pause
    exit /b 1
)

REM ── 步骤2: Git 提交 ──
echo.
echo [2/3] 正在提交到本地 Git...
echo ----------------------------------------
git add data/after-sale-data-compact.json data/version.json
git commit -m "sync: update data"
if %errorlevel% neq 0 (
    echo [提示] 无新变更或提交失败（可能数据未变化），继续推送...
)

REM ── 步骤3: Git 推送 ──
echo.
echo [3/3] 正在推送到 GitHub...
echo ----------------------------------------
git push origin main
if %errorlevel% neq 0 (
    echo.
    echo [错误] 推送到 GitHub 失败！
    echo   请检查:
    echo   1. 网络是否连通
    echo   2. Git SSH 密钥是否配置
    echo.
    pause
    exit /b 1
)

echo.
echo ============================================
echo   ✅ 同步完成！
echo   数据已推送到 zhongshanms/lamp-after-sale-analysis
echo ============================================
echo.
echo 窗口将在 5 秒后自动关闭...
timeout /t 5 /nobreak >nul
exit /b 0
