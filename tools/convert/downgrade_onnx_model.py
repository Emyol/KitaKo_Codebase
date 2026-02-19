"""
Downgrade ONNX model to opset 13 / IR version 8 for compatibility with
onnxruntime Flutter package 1.4.1 (which only supports IR <= 9).

This script uses onnx.version_converter to downgrade the model's opset version.
"""

import onnx
from onnx import version_converter
import sys
import os

def downgrade_model(input_path: str, output_path: str, target_opset: int = 13):
    """Downgrade an ONNX model to a lower opset version."""
    print(f"Loading model from {input_path}")
    model = onnx.load(input_path)
    
    print(f"Current IR version: {model.ir_version}")
    print(f"Current opset versions: {[(op.domain, op.version) for op in model.opset_import]}")
    
    # Try to convert to target opset
    print(f"Converting to opset {target_opset}...")
    try:
        converted = version_converter.convert_version(model, target_opset)
        
        # Force IR version to 8 (compatible with onnxruntime 1.4.x)
        converted.ir_version = 8
        
        print(f"New IR version: {converted.ir_version}")
        print(f"New opset versions: {[(op.domain, op.version) for op in converted.opset_import]}")
        
        print(f"Saving to {output_path}")
        onnx.save(converted, output_path)
        print("Done!")
        
        # Print file sizes
        orig_size = os.path.getsize(input_path)
        new_size = os.path.getsize(output_path)
        print(f"Original size: {orig_size / 1024 / 1024:.1f} MB")
        print(f"New size: {new_size / 1024 / 1024:.1f} MB")
        
    except Exception as e:
        print(f"Version conversion failed: {e}")
        print("Trying manual IR version downgrade...")
        
        # Just set the IR version directly
        model.ir_version = 8
        onnx.save(model, output_path)
        print(f"Saved with IR version 8 (opset unchanged)")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python downgrade_onnx_model.py <input.onnx> <output.onnx> [target_opset]")
        sys.exit(1)
    
    input_path = sys.argv[1]
    output_path = sys.argv[2]
    target_opset = int(sys.argv[3]) if len(sys.argv) > 3 else 13
    
    downgrade_model(input_path, output_path, target_opset)
