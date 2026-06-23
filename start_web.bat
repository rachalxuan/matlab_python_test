@echo off
chcp 65001 >nul
setlocal

set "ROOT=%~dp0"
set "PY_DIR=%ROOT%src\python"

echo Starting Python MATLAB server in background...
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "Start-Process -FilePath 'python' -ArgumentList 'server.py' -WorkingDirectory '%PY_DIR%' -WindowStyle Hidden"

echo Starting React web frontend...
cd /d "%ROOT%"
npm start

endlocal
