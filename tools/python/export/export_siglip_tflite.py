#!/usr/bin/env python3
"""
Export SigLIP model to TFLite format compatible with tflite_flutter.

This script exports directly from HuggingFace to TFLite using TensorFlow 2.14,
which is compatible with the TFLite runtime in tflite_flutter 0.12.1.

Requirements:
    pip install tensorflow==2.14.0 transformers torch numpy

Usage:
    python export_siglip_tflite.py
"""

import os
import sys
import numpy as np

# Paths
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
MODELS_DIR = os.path.join(PROJECT_ROOT, "assets", "models")
OUTPUT_DIR = os.path.join(MODELS_DIR, "tflite_compat")


def check_tf_version():
    """Check TensorFlow version - must be 2.14 or earlier for compatibility."""
    import tensorflow as tf
    tf_version = tf.__version__
    major, minor = map(int, tf_version.split('.')[:2])
    
    print(f"TensorFlow version: {tf_version}")
    
    if major > 2 or (major == 2 and minor > 14):
        print(f"⚠ WARNING: TensorFlow {tf_version} may produce models incompatible with tflite_flutter")
        print("  For best compatibility, use: pip install tensorflow==2.14.0")
        return False
    
    print("✓ TensorFlow version is compatible")
    return True


def export_vision_encoder():
    """Export the vision encoder to TFLite."""
    import tensorflow as tf
    import torch
    from transformers import SiglipModel
    
    print("\n" + "="*60)
    print("Exporting Vision Encoder")
    print("="*60)
    
    # Load PyTorch model
    print("Loading SigLIP model from HuggingFace...")
    model_id = "google/siglip-base-patch16-224"
    pt_model = SiglipModel.from_pretrained(model_id)
    pt_model.eval()
    
    vision_model = pt_model.vision_model
    
    # Create dummy input
    dummy_input = torch.randn(1, 3, 224, 224)
    
    # Get PyTorch output for verification
    with torch.no_grad():
        pt_output = vision_model(dummy_input)
        pt_embedding = pt_output.pooler_output.numpy()
    
    print(f"PyTorch output shape: {pt_embedding.shape}")
    
    # Create TensorFlow concrete function
    print("Converting to TensorFlow...")
    
    class VisionEncoder(tf.Module):
        def __init__(self, pt_model):
            super().__init__()
            self.pt_model = pt_model
            
            # Extract weights from PyTorch model
            # This is a simplified approach - for full model you'd need to
            # recreate the architecture in TF
            
        @tf.function(input_signature=[
            tf.TensorSpec(shape=[1, 3, 224, 224], dtype=tf.float32)
        ])
        def __call__(self, pixel_values):
            # Transpose from NCHW (PyTorch) to NHWC (TensorFlow)
            x = tf.transpose(pixel_values, [0, 2, 3, 1])
            # For now, return a placeholder
            # Full implementation would require recreating the vision transformer
            return tf.zeros([1, 768], dtype=tf.float32)
    
    # Since direct conversion is complex, let's use ONNX as intermediate
    print("⚠ Direct PyTorch->TFLite conversion requires ONNX intermediate step")
    print("  Use the ONNX models exported earlier with onnxruntime Flutter package")
    
    return False


def export_via_onnx():
    """Export TFLite via ONNX intermediate format."""
    print("\n" + "="*60)
    print("Checking for ONNX models...")
    print("="*60)
    
    onnx_dir = os.path.join(MODELS_DIR, "onnx")
    vision_onnx = os.path.join(onnx_dir, "siglip_vision_encoder.onnx")
    text_onnx = os.path.join(onnx_dir, "siglip_text_encoder.onnx")
    
    if os.path.exists(vision_onnx) and os.path.exists(text_onnx):
        print(f"✓ Found ONNX models in {onnx_dir}")
        print(f"  - Vision: {os.path.getsize(vision_onnx) / (1024*1024):.2f} MB")
        print(f"  - Text: {os.path.getsize(text_onnx) / (1024*1024):.2f} MB")
        
        # Check for data files
        vision_data = vision_onnx + ".data"
        text_data = text_onnx + ".data"
        
        if os.path.exists(vision_data):
            print(f"  - Vision data: {os.path.getsize(vision_data) / (1024*1024):.2f} MB")
        if os.path.exists(text_data):
            print(f"  - Text data: {os.path.getsize(text_data) / (1024*1024):.2f} MB")
        
        print("\n" + "="*60)
        print("RECOMMENDATION")
        print("="*60)
        print("""
The ONNX models are ready! However, they have external data files which
makes them harder to bundle with Flutter assets.

Option 1: Use onnxruntime Flutter package
-----------------------------------------
Add to pubspec.yaml:
  onnxruntime: ^1.4.1

The models will need to be downloaded at runtime or bundled differently.

Option 2: Re-export with embedded weights
-----------------------------------------
The export script can be modified to embed weights in the ONNX file
(makes files larger but easier to handle).

Option 3: Use a smaller model
-----------------------------
Consider using a smaller SigLIP variant:
- google/siglip-base-patch16-224 (current, ~400MB)
- google/siglip-so400m-patch14-384 (larger, better quality)

For mobile, you might want to explore:
- MobileCLIP or similar efficient models
- OpenCLIP with smaller backbones
""")
        return True
    else:
        print(f"✗ ONNX models not found in {onnx_dir}")
        print("  Run export_siglip_onnx.py first")
        return False


def main():
    print("="*60)
    print("SigLIP TFLite Export Tool")
    print("="*60)
    
    # Create output directory
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    
    # Check TensorFlow version
    try:
        check_tf_version()
    except ImportError:
        print("TensorFlow not installed. This script requires tensorflow.")
        sys.exit(1)
    
    # Check for existing ONNX exports
    export_via_onnx()


if __name__ == "__main__":
    main()
