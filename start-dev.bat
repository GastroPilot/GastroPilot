@echo off
setlocal

set "ROOT=%~dp0"

echo Starte GastroPilot Dev-Services...

start "GastroPilot Frontend " cmd /k "cd /d ""%ROOT%dashboard"" && npm run dev"

start "GastroPilot App (Expo)" cmd /k "cd /d ""%ROOT%restaurant-app"" && npx expo start -c"

start "GastroPilot Backend Core (8000)" cmd /k "cd /d ""%ROOT%backend"" && call .\venv\Scripts\activate && cd /d ""%ROOT%backend\services\core"" && uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload"

start "GastroPilot Backend Orders (8001)" cmd /k "cd /d ""%ROOT%backend"" && call .\venv\Scripts\activate && cd /d ""%ROOT%backend\services\orders"" && uvicorn app.main:app --host 0.0.0.0 --port 8001 --reload"

echo Alle Startbefehle wurden in neuen Fenstern gestartet.
endlocal
