@echo off
chcp 65001 >nul
title 独立站灯饰售后工单分析系统
cd /d "%~dp0"

echo ============================================
echo   独立站灯饰售后工单分析系统 - 正在启动...
echo ============================================
echo.

REM 检查Python是否可用
python --version >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [错误] 未找到Python，请确保已安装Python 3.x
    echo.
    echo 替代访问方式:
    echo   1. 在线版: https://zhongshanms.github.io/lamp-after-sale-analysis/
    echo   2. 直接双击"独立站灯饰售后分析系统.html"
    echo      （注：部分浏览器可能限制，建议用在线版）
    echo.
    pause
    exit /b 1
)

echo [✓] Python已就绪
echo.
echo ============================================
echo   访问地址
echo ============================================
echo.
echo   桌面端: http://localhost:8000
echo.
echo   手机端（需同一WiFi）:
echo   http://你的电脑IP地址:8000
echo   （电脑IP可通过 ipconfig 命令查看）
echo.
echo   按 Ctrl+C 可停止服务器
echo ============================================
echo.

REM 打开浏览器
start "" "http://localhost:8000"

REM 启动Python HTTP服务器
python -m http.server 8000

pause
