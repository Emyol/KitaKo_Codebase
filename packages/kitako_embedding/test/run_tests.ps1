# Run all SigLIP model tests
cd "c:\Users\Jhezra\Documents\KitaKo_System\packages\kitako_embedding"

Write-Host "=== Running SigLIP Model Tests ===" -ForegroundColor Cyan
Write-Host ""

# Run the comprehensive model tests
Write-Host "Running comprehensive model validation..." -ForegroundColor Yellow
flutter test test/siglip_model_test.dart --reporter expanded

Write-Host ""
Write-Host "=== Test Summary ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Tests cover:" -ForegroundColor White
Write-Host "  ✓ Model file validation (sizes, existence)" -ForegroundColor Gray
Write-Host "  ✓ Model initialization (SigLIP-1 & SigLIP-2)" -ForegroundColor Gray
Write-Host "  ✓ Image embedding generation (768D, normalized)" -ForegroundColor Gray
Write-Host "  ✓ Text embedding generation (768D, normalized)" -ForegroundColor Gray
Write-Host "  ✓ SigLIP-1 vs SigLIP-2 comparison (projection layers)" -ForegroundColor Gray
Write-Host "  ✓ Performance benchmarks (speed)" -ForegroundColor Gray
Write-Host "  ✓ Edge cases (empty text, long text, special chars)" -ForegroundColor Gray
Write-Host ""
