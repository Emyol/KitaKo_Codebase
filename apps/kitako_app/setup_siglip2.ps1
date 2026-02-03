# SigLIP-2 Model Setup Script
# This script pushes the proper SigLIP-2 models to your Android device

$deviceId = "IV5XLBPN59BQXOWW"
$modelDir = "c:\Users\Jhezra\Documents\KitaKo_System\assets\models"
# Use app_flutter directory (matches Flutter's getApplicationDocumentsDirectory)
$appCache = "/data/data/com.example.kitako_app/app_flutter/onnx_models"

Write-Host "=== SigLIP-2 Model Setup ===" -ForegroundColor Cyan
Write-Host ""

# Check if models exist
$visionModel = "$modelDir\siglip2_vision_model_fp32.onnx"
$textModel = "$modelDir\siglip2_text_model_fp32.onnx"

if (-not (Test-Path $visionModel)) {
    Write-Host "❌ Vision model not found: $visionModel" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $textModel)) {
    Write-Host "❌ Text model not found: $textModel" -ForegroundColor Red
    exit 1
}

Write-Host "✓ Found vision model: $((Get-Item $visionModel).Length / 1MB) MB" -ForegroundColor Green
Write-Host "✓ Found text model: $((Get-Item $textModel).Length / 1MB) MB" -ForegroundColor Green
Write-Host ""

# Check device connection
Write-Host "Checking device connection..." -ForegroundColor Yellow
$devices = adb devices
if ($devices -notmatch $deviceId) {
    Write-Host "❌ Device $deviceId not connected" -ForegroundColor Red
    Write-Host "Available devices:" -ForegroundColor Yellow
    adb devices
    exit 1
}
Write-Host "✓ Device connected: $deviceId" -ForegroundColor Green
Write-Host ""

# Create cache directory on device
Write-Host "Creating cache directory on device..." -ForegroundColor Yellow
adb -s $deviceId shell "mkdir -p $appCache"
Write-Host "✓ Cache directory created" -ForegroundColor Green
Write-Host ""

# Push vision model
Write-Host "Pushing vision model (371 MB)..." -ForegroundColor Yellow
Write-Host "This will take 30-60 seconds..." -ForegroundColor Gray
$visionResult = adb -s $deviceId push $visionModel "$appCache/siglip2_vision_model_fp32.onnx" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to push vision model" -ForegroundColor Red
    Write-Host $visionResult
    exit 1
}
Write-Host "✓ Vision model pushed successfully" -ForegroundColor Green
Write-Host ""

# Push text model
Write-Host "Pushing text model (1.1 GB)..." -ForegroundColor Yellow
Write-Host "This will take 2-3 minutes..." -ForegroundColor Gray
$textResult = adb -s $deviceId push $textModel "$appCache/siglip2_text_model_fp32.onnx" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to push text model" -ForegroundColor Red
    Write-Host $textResult
    exit 1
}
Write-Host "✓ Text model pushed successfully" -ForegroundColor Green
Write-Host ""

# Verify files on device
Write-Host "Verifying models on device..." -ForegroundColor Yellow
$files = adb -s $deviceId shell "ls -lh $appCache"
Write-Host $files
Write-Host ""

Write-Host "=== Setup Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Clear app data (Settings → Apps → KitaKo → Clear storage)" -ForegroundColor White
Write-Host "2. Restart the app" -ForegroundColor White
Write-Host "3. Let it re-index images (will use SigLIP-2 automatically)" -ForegroundColor White
Write-Host "4. Search for 'cat on table' → should see similarities 0.75-0.95" -ForegroundColor White
Write-Host ""
Write-Host "Expected improvement:" -ForegroundColor Cyan
Write-Host "  Before: 0.08 - 0.12 similarity (weak)" -ForegroundColor Red
Write-Host "  After:  0.75 - 0.95 similarity (strong)" -ForegroundColor Green
