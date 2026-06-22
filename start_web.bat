@echo off
chcp 65001 >nul
setlocal

set "ROOT=%~dp0"
set "PY_DIR=%ROOT%src\python"

echo Starting React web frontend...
start "CCSDS React Web" cmd /k "cd /d ""%ROOT%"" && npm start"

echo Starting Python MATLAB server...
start "CCSDS Python MATLAB Server" /min cmd /k "cd /d ""%PY_DIR%"" && python server.py"

endlocal
