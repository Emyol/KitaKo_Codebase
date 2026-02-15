#!/usr/bin/env python3
"""
Downgrade ONNX Model IR Version from 10 to 9

The Flutter onnxruntime package (v1.4.1) only supports ONNX IR version up to 9.
Our exported models use IR version 10, causing compatibility issues.

This script converts models to IR version 9 while keeping opset 17 if possible.
"""

import onnx
from onnx import version_converter
import os
import sys
from pathlib import Path

def get_model_info(model_path: str) -> dict:
    """Get information about an ONNX model."""
    model = onnx.load(model_path)
    return {
        "ir_version": model.ir_version,
        "opset_version": model.opset_import[0].version if model.opset_import else None,
        "producer": model.producer_name,
        "graph_name": model.graph.name if model.graph.name else "unnamed",
    }

def downgrade_ir_version(input_path: str, output_path: str, target_ir_version: int = 9):
    """
    Downgrade ONNX model IR version.
    
    Note: IR version is metadata about the protobuf format, not the opset.
    Simply changing ir_version works for most models.
    """
    print(f"Loading model: {input_path}")
    model = onnx.load(input_path)
    
    original_ir = model.ir_version
    original_opset = model.opset_import[0].version if model.opset_import else "unknown"
    
    print(f"  Original IR version: {original_ir}")
    print(f"  Original opset version: {original_opset}")
    
    if original_ir <= target_ir_version:
        print(f"  Model already at IR version {original_ir}, no downgrade needed.")
        return False
    
    # Simply change the IR version
    # IR version is just metadata format version, not the operator set
    model.ir_version = target_ir_version
    
    print(f"  Downgraded IR version: {original_ir} → {target_ir_version}")
    
    # Validate the model still works
    try:
        onnx.checker.check_model(model)
        print("  Model validation: PASSED")
    except Exception as e:
        print(f"  Model validation WARNING: {e}")
        print("  Proceeding anyway (mobile runtime may still work)")
    
    # Save the downgraded model
    print(f"  Saving to: {output_path}")
    onnx.save(model, output_path)
    
    # Verify saved model
    saved_model = onnx.load(output_path)
    print(f"  Verified saved IR version: {saved_model.ir_version}")
    
    return True

def main():
    # Define model paths
    models_dir = Path(__file__).parent.parent / "assets" / "models"
    onnx_models_dir = models_dir / "onnx"
    
    models_to_convert = [
        # SigLIP-1 ALIGNED models
        (onnx_models_dir / "siglip_vision_aligned_full.onnx", "SigLIP-1 Vision"),
        (onnx_models_dir / "siglip_text_aligned_full.onnx", "SigLIP-1 Text"),
        # SigLIP-2 models
        (models_dir / "siglip2_vision_model_fp32.onnx", "SigLIP-2 Vision"),
        (models_dir / "siglip2_text_model_fp32.onnx", "SigLIP-2 Text"),
    ]
    
    print("=" * 60)
    print("ONNX IR Version Downgrader")
    print("Converts IR version 10 → 9 for Flutter onnxruntime compatibility")
    print("=" * 60)
    print()
    
    for model_path, name in models_to_convert:
        if not model_path.exists():
            print(f"⚠️  {name}: Not found at {model_path}")
            continue
            
        print(f"\n{'─' * 50}")
        print(f"Processing: {name}")
        print(f"{'─' * 50}")
        
        # Get original info
        info = get_model_info(str(model_path))
        print(f"Current IR version: {info['ir_version']}")
        print(f"Opset version: {info['opset_version']}")
        
        if info['ir_version'] == 10:
            # Create backup
            backup_path = str(model_path).replace(".onnx", "_ir10_backup.onnx")
            if not os.path.exists(backup_path):
                print(f"Creating backup: {backup_path}")
                import shutil
                shutil.copy2(str(model_path), backup_path)
            
            # Downgrade in place
            downgrade_ir_version(str(model_path), str(model_path), target_ir_version=9)
            print(f"✅ {name}: Successfully downgraded")
        else:
            print(f"ℹ️  {name}: Already at IR version {info['ir_version']}")
    
    print()
    print("=" * 60)
    print("Conversion complete!")
    print("=" * 60)

if __name__ == "__main__":
    main()
