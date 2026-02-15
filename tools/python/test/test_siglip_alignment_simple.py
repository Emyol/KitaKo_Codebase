#!/usr/bin/env python3
"""Quick test of SigLIP alignment using get_image_features and get_text_features."""

import os
os.environ['HF_HUB_DISABLE_PROGRESS_BARS'] = '1'

import warnings
warnings.filterwarnings('ignore')

import logging
logging.disable(logging.WARNING)

from transformers import SiglipModel, SiglipImageProcessor, SiglipTokenizer
import torch
from PIL import Image

print("Loading SigLIP model...")
model = SiglipModel.from_pretrained('google/siglip-base-patch16-224')
image_processor = SiglipImageProcessor.from_pretrained('google/siglip-base-patch16-224')
tokenizer = SiglipTokenizer.from_pretrained('google/siglip-base-patch16-224')
model.eval()

print("Creating test inputs...")
image = Image.new('RGB', (224, 224), color='red')

image_inputs = image_processor(images=image, return_tensors='pt')
text_inputs = tokenizer(['a red image', 'a cat', 'a blue sky'], padding='max_length', max_length=64, return_tensors='pt')

print("Running inference...")
with torch.no_grad():
    image_out = model.get_image_features(image_inputs['pixel_values'])
    text_out = model.get_text_features(text_inputs['input_ids'])

    # Debug: check output types
    print(f"Image output type: {type(image_out)}")
    print(f"Text output type: {type(text_out)}")

    # Handle both tensor and object outputs
    if hasattr(image_out, 'pooler_output'):
        image_features = image_out.pooler_output
    elif hasattr(image_out, 'last_hidden_state'):
        image_features = image_out.last_hidden_state.mean(dim=1)
    else:
        image_features = image_out

    if hasattr(text_out, 'pooler_output'):
        text_features = text_out.pooler_output
    elif hasattr(text_out, 'last_hidden_state'):
        text_features = text_out.last_hidden_state.mean(dim=1)
    else:
        text_features = text_out

    # L2 normalize
    image_features = image_features / image_features.norm(dim=-1, keepdim=True)
    text_features = text_features / text_features.norm(dim=-1, keepdim=True)

    similarity = (image_features @ text_features.T)

    print(f"\n=== Results ===")
    print(f"Image features shape: {image_features.shape}")
    print(f"Text features shape: {text_features.shape}")
    print(f"\nSimilarities (red image vs queries):")
    print(f'  "a red image": {similarity[0, 0].item():.4f}')
    print(f'  "a cat":       {similarity[0, 1].item():.4f}')
    print(f'  "a blue sky":  {similarity[0, 2].item():.4f}')

    print("\n=== Conclusion ===")
    if similarity[0, 0] > similarity[0, 1] and similarity[0, 0] > similarity[0, 2]:
        print("SUCCESS: get_image_features and get_text_features produce ALIGNED embeddings!")
        print("The model's built-in methods already handle projection internally.")
    else:
        print("UNEXPECTED: Alignment may be incorrect")

print("\nDone!")
