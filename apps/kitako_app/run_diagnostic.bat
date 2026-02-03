@echo off
REM Quick Diagnostic Test - Run this first to identify embedding problems
REM Run from apps\kitako_app directory

echo ========================================
echo KitaKo Embedding Diagnostic Test
echo ========================================
echo.
echo This test checks:
echo  - Model files exist and are valid
echo  - Tokenizer loads and tokenizes correctly
echo  - ONNX models load and produce valid output
echo  - Cross-modal alignment works
echo  - Embeddings are properly normalized
echo.

cd /d "%~dp0"

echo Running diagnostic tests...
echo ----------------------------------------
call flutter test test/diagnostics/embedding_diagnostic_test.dart --reporter expanded

echo.
echo ========================================
echo Diagnostic complete!
echo ========================================
pause
