#!/usr/bin/env python3
"""Inspect SigLIP model structure to find projection layers."""

import torch
from transformers import SiglipModel

model_id = "google/siglip-base-patch16-224"
print(f"Loading model: {model_id}")

model = SiglipModel.from_pretrained(model_id)
print("\n=== Model Structure ===")
print(f"Model type: {type(model)}")
print(f"\nModel attributes:")
for attr in dir(model):
    if not attr.startswith('_'):
        try:
            obj = getattr(model, attr)
            if isinstance(obj, torch.nn.Module):
                print(f"  - {attr}: {type(obj).__name__}")
        except:
            pass

print("\n=== Vision Model ===")
print(f"Vision model type: {type(model.vision_model)}")
print(f"Vision model attributes:")
for attr in dir(model.vision_model):
    if not attr.startswith('_'):
        try:
            obj = getattr(model.vision_model, attr)
            if isinstance(obj, torch.nn.Module):
                print(f"  - {attr}: {type(obj).__name__}")
        except:
            pass

print("\n=== Text Model ===")
print(f"Text model type: {type(model.text_model)}")
print(f"Text model attributes:")
for attr in dir(model.text_model):
    if not attr.startswith('_'):
        try:
            obj = getattr(model.text_model, attr)
            if isinstance(obj, torch.nn.Module):
                print(f"  - {attr}: {type(obj).__name__}")
        except:
            pass

print("\n=== Config ===")
print(f"Vision config: {model.config.vision_config}")
print(f"\nText config: {model.config.text_config}")

print("\n=== Testing Forward Pass ===")
# Test to see what outputs we get
from transformers import SiglipProcessor
from PIL import Image
import requests

processor = SiglipProcessor.from_pretrained(model_id)

# Load a sample image
url = "http://images.cocodataset.org/val2017/000000039769.jpg"
image = Image.open(requests.get(url, stream=True).raw)
text = "a photo of 2 cats"

inputs = processor(text=[text], images=image, return_tensors="pt", padding=True)

print(f"\nInput keys: {inputs.keys()}")

with torch.no_grad():
    outputs = model(**inputs)

print(f"\nOutput keys: {outputs.keys()}")
print(f"Output types:")
for key, value in outputs.items():
    if hasattr(value, 'shape'):
        print(f"  - {key}: shape {value.shape}")
    else:
        print(f"  - {key}: {type(value)}")