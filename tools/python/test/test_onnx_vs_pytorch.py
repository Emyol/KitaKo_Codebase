#!/usr/bin/env python3
"""Compare ONNX model outputs vs PyTorch model to verify projections."""

import torch
import onnxruntime as ort
import numpy as np
from transformers import SiglipModel, SiglipProcessor
from PIL import Image

model_id = "google/siglip-base-patch16-224"
print(f"Loading PyTorch model: {model_id}\n")

# Load PyTorch model
model = SiglipModel.from_pretrained(model_id)
model.eval()

# Test text embedding
text = "cat"
print(f"=== Testing Text: '{text}' ===\n")

# Simple tokenization (we'll just use a simple token sequence)
# SigLIP uses tokens: [0=pad, 1=eos, 2=bos, 3=unk]
# For now, let's create a simple token sequence
token_ids = [3, 3, 3]  # Use unk tokens as placeholder
input_ids = torch.tensor([token_ids + [1] + [0] * (64 - len(token_ids) - 1)])  # Add EOS and pad to 64

print(f"Input IDs shape: {input_ids.shape}")
print(f"Input IDs: {input_ids[0, :10].tolist()}...")

# Run PyTorch text model
with torch.no_grad():
    text_outputs = model.get_text_features(input_ids=input_ids)

print(f"\n=== PyTorch Text Model Output ===")
print(f"Shape: {text_outputs.shape}")
print(f"First 10 values: {text_outputs[0, :10].tolist()}")
print(f"Norm: {torch.norm(text_outputs).item():.4f}")

# Check if vision model has encoder output
print(f"\n=== Vision Model Structure ===")
print(f"Vision head type: {type(model.vision_model.head)}")
print(f"Vision head: {model.vision_model.head}")

# Test with dummy image
dummy_image = torch.randn(1, 3, 224, 224)
with torch.no_grad():
    vision_outputs = model.get_image_features(pixel_values=dummy_image)

print(f"\n=== PyTorch Vision Model Output ===")
print(f"Shape: {vision_outputs.shape}")
print(f"First 10 values: {vision_outputs[0, :10].tolist()}")
print(f"Norm: {torch.norm(vision_outputs).item():.4f}")

# Check what the encoder outputs (before head)
with torch.no_grad():
    encoder_output = model.vision_model.encoder(
        model.vision_model.embeddings(dummy_image)
    )
    pooled = model.vision_model.post_layernorm(encoder_output[0])

print(f"\n=== Vision Encoder Output (before head) ===")
print(f"Encoder output shape: {encoder_output[0].shape}")
print(f"After post_layernorm shape: {pooled.shape}")

# Apply head
with torch.no_grad():
    head_output = model.vision_model.head(pooled)

print(f"\n=== Vision After Head ===")
print(f"Head output shape: {head_output.shape}")
print(f"Head output first 10: {head_output[0, :10].tolist()}")
print(f"Matches get_image_features: {torch.allclose(head_output, vision_outputs, atol=1e-4)}")

print("\n=== Conclusion ===")
print(f"If get_image_features matches head output, then pooler_output in ONNX should be correct.")
print(f"If they don't match, the ONNX export might be missing the head layer.")