@echo off
REM Autopilot Registration GUID Tool Launcher
REM This batch file launches the PowerShell script with administrator privileges

setlocal enabledelayedexpansion

REM Check if running as administrator
net session >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo This tool requires administrator privileges.
    echo Attempting to elevate permissions...
    powershell -Command "Start-Process cmd -ArgumentList '/c %~s0' -Verb RunAs"
    exit /b
)

REM Get the directory where this batch file is located
set SCRIPT_DIR=%~dp0

REM Run the PowerShell script with bypass execution policy
powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%AutopilotRegistrationGUID.ps1"

pause
