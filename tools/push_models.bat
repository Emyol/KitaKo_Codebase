@echo off
REM Push ONNX models to connected Android device via ADB.
REM Run this once per device. Models persist across app reinstalls.
REM The app's copyModelsFromTmp() copies them to its private directory.

set ADB=C:\Users\ricba\AppData\Local\Android\sdk\platform-tools\adb.exe
set MODELS=%~dp0..\models\kitako

echo === KitaKo ONNX Model Pusher ===
echo.

REM Check device
"%ADB%" get-state >nul 2>&1
if errorlevel 1 (
    echo ERROR: No Android device connected. Connect a device and try again.
    exit /b 1
)

REM Check models directory
if not exist "%MODELS%" (
    echo ERROR: models\kitako\ directory not found at %MODELS%
    exit /b 1
)

REM Push each model (skip if already on device)
for %%F in ("%MODELS%\*.onnx") do (
    "%ADB%" shell ls /data/local/tmp/%%~nxF >nul 2>&1
    if errorlevel 1 (
        echo Pushing %%~nxF ...
        "%ADB%" push "%%F" /data/local/tmp/
    ) else (
        echo %%~nxF already on device, skipping.
    )
)

echo.
echo === Models on device ===
"%ADB%" shell ls -la /data/local/tmp/*.onnx 2>nul
echo.
echo Done. Run the app and models will be loaded automatically.
