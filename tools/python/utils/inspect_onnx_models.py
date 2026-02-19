#!/usr/bin/env python3
"""Inspect the downloaded Xenova ONNX models."""

import onnxruntime as ort
import numpy as np

# Get model paths from app data
import os
model_dir = os.path.expanduser(r"~\AppData\Local\Temp\kitako_models")

vision_model = os.path.join(model_dir, "vision_model_quantized.onnx")
text_model = os.path.join(model_dir, "text_model_quantized.onnx")

print("=== Vision Model ===")
if os.path.exists(vision_model):
    session = ort.InferenceSession(vision_model)
    print(f"Inputs:")
    for inp in session.get_inputs():
        print(f"  - {inp.name}: {inp.type}, shape {inp.shape}")
    print(f"Outputs:")
    for out in session.get_outputs():
        print(f"  - {out.name}: {out.type}, shape {out.shape}")
else:
    print(f"NOT FOUND: {vision_model}")

print("\n=== Text Model ===")
if os.path.exists(text_model):
    session = ort.InferenceSession(text_model)
    print(f"Inputs:")
    for inp in session.get_inputs():
        print(f"  - {inp.name}: {inp.type}, shape {inp.shape}")
    print(f"Outputs:")
    for out in session.get_outputs():
        print(f"  - {out.name}: {out.type}, shape {out.shape}")
else:
    print(f"NOT FOUND: {text_model}")

# Also check if there are non-quantized versions
print("\n=== Checking HuggingFace Cache ===")
hf_cache = os.path.expanduser(r"~\.cache\huggingface\hub")
if os.path.exists(hf_cache):
    # Look for Xenova SigLIP models
    for item in os.listdir(hf_cache):
        if "siglip" in item.lower() or "xenova" in item.lower():
            print(f"Found: {item}")
            model_path = os.path.join(hf_cache, item)
            # Look for ONNX files
            for root, dirs, files in os.walk(model_path):
                for file in files:
                    if file.endswith('.onnx'):
                        onnx_path = os.path.join(root, file)
                        print(f"  ONNX: {file}")
                        try:
                            sess = ort.InferenceSession(onnx_path)
                            print(f"    Outputs: {[o.name for o.outputs in sess.get_outputs()]}")
                        except Exception as e:
                            print(f"    Error loading: {e}")