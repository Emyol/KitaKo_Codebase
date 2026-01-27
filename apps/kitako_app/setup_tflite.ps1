# KitaKo TFLite Setup Script for Windows
# Downloads the TensorFlow Lite C library required for embedding generation

$ErrorActionPreference = "Stop"

$blobsDir = Join-Path $PSScriptRoot "blobs"
$dllPath = Join-Path $blobsDir "libtensorflowlite_c-win.dll"

# Create blobs directory
if (-not (Test-Path $blobsDir)) {
    New-Item -ItemType Directory -Path $blobsDir | Out-Null
    Write-Host "Created blobs directory"
}

# Check if DLL already exists
if (Test-Path $dllPath) {
    Write-Host "TFLite DLL already exists at: $dllPath"
    Write-Host "Delete it manually if you want to re-download."
    exit 0
}

Write-Host "Downloading TensorFlow Lite C library for Windows..."
Write-Host ""

# TFLite release URLs to try (in order of preference)
$urls = @(
    "https://github.com/peterfritz/tflite-flutter-plugin-prebuilt/releases/download/0.11.0/windows-x64-libtensorflowlite_c.dll",
    "https://github.com/peterfritz/tflite-flutter-plugin-prebuilt/releases/download/v0.10.0/libtensorflowlite_c-win.dll",
    "https://github.com/nicholasshulman/tflite-dist/releases/download/2.16.1/libtensorflowlite_c-win.dll"
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$downloaded = $false
foreach ($url in $urls) {
    Write-Host "Trying: $url"
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
        $wc.DownloadFile($url, $dllPath)
        Write-Host "Download successful!"
        $downloaded = $true
        break
    } catch {
        Write-Host "Failed: $($_.Exception.Message)"
    }
}

if (-not $downloaded) {
    Write-Host ""
    Write-Host "=========================================="
    Write-Host "AUTOMATIC DOWNLOAD FAILED"
    Write-Host "=========================================="
    Write-Host ""
    Write-Host "Please download the TFLite DLL manually:"
    Write-Host ""
    Write-Host "Option 1: Pre-built from GitHub"
    Write-Host "  1. Go to: https://github.com/peterfritz/tflite-flutter-plugin-prebuilt/releases"
    Write-Host "  2. Download the Windows DLL (x64)"
    Write-Host "  3. Rename to: libtensorflowlite_c-win.dll"
    Write-Host "  4. Place in: $blobsDir"
    Write-Host ""
    Write-Host "Option 2: Build from TensorFlow source"
    Write-Host "  1. Clone: https://github.com/tensorflow/tensorflow"
    Write-Host "  2. Build: bazel build -c opt //tensorflow/lite/c:tensorflowlite_c"
    Write-Host "  3. Copy bazel-bin/tensorflow/lite/c/tensorflowlite_c.dll"
    Write-Host "  4. Rename to: libtensorflowlite_c-win.dll"
    Write-Host "  5. Place in: $blobsDir"
    Write-Host ""
    Write-Host "The app will run in MOCK mode until the DLL is provided."
    exit 1
}

# Verify the file
$fileInfo = Get-Item $dllPath
Write-Host ""
Write-Host "=========================================="
Write-Host "SUCCESS!"
Write-Host "=========================================="
Write-Host "Downloaded: $($fileInfo.Name)"
Write-Host "Size: $([math]::Round($fileInfo.Length / 1MB, 2)) MB"
Write-Host "Location: $dllPath"
Write-Host ""
Write-Host "Now run: flutter clean && flutter run -d windows"
