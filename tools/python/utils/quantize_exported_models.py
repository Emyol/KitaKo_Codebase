#!/usr/bin/env python3
"""Quantize the exported ONNX models to INT8 for mobile deployment."""

import onnx
from onnxruntime.quantization import quantize_dynamic, QuantType
import os

input_dir = "onnx_models_complete"
output_dir = "onnx_models_quantized"

os.makedirs(output_dir, exist_ok=True)

models = ["vision_model.onnx", "text_model.onnx"]

for model_name in models:
    input_path = os.path.join(input_dir, model_name)
    output_path = os.path.join(output_dir, model_name)

    print(f"\n=== Quantizing {model_name} ===")
    print(f"Input: {input_path}")
    print(f"Output: {output_path}")

    # Get input size
    input_size_mb = os.path.getsize(input_path) / 1024 / 1024
    data_file = input_path + ".data"
    if os.path.exists(data_file):
        input_size_mb += os.path.getsize(data_file) / 1024 / 1024
    print(f"Input size: {input_size_mb:.2f} MB")

    # Quantize
    quantize_dynamic(
        model_input=input_path,
        model_output=output_path,
        weight_type=QuantType.QUInt8,  # Quantize weights to 8-bit
    )

    # Get output size
    output_size_mb = os.path.getsize(output_path) / 1024 / 1024
    data_file = output_path + ".data"
    if os.path.exists(data_file):
        output_size_mb += os.path.getsize(data_file) / 1024 / 1024

    print(f"Output size: {output_size_mb:.2f} MB")
    print(f"Compression: {(1 - output_size_mb / input_size_mb) * 100:.1f}%")
    print(f"[OK] Quantized successfully")

print(f"\n[SUCCESS] All models quantized!")
print(f"\nQuantized models in: {output_dir}/")
print(f"\nNext: Push to Android device")