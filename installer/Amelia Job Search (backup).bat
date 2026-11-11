@echo off
rem Backup launcher when the .exe is blocked. Runs the same readable PowerShell file.
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Amelia Job Search.ps1"
