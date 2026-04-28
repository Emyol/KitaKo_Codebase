#!/usr/bin/env python3
"""
Convert TFLite models to ONNX format.

Requirements (install with pip):
    pip install tf2onnx tensorflow onnx onnxruntime

Usage:
    python convert_tflite_to_onnx.py
"""

import os
import subprocess
import sys

# Paths relative to this script
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
MODELS_DIR = os.path.join(PROJECT_ROOT, "assets", "models")

# Input TFLite models
IMAGE_ENCODER_TFLITE = os.path.join(MODELS_DIR, "image_encoder", "kitako_image_encoder_int8.tflite")
TEXT_ENCODER_TFLITE = os.path.join(MODELS_DIR, "text_encoder", "kitako_text_encoder_dynamic.tflite")

# Output ONNX models
IMAGE_ENCODER_ONNX = os.path.join(MODELS_DIR, "image_encoder", "kitako_image_encoder.onnx")
TEXT_ENCODER_ONNX = os.path.join(MODELS_DIR, "text_encoder", "kitako_text_encoder.onnx")


def check_dependencies():
    """Check if required packages are installed."""
    try:
        import tf2onnx
        import onnx
        import onnxruntime
        print("✓ All dependencies are installed")
        return True
    except ImportError as e:
        print(f"✗ Missing dependency: {e}")
        print("\nInstall dependencies with:")
        print("  pip install tf2onnx tensorflow onnx onnxruntime")
        return False


def convert_tflite_to_onnx(tflite_path: str, onnx_path: str, opset: int = 13):
    """
    Convert a TFLite model to ONNX format using tf2onnx.
    
    Args:
        tflite_path: Path to input .tflite file
        onnx_path: Path to output .onnx file
        opset: ONNX opset version (default 13)
    """
    if not os.path.exists(tflite_path):
        print(f"✗ TFLite model not found: {tflite_path}")
        return False
    
    print(f"\nConverting: {os.path.basename(tflite_path)}")
    print(f"  Input:  {tflite_path}")
    print(f"  Output: {onnx_path}")
    
    # Use tf2onnx command line tool
    cmd = [
        sys.executable, "-m", "tf2onnx.convert",
        "--tflite", tflite_path,
        "--output", onnx_path,
        "--opset", str(opset)
    ]
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode == 0:
            print(f"✓ Converted successfully!")
            
            # Verify the output
            if os.path.exists(onnx_path):
                size_mb = os.path.getsize(onnx_path) / (1024 * 1024)
                print(f"  Output size: {size_mb:.2f} MB")
                return True
            else:
                print(f"✗ Output file not created")
                return False
        else:
            print(f"✗ Conversion failed:")
            print(result.stderr)
            return False
    except Exception as e:
        print(f"✗ Error during conversion: {e}")
        return False


def verify_onnx_model(onnx_path: str):
    """Verify an ONNX model can be loaded and run."""
    try:
        import onnx
        import onnxruntime as ort
        
        # Check model structure
        model = onnx.load(onnx_path)
        onnx.checker.check_model(model)
        print(f"  ✓ Model structure valid")
        
        # Check it can be loaded by ONNX Runtime
        session = ort.InferenceSession(onnx_path)
        
        # Print input/output info
        print(f"  Inputs:")
        for inp in session.get_inputs():
            print(f"    - {inp.name}: {inp.shape} ({inp.type})")
        print(f"  Outputs:")
        for out in session.get_outputs():
            print(f"    - {out.name}: {out.shape} ({out.type})")
        
        return True
    except Exception as e:
        print(f"  ✗ Verification failed: {e}")
        return False


def main():
    print("=" * 60)
    print("TFLite to ONNX Converter for KitaKo")
    print("=" * 60)
    
    if not check_dependencies():
        sys.exit(1)
    
    success_count = 0
    total_count = 0
    
    # Convert image encoder
    if os.path.exists(IMAGE_ENCODER_TFLITE):
        total_count += 1
        if convert_tflite_to_onnx(IMAGE_ENCODER_TFLITE, IMAGE_ENCODER_ONNX):
            if verify_onnx_model(IMAGE_ENCODER_ONNX):
                success_count += 1
    else:
        print(f"\n⚠ Image encoder TFLite not found: {IMAGE_ENCODER_TFLITE}")
    
    # Convert text encoder
    if os.path.exists(TEXT_ENCODER_TFLITE):
        total_count += 1
        if convert_tflite_to_onnx(TEXT_ENCODER_TFLITE, TEXT_ENCODER_ONNX):
            if verify_onnx_model(TEXT_ENCODER_ONNX):
                success_count += 1
    else:
        print(f"\n⚠ Text encoder TFLite not found: {TEXT_ENCODER_TFLITE}")
    
    print("\n" + "=" * 60)
    print(f"Conversion complete: {success_count}/{total_count} models converted")
    print("=" * 60)
    
    if success_count == total_count and total_count > 0:
        print("\n✓ All models converted successfully!")
        print("\nNext steps:")
        print("1. Copy ONNX models to Flutter assets")
        print("2. Update pubspec.yaml to include ONNX models")
        print("3. Update embedding service to use ONNX Runtime")
    else:
        print("\n✗ Some conversions failed. Check the errors above.")


if __name__ == "__main__":
    main()
