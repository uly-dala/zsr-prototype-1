@echo off
rem ZSR prototype 1: headless checks. Result: console and logs\checks.log
setlocal
if "%GODOT_BIN%"=="" set "GODOT_BIN=%USERPROFILE%\work\programms\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
if not exist "%GODOT_BIN%" (
    echo Godot not found: %GODOT_BIN%
    echo Set GODOT_BIN to the path of the Godot console executable.
    pause
    exit /b 2
)
"%GODOT_BIN%" --headless --path "%~dp0." --script res://tests/run_checks.gd
set "RESULT=%ERRORLEVEL%"
echo.
echo Exit code: %RESULT%
if "%1"=="" pause
exit /b %RESULT%
