@echo off
REM ParkMe — free port 8000 (kill any leftover dev server), then run on 8000.
REM Double-click this file, or run  .\run.bat  in the terminal.
for /f "tokens=5" %%a in ('netstat -ano ^| findstr :8000 ^| findstr LISTENING') do taskkill /PID %%a /F >nul 2>&1
flutter run -d chrome --web-hostname localhost --web-port 8000
