#!/usr/bin/env python3
"""
Export SigLIP model with PROJECTION LAYERS to ONNX format.

The previous export was missing the projection layers, causing vision and text
embeddings to be in different spaces (resulting in negative similarities).

This script exports:
1. Vision encoder + visual_projection → shared embedding space
2. Text encoder + text_projection → shared embedding space

Requirements:
    pip install torch transformers onnx onnxruntime numpy

Usage:
    python export_siglip_with_projection.py
"""

import os
import sys
import torch
import torch.nn as nn
import numpy as np


def check_dependencies():
    """Check if required packages are installed."""
    missing = []
    for pkg in ['torch', 'transformers', 'onnx', 'onnxruntime', 'numpy']:
        try:
            __import__(pkg)
        except ImportError:
            missing.append(pkg)
    
    if missing:
        print("Missing dependencies. Install with:")
        print(f"  pip install {' '.join(missing)}")
        return False
    return True


class SigLIPVisionWithProjection(nn.Module):
    """Vision encoder with projection layer - produces embeddings in shared space."""
    
    def __init__(self, model):
        super().__init__()
        self.vision_model = model.vision_model
        self.visual_projection = model.visual_projection  # <-- KEY: projection layer!
    
    def forward(self, pixel_values):
        # Get vision features
        vision_outputs = self.vision_model(pixel_values=pixel_values)
        
        # SigLIP uses pooler_output (mean of patches)
        # pooler_output shape: [batch, hidden_dim]
        pooled_output = vision_outputs.pooler_output
        
        # Project to shared embedding space
        # visual_projection: [hidden_dim] -> [projection_dim] (768 -> 768 for base model)
        image_embeds = self.visual_projection(pooled_output)
        
        return image_embeds


class SigLIPTextWithProjection(nn.Module):
    """Text encoder with projection layer - produces embeddings in shared space."""
    
    def __init__(self, model):
        super().__init__()
        self.text_model = model.text_model
        self.text_projection = model.text_projection  # <-- KEY: projection layer!
    
    def forward(self, input_ids):
        # Get text features
        text_outputs = self.text_model(input_ids=input_ids)
        
        # SigLIP uses pooler_output (mean of tokens or EOS token)
        pooled_output = text_outputs.pooler_output
        
        # Project to shared embedding space
        text_embeds = self.text_projection(pooled_output)
        
        return text_embeds


def export_models():
    """Export SigLIP components with projection layers."""
    from transformers import SiglipModel, AutoProcessor
    import onnx
    import onnxruntime as ort
    
    SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
    PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
    ONNX_DIR = os.path.join(PROJECT_ROOT, "assets", "models", "onnx")
    
    os.makedirs(ONNX_DIR, exist_ok=True)
    
    # Load the full SigLIP model
    model_id = "google/siglip-base-patch16-224"
    print(f"Loading {model_id}...")
    
    model = SiglipModel.from_pretrained(model_id)
    model.eval()
    
    print(f"\n=== Model Architecture ===")
    print(f"Vision model hidden size: {model.config.vision_config.hidden_size}")
    print(f"Text model hidden size: {model.config.text_config.hidden_size}")
    print(f"Projection dim: {model.config.projection_dim if hasattr(model.config, 'projection_dim') else 'N/A'}")
    print(f"Has visual_projection: {hasattr(model, 'visual_projection')}")
    print(f"Has text_projection: {hasattr(model, 'text_projection')}")
    
    if hasattr(model, 'visual_projection'):
        print(f"visual_projection: {model.visual_projection}")
    if hasattr(model, 'text_projection'):
        print(f"text_projection: {model.text_projection}")
    
    # ============ EXPORT VISION ENCODER WITH PROJECTION ============
    print("\n=== Exporting Vision Encoder WITH Projection ===")
    
    vision_with_proj = SigLIPVisionWithProjection(model)
    vision_with_proj.eval()
    
    # Dummy input: [batch, channels, height, width]
    dummy_pixel_values = torch.randn(1, 3, 224, 224)
    
    vision_onnx_path = os.path.join(ONNX_DIR, "siglip_vision_with_projection.onnx")
    
    with torch.no_grad():
        # Trace the model
        torch.onnx.export(
            vision_with_proj,
            (dummy_pixel_values,),
            vision_onnx_path,
            input_names=["pixel_values"],
            output_names=["image_embeds"],  # This is the projected embedding!
            dynamic_axes={
                "pixel_values": {0: "batch_size"},
                "image_embeds": {0: "batch_size"},
            },
            opset_version=14,
            do_constant_folding=True,
        )
    
    print(f"  Saved to: {vision_onnx_path}")
    print(f"  Size: {os.path.getsize(vision_onnx_path) / (1024*1024):.2f} MB")
    
    # Verify
    print("  Verifying...")
    onnx_model = onnx.load(vision_onnx_path)
    onnx.checker.check_model(onnx_model)
    
    vision_session = ort.InferenceSession(vision_onnx_path)
    vision_result = vision_session.run(None, {"pixel_values": dummy_pixel_values.numpy()})
    print(f"  Output shape: {vision_result[0].shape}")  # Should be [1, 768]
    print(f"  ✓ Vision encoder with projection exported!")
    
    # ============ EXPORT TEXT ENCODER WITH PROJECTION ============
    print("\n=== Exporting Text Encoder WITH Projection ===")
    
    text_with_proj = SigLIPTextWithProjection(model)
    text_with_proj.eval()
    
    # Dummy input: [batch, seq_length]
    dummy_input_ids = torch.randint(0, 32000, (1, 64))
    
    text_onnx_path = os.path.join(ONNX_DIR, "siglip_text_with_projection.onnx")
    
    with torch.no_grad():
        torch.onnx.export(
            text_with_proj,
            (dummy_input_ids,),
            text_onnx_path,
            input_names=["input_ids"],
            output_names=["text_embeds"],  # This is the projected embedding!
            dynamic_axes={
                "input_ids": {0: "batch_size", 1: "sequence_length"},
                "text_embeds": {0: "batch_size"},
            },
            opset_version=14,
            do_constant_folding=True,
        )
    
    print(f"  Saved to: {text_onnx_path}")
    print(f"  Size: {os.path.getsize(text_onnx_path) / (1024*1024):.2f} MB")
    
    # Verify
    print("  Verifying...")
    onnx_model = onnx.load(text_onnx_path)
    onnx.checker.check_model(onnx_model)
    
    text_session = ort.InferenceSession(text_onnx_path)
    text_result = text_session.run(None, {"input_ids": dummy_input_ids.numpy()})
    print(f"  Output shape: {text_result[0].shape}")  # Should be [1, 768]
    print(f"  ✓ Text encoder with projection exported!")
    
    # ============ TEST ALIGNMENT ============
    print("\n=== Testing Embedding Alignment ===")
    
    processor = AutoProcessor.from_pretrained(model_id)
    
    # Test with a real image-text pair
    from PIL import Image
    import urllib.request
    
    # Use a simple test image
    test_images_dir = os.path.join(PROJECT_ROOT, "dataset", "images", "taglish_test_images")
    if os.path.exists(test_images_dir):
        test_images = [f for f in os.listdir(test_images_dir) if f.endswith(('.jpg', '.png', '.jpeg'))]
        if test_images:
            test_image_path = os.path.join(test_images_dir, test_images[0])
            image = Image.open(test_image_path).convert("RGB")
            print(f"  Using test image: {test_images[0]}")
        else:
            # Create a dummy image
            image = Image.new('RGB', (224, 224), color='red')
            print("  Using dummy red image")
    else:
        image = Image.new('RGB', (224, 224), color='red')
        print("  Using dummy red image")
    
    # Process image
    image_inputs = processor(images=image, return_tensors="np")
    pixel_values = image_inputs["pixel_values"].astype(np.float32)
    
    # Process text
    test_queries = ["a photo", "a red image", "a dog", "a cat", "nature"]
    
    print("\n  Similarities (higher = more similar):")
    
    # Get image embedding
    vision_result = vision_session.run(None, {"pixel_values": pixel_values})
    image_embed = vision_result[0][0]
    image_embed = image_embed / np.linalg.norm(image_embed)  # L2 normalize
    
    for query in test_queries:
        text_inputs = processor(text=[query], return_tensors="np", padding="max_length", max_length=64)
        input_ids = text_inputs["input_ids"].astype(np.int64)
        
        text_result = text_session.run(None, {"input_ids": input_ids})
        text_embed = text_result[0][0]
        text_embed = text_embed / np.linalg.norm(text_embed)  # L2 normalize
        
        # Cosine similarity
        similarity = np.dot(image_embed, text_embed)
        print(f"    '{query}': {similarity:.4f}")
    
    print("\n" + "=" * 60)
    print("✓ Export complete!")
    print("=" * 60)
    print("\nThe new models output PROJECTED embeddings that are in the same")
    print("semantic space, so image-text similarity should now be positive")
    print("for semantically related pairs.")
    print(f"\nNew model files:")
    print(f"  - {os.path.basename(vision_onnx_path)}")
    print(f"  - {os.path.basename(text_onnx_path)}")
    print("\nUpdate your Dart code to use these new model files!")
    
    return True


def main():
    print("=" * 60)
    print("SigLIP ONNX Export WITH PROJECTION LAYERS")
    print("=" * 60)
    
    if not check_dependencies():
        sys.exit(1)
    
    try:
        export_models()
    except Exception as e:
        print(f"\n✗ Export failed: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
