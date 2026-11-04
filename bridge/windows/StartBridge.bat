@echo off
rem Double-click to start the Jayhil Bridge in watch mode.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0JayhilBridge.ps1" -Watch
pause
