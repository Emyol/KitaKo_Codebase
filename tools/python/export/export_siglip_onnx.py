#!/usr/bin/env python3
"""
Export SigLIP model from HuggingFace directly to ONNX format.

This bypasses the TFLite models and creates fresh ONNX exports from the 
original HuggingFace model, which will be compatible with ONNX Runtime.

Requirements:
    pip install transformers torch onnx onnxruntime optimum

Usage:
    python export_siglip_onnx.py
"""

import os
import sys

# Check dependencies first
def check_dependencies():
    """Check if required packages are installed."""
    missing = []
    try:
        import torch
    except ImportError:
        missing.append('torch')
    try:
        import transformers
    except ImportError:
        missing.append('transformers')
    try:
        import onnx
    except ImportError:
        missing.append('onnx')
    try:
        import onnxruntime
    except ImportError:
        missing.append('onnxruntime')
    
    if missing:
        print("Missing dependencies. Install with:")
        print(f"  pip install {' '.join(missing)}")
        return False
    return True


def export_with_optimum():
    """Export SigLIP using Optimum library (recommended method)."""
    from optimum.exporters.onnx import main_export
    from optimum.onnxruntime import ORTModelForImageClassification
    
    SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
    PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
    OUTPUT_DIR = os.path.join(PROJECT_ROOT, "assets", "models", "onnx")
    
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    
    # SigLIP model identifier
    model_id = "google/siglip-base-patch16-224"
    
    print(f"Exporting {model_id} to ONNX...")
    print(f"Output directory: {OUTPUT_DIR}")
    
    # Export the model
    main_export(
        model_name_or_path=model_id,
        output=OUTPUT_DIR,
        task="image-classification",  # Will export vision encoder
        device="cpu",
    )
    
    print(f"✓ Model exported to {OUTPUT_DIR}")


def export_manual():
    """Manual export of SigLIP components."""
    import torch
    from transformers import SiglipModel, AutoTokenizer
    import onnx
    import onnxruntime as ort
    
    SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
    PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
    MODELS_DIR = os.path.join(PROJECT_ROOT, "assets", "models")
    ONNX_DIR = os.path.join(MODELS_DIR, "onnx")
    
    os.makedirs(ONNX_DIR, exist_ok=True)
    
    # Load the model
    model_id = "google/siglip-base-patch16-224"
    print(f"Loading {model_id}...")
    
    model = SiglipModel.from_pretrained(model_id)
    model.eval()
    
    # Export vision encoder
    print("\nExporting vision encoder...")
    vision_model = model.vision_model
    
    # Dummy input for vision encoder: [batch, channels, height, width]
    dummy_pixel_values = torch.randn(1, 3, 224, 224)
    
    vision_onnx_path = os.path.join(ONNX_DIR, "siglip_vision_encoder.onnx")
    
    torch.onnx.export(
        vision_model,
        (dummy_pixel_values,),
        vision_onnx_path,
        input_names=["pixel_values"],
        output_names=["last_hidden_state", "pooler_output"],
        dynamic_axes={
            "pixel_values": {0: "batch_size"},
            "last_hidden_state": {0: "batch_size"},
            "pooler_output": {0: "batch_size"},
        },
        opset_version=14,
        do_constant_folding=True,
    )
    
    # Verify vision encoder
    print(f"  Verifying {vision_onnx_path}...")
    onnx_model = onnx.load(vision_onnx_path)
    onnx.checker.check_model(onnx_model)
    
    session = ort.InferenceSession(vision_onnx_path)
    print(f"  ✓ Vision encoder exported successfully!")
    print(f"    Size: {os.path.getsize(vision_onnx_path) / (1024*1024):.2f} MB")
    
    # Export text encoder
    print("\nExporting text encoder...")
    text_model = model.text_model
    
    # Dummy input for text encoder: [batch, seq_length]
    dummy_input_ids = torch.randint(0, 32000, (1, 64))
    
    text_onnx_path = os.path.join(ONNX_DIR, "siglip_text_encoder.onnx")
    
    torch.onnx.export(
        text_model,
        (dummy_input_ids,),
        text_onnx_path,
        input_names=["input_ids"],
        output_names=["last_hidden_state", "pooler_output"],
        dynamic_axes={
            "input_ids": {0: "batch_size", 1: "sequence_length"},
            "last_hidden_state": {0: "batch_size", 1: "sequence_length"},
            "pooler_output": {0: "batch_size"},
        },
        opset_version=14,
        do_constant_folding=True,
    )
    
    # Verify text encoder  
    print(f"  Verifying {text_onnx_path}...")
    onnx_model = onnx.load(text_onnx_path)
    onnx.checker.check_model(onnx_model)
    
    session = ort.InferenceSession(text_onnx_path)
    print(f"  ✓ Text encoder exported successfully!")
    print(f"    Size: {os.path.getsize(text_onnx_path) / (1024*1024):.2f} MB")
    
    # Save tokenizer separately using AutoTokenizer
    print("\nSaving tokenizer...")
    tokenizer_path = os.path.join(ONNX_DIR, "tokenizer")
    try:
        tokenizer = AutoTokenizer.from_pretrained(model_id)
        tokenizer.save_pretrained(tokenizer_path)
        print(f"  ✓ Tokenizer saved to {tokenizer_path}")
    except Exception as e:
        print(f"  ⚠ Could not save tokenizer: {e}")
        print("  (You can use the existing tokenizer from assets/tokenizer)")
    
    return True


def main():
    print("=" * 60)
    print("SigLIP ONNX Export Tool")
    print("=" * 60)
    
    if not check_dependencies():
        print("\nInstall missing dependencies and try again.")
        print("\nFull command:")
        print("  pip install torch transformers onnx onnxruntime optimum[exporters]")
        sys.exit(1)
    
    try:
        success = export_manual()
        if success:
            print("\n" + "=" * 60)
            print("✓ Export complete!")
            print("=" * 60)
            print("\nNext steps:")
            print("1. Update Flutter pubspec.yaml to include ONNX models")
            print("2. Update embedding service to use ONNX Runtime")
    except Exception as e:
        print(f"\n✗ Export failed: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
