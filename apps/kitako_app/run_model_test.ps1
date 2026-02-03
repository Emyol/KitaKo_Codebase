# SigLIP Model Integration Test Runner
# Runs the critical cross-modal similarity test on Android emulator

Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "SigLIP Model Integration Test" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host ""

# Check if emulator/device is connected
$devices = flutter devices
if ($devices -match "No devices detected") {
    Write-Host "❌ No Android device or emulator detected!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please start an emulator first:" -ForegroundColor Yellow
    Write-Host "  flutter emulators" -ForegroundColor Gray
    Write-Host "  flutter emulators --launch <emulator-name>" -ForegroundColor Gray
    exit 1
}

Write-Host "✓ Device detected" -ForegroundColor Green
Write-Host ""

# Check if models are deployed
Write-Host "Checking if models are on device..." -ForegroundColor Yellow
$siglip2Vision = adb shell "run-as com.example.kitako_app ls /data/data/com.example.kitako_app/app_flutter/onnx_models/siglip2_vision_model_fp32.onnx 2>&1"

if ($siglip2Vision -match "No such file") {
    Write-Host "⚠ SigLIP-2 models not found on device!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Run setup script first:" -ForegroundColor Yellow
    Write-Host "  .\setup_siglip2.ps1" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Or press Enter to continue anyway (test will show deployment instructions)..." -ForegroundColor Yellow
    Read-Host
} else {
    Write-Host "✓ SigLIP-2 models found on device" -ForegroundColor Green
    Write-Host ""
}

# Run the integration test
Write-Host "Running integration test..." -ForegroundColor Cyan
Write-Host ""

flutter test integration_test/siglip_model_test.dart

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "Test Complete!" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
