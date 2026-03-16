@echo off
setlocal

set SCRIPT_DIR=%~dp0
set MIRROR_DIR=%SCRIPT_DIR%python\mirror
set VENV_DIR=%MIRROR_DIR%\.venv
set PYTHON=%VENV_DIR%\Scripts\python.exe

:: ── Locate scrcpy (PATH or WinGet install dir) ───────────────────────────────
set SCRCPY_EXE=
where scrcpy >nul 2>&1 && set SCRCPY_EXE=scrcpy

if "%SCRCPY_EXE%"=="" (
    for /f "delims=" %%F in ('dir /s /b "%LOCALAPPDATA%\Microsoft\WinGet\Packages\Genymobile.scrcpy*\scrcpy.exe" 2^>nul') do set SCRCPY_EXE=%%F
)

if "%SCRCPY_EXE%"=="" (
    echo scrcpy not found. Installing via winget...
    winget install --id Genymobile.scrcpy -e --accept-package-agreements --accept-source-agreements
    if %ERRORLEVEL% NEQ 0 (
        echo.
        echo  [ERROR] winget install failed.
        echo  Download manually: https://github.com/Genymobile/scrcpy/releases
        pause
        exit /b 1
    )
    for /f "delims=" %%F in ('dir /s /b "%LOCALAPPDATA%\Microsoft\WinGet\Packages\Genymobile.scrcpy*\scrcpy.exe" 2^>nul') do set SCRCPY_EXE=%%F
)

:: ── Bootstrap venv ────────────────────────────────────────────────────────────
if not exist "%PYTHON%" (
    echo Setting up Python venv...
    python -m venv "%VENV_DIR%"
    if %ERRORLEVEL% NEQ 0 (
        echo  [ERROR] Failed to create venv. Is Python 3 installed?
        pause
        exit /b 1
    )
    echo Installing dependencies...
    "%PYTHON%" -m pip install --quiet -r "%MIRROR_DIR%\requirements.txt"
    if %ERRORLEVEL% NEQ 0 (
        echo  [ERROR] pip install failed.
        pause
        exit /b 1
    )
    echo.
)

:: ── Run mirror script ─────────────────────────────────────────────────────────
"%PYTHON%" "%MIRROR_DIR%\mirror.py" --scrcpy "%SCRCPY_EXE%"

endlocal
