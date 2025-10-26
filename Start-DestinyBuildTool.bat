@echo off
REM Destiny 2 Build Tool Launcher
REM Double-click this file to launch the tool

REM Check if PowerShell is available
where pwsh >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    REM Use PowerShell Core if available
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-DestinyBuildTool.ps1"
) else (
    REM Fall back to Windows PowerShell
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-DestinyBuildTool.ps1"
)

REM Keep window open if there was an error
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo An error occurred. Press any key to exit...
    pause >nul
)
