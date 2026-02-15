#!/usr/bin/env python3
"""
Test SigLIP model to verify vision and text embeddings are properly aligned.

This script checks if the pooler_output from vision and text models are
in the same embedding space by computing similarity scores.
"""

import os
import torch
import numpy as np
from transformers import SiglipModel, SiglipProcessor
from PIL import Image

def test_alignment():
    """Test if SigLIP embeddings are properly aligned."""

    # Load model
    model_id = "google/siglip-base-patch16-224"
    print(f"Loading {model_id}...")

    model = SiglipModel.from_pretrained(model_id)
    processor = SiglipProcessor.from_pretrained(model_id)
    model.eval()

    # Print model architecture
    print("\n=== Model Architecture ===")
    print(f"Model type: {type(model)}")
    print(f"Vision model hidden size: {model.config.vision_config.hidden_size}")
    print(f"Text model hidden size: {model.config.text_config.hidden_size}")

    # Check for projection layers
    print(f"\nHas visual_projection: {hasattr(model, 'visual_projection')}")
    print(f"Has text_projection: {hasattr(model, 'text_projection')}")

    if hasattr(model, 'logit_scale'):
        print(f"Logit scale: {model.logit_scale.item():.4f}")

    # Create test image (red square)
    image = Image.new('RGB', (224, 224), color='red')

    # Test queries - some match, some don't
    test_queries = [
        "a red image",      # Should match
        "a red square",     # Should match
        "red color",        # Should match
        "a blue image",     # Should NOT match
        "a dog",            # Should NOT match
        "a cat",            # Should NOT match
    ]

    print("\n=== Testing Embedding Alignment ===")
    print("Using red image vs various text queries\n")

    # Get image embedding
    with torch.no_grad():
        # Process image
        image_inputs = processor(images=image, return_tensors="pt")

        # Get vision outputs
        vision_outputs = model.vision_model(**image_inputs)
        image_embeds = vision_outputs.pooler_output  # [1, 768]

        # Normalize
        image_embeds = image_embeds / image_embeds.norm(dim=-1, keepdim=True)

        print(f"Image embedding shape: {image_embeds.shape}")
        print(f"Image embedding norm: {image_embeds.norm().item():.4f}")

        print("\nSimilarity scores (higher = more similar):")
        print("-" * 50)

        for query in test_queries:
            # Process text
            text_inputs = processor(text=[query], return_tensors="pt", padding="max_length", max_length=64)

            # Get text outputs
            text_outputs = model.text_model(**text_inputs)
            text_embeds = text_outputs.pooler_output  # [1, 768]

            # Normalize
            text_embeds = text_embeds / text_embeds.norm(dim=-1, keepdim=True)

            # Compute cosine similarity
            similarity = (image_embeds * text_embeds).sum().item()

            # Expected: red-related queries should have positive similarity
            # Non-red queries should have lower/negative similarity
            status = "✓" if (query.startswith("red") or "red" in query) and similarity > 0.1 else "✗"
            print(f"  {status} '{query:20s}': {similarity:+.4f}")

    print("\n" + "=" * 50)
    print("DIAGNOSIS:")
    print("=" * 50)

    print("""
If red-related queries show POSITIVE similarity (> 0.1):
  ✓ Model is working correctly
  ✓ Embeddings are in the same space
  ✓ No projection layers needed

If ALL queries show NEGATIVE or near-zero similarity:
  ✗ Embeddings are NOT aligned
  ✗ May need different model or post-processing

If results are random/inconsistent:
  ⚠ Model may not be properly loaded or configured
    """)

if __name__ == "__main__":
    test_alignment()
