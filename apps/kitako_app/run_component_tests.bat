@echo off
REM Embedding Component Test Runner
REM Run this from apps\kitako_app directory

echo ========================================
echo KitaKo Embedding Component Tests
echo ========================================
echo.

cd /d "%~dp0"

echo [1/4] Running Tokenizer Tests...
echo ----------------------------------------
call flutter test test/component_tests/tokenizer_test.dart --reporter expanded
if %ERRORLEVEL% NEQ 0 (
    echo ❌ Tokenizer tests FAILED
) else (
    echo ✅ Tokenizer tests PASSED
)
echo.

echo [2/4] Running Image Preprocessor Tests...
echo ----------------------------------------
call flutter test test/component_tests/image_preprocessor_test.dart --reporter expanded
if %ERRORLEVEL% NEQ 0 (
    echo ❌ Image Preprocessor tests FAILED
) else (
    echo ✅ Image Preprocessor tests PASSED
)
echo.

echo [3/4] Running ONNX Inference Tests...
echo ----------------------------------------
call flutter test test/component_tests/onnx_inference_test.dart --reporter expanded
if %ERRORLEVEL% NEQ 0 (
    echo ❌ ONNX Inference tests FAILED
) else (
    echo ✅ ONNX Inference tests PASSED
)
echo.

echo [4/4] Running Embedding Service Tests...
echo ----------------------------------------
call flutter test test/component_tests/embedding_service_test.dart --reporter expanded
if %ERRORLEVEL% NEQ 0 (
    echo ❌ Embedding Service tests FAILED
) else (
    echo ✅ Embedding Service tests PASSED
)
echo.

echo ========================================
echo All component tests completed!
echo ========================================
pause
