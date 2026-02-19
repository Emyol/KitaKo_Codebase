#!/usr/bin/env python3
"""Test PyTorch SigLIP model to see what we SHOULD be getting."""

import torch
import numpy as np
from transformers import SiglipModel, SiglipProcessor
from PIL import Image, ImageDraw, ImageFont

model_id = "google/siglip-base-patch16-224"

print("=== Testing PyTorch SigLIP ===\n")
print(f"Loading model: {model_id}")
model = SiglipModel.from_pretrained(model_id)
try:
    processor = SiglipProcessor.from_pretrained(model_id)
except Exception as e:
    print(f"Warning: Could not load processor: {e}")
    print("Using manual preprocessing instead...")
    processor = None
model.eval()
print("[OK] Model loaded\n")

# Inspect model structure
print("=== Model Structure ===")
print(f"Vision model has head: {hasattr(model.vision_model, 'head')}")
if hasattr(model.vision_model, 'head'):
    print(f"Vision head type: {type(model.vision_model.head)}")
    print(f"Vision head: {model.vision_model.head}")

print(f"\nText model has head: {hasattr(model.text_model, 'head')}")
if hasattr(model.text_model, 'head'):
    print(f"Text head type: {type(model.text_model.head)}")
    print(f"Text head: {model.text_model.head}")

print(f"\nModel has logit_scale: {hasattr(model, 'logit_scale')}")
if hasattr(model, 'logit_scale'):
    print(f"logit_scale value: {model.logit_scale.item():.4f}")

print(f"Model has logit_bias: {hasattr(model, 'logit_bias')}")
if hasattr(model, 'logit_bias'):
    print(f"logit_bias value: {model.logit_bias.item():.4f}")

# Create test images
def create_colored_image(color_name, rgb):
    """Create a 224x224 image filled with the specified color."""
    img = Image.new('RGB', (224, 224), color=rgb)
    draw = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype("arial.ttf", 40)
    except:
        font = ImageFont.load_default()

    bbox = draw.textbbox((0, 0), color_name, font=font)
    text_width = bbox[2] - bbox[0]
    text_height = bbox[3] - bbox[1]
    x = (224 - text_width) // 2
    y = (224 - text_height) // 2

    text_color = (255, 255, 255) if sum(rgb) < 384 else (0, 0, 0)
    draw.text((x, y), color_name, fill=text_color, font=font)

    return img

print("\n=== Test Cases ===\n")

test_cases = [
    ("red", (255, 0, 0)),
    ("blue", (0, 0, 255)),
    ("green", (0, 255, 0)),
]

# Process images manually
def preprocess_pil_image(img):
    """Preprocess PIL image to tensor."""
    # Convert to numpy array
    img_array = np.array(img).astype(np.float32)
    # Normalize: (pixel / 255.0 - 0.5) / 0.5
    img_array = img_array / 127.5 - 1.0
    # Transpose from HWC to CHW
    img_array = img_array.transpose(2, 0, 1)
    return torch.from_numpy(img_array)

# Create manual inputs
pixel_values_list = []
for color_name, rgb in test_cases:
    img = create_colored_image(color_name, rgb)
    pixel_values_list.append(preprocess_pil_image(img))
    print(f"Created: {color_name} image")

pixel_values = torch.stack(pixel_values_list)

# Simple tokenization for testing (will use model's built-in methods)
texts = [name for name, _ in test_cases]

print(f"\npixel_values shape: {pixel_values.shape}")

# Run model using get_image_features and get_text_features
with torch.no_grad():
    # For vision: just pass pixel values
    image_outputs = model.vision_model(pixel_values=pixel_values)

    # For text: we need proper tokenization, so we'll use a simple approach
    # Create basic token IDs (this is a hack for testing - in production use proper tokenizer)
    input_ids = torch.tensor([[2, 3, 3, 3, 1] + [0] * 59] * len(texts))  # BOS, UNK, UNK, UNK, EOS, PAD...
    text_outputs = model.text_model(input_ids=input_ids)

# Extract pooler outputs
image_embeds = image_outputs.pooler_output
text_embeds = text_outputs.pooler_output

print(f"\nImage embeddings shape: {image_embeds.shape}")
print(f"Text embeddings shape: {text_embeds.shape}")

# Check if normalized
image_norms = torch.norm(image_embeds, dim=-1)
text_norms = torch.norm(text_embeds, dim=-1)

print(f"\nImage embedding norms: {image_norms.tolist()}")
print(f"Text embedding norms: {text_norms.tolist()}")

if torch.allclose(image_norms, torch.ones_like(image_norms), atol=1e-3):
    print("Image embeddings are L2-normalized")
else:
    print("Image embeddings are NOT normalized - need to normalize!")

if torch.allclose(text_norms, torch.ones_like(text_norms), atol=1e-3):
    print("Text embeddings are L2-normalized")
else:
    print("Text embeddings are NOT normalized - need to normalize!")

# Compute similarity matrix
print("\n=== Similarity Matrix (PyTorch) ===\n")
print("         ", end="")
for text_name in texts:
    print(f"{text_name:>8}", end="")
print()

for i, img_name in enumerate(texts):
    print(f"{img_name:>8} ", end="")
    for j, text_name in enumerate(texts):
        sim = torch.dot(image_embeds[i], text_embeds[j]).item()
        if i == j:
            print(f"*{sim:>7.4f}", end="")
        else:
            print(f" {sim:>7.4f}", end="")
    print()

print("\n=== Analysis ===")
all_sims = []
diagonal_sims = []
for i in range(len(test_cases)):
    for j in range(len(test_cases)):
        sim = torch.dot(image_embeds[i], text_embeds[j]).item()
        all_sims.append(sim)
        if i == j:
            diagonal_sims.append(sim)

avg_sim = np.mean(all_sims)
avg_diagonal = np.mean(diagonal_sims)

print(f"Average all similarities: {avg_sim:.4f}")
print(f"Average diagonal (matches): {avg_diagonal:.4f}")
print(f"Difference: {avg_diagonal - avg_sim:.4f}")

if avg_diagonal > avg_sim + 0.05:
    print("[OK] PyTorch model produces aligned embeddings!")
else:
    print("[WARNING] Even PyTorch model shows weak alignment!")

# Test with scaled logits
if hasattr(model, 'logit_scale') and hasattr(model, 'logit_bias'):
    logit_scale = model.logit_scale.exp().item()
    logit_bias = model.logit_bias.item()

    print(f"\n=== With Logit Scale/Bias ===")
    print(f"logit_scale (exp): {logit_scale:.4f}")
    print(f"logit_bias: {logit_bias:.4f}\n")

    print("         ", end="")
    for text_name in texts:
        print(f"{text_name:>8}", end="")
    print()

    for i, img_name in enumerate(texts):
        print(f"{img_name:>8} ", end="")
        for j, text_name in enumerate(texts):
            raw_sim = torch.dot(image_embeds[i], text_embeds[j]).item()
            scaled_sim = raw_sim * logit_scale + logit_bias
            if i == j:
                print(f"*{scaled_sim:>7.4f}", end="")
            else:
                print(f" {scaled_sim:>7.4f}", end="")
        print()