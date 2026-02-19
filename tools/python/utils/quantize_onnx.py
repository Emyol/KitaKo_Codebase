#!/usr/bin/env python3
"""
Quantize ONNX models to reduce size for mobile deployment.
"""

import os
import onnx
from onnxruntime.quantization import quantize_dynamic, QuantType

MODELS_DIR = r"C:\Users\Jhezra\Documents\KitaKo_System\assets\models\onnx"

def quantize_model(input_path, output_path, name):
    """Quantize an ONNX model using dynamic quantization."""
    print(f"\nQuantizing {name}...")
    print(f"  Input: {input_path}")
    print(f"  Input size: {os.path.getsize(input_path) / (1024*1024):.2f} MB")
    
    try:
        quantize_dynamic(
            model_input=input_path,
            model_output=output_path,
            weight_type=QuantType.QUInt8
        )
        
        print(f"  Output: {output_path}")
        print(f"  Output size: {os.path.getsize(output_path) / (1024*1024):.2f} MB")
        
        reduction = (1 - os.path.getsize(output_path) / os.path.getsize(input_path)) * 100
        print(f"  Size reduction: {reduction:.1f}%")
        return True
    except Exception as e:
        print(f"  ✗ Failed: {e}")
        return False

def main():
    print("="*60)
    print("ONNX Model Quantization")
    print("="*60)
    
    # Quantize vision encoder
    quantize_model(
        os.path.join(MODELS_DIR, "siglip_vision_encoder_full.onnx"),
        os.path.join(MODELS_DIR, "siglip_vision_encoder_quant.onnx"),
        "Vision Encoder"
    )
    
    # Quantize text encoder
    quantize_model(
        os.path.join(MODELS_DIR, "siglip_text_encoder_full.onnx"),
        os.path.join(MODELS_DIR, "siglip_text_encoder_quant.onnx"),
        "Text Encoder"
    )
    
    print("\n" + "="*60)
    print("Summary")
    print("="*60)
    
    for f in os.listdir(MODELS_DIR):
        if f.endswith('.onnx'):
            path = os.path.join(MODELS_DIR, f)
            size = os.path.getsize(path) / (1024*1024)
            print(f"  {f}: {size:.2f} MB")

if __name__ == "__main__":
    main()
