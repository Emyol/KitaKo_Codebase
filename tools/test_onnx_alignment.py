#!/usr/bin/env python3
"""Test if the exported ONNX models produce aligned embeddings."""

import onnxruntime as ort
import numpy as np
from PIL import Image, ImageDraw, ImageFont
import os

# Model paths
model_dir = "onnx_models_quantized"
vision_model = os.path.join(model_dir, "vision_model_quantized.onnx")
text_model = os.path.join(model_dir, "text_model_quantized.onnx")

print("=== Testing ONNX Model Alignment ===\n")

# Load models
print("Loading ONNX models...")
vision_session = ort.InferenceSession(vision_model)
text_session = ort.InferenceSession(text_model)
print("[OK] Models loaded\n")

# Create simple test images
def create_colored_image(color_name, rgb):
    """Create a 224x224 image filled with the specified color."""
    img = Image.new('RGB', (224, 224), color=rgb)
    # Add text label
    draw = ImageDraw.Draw(img)
    font_size = 40
    try:
        font = ImageFont.truetype("arial.ttf", font_size)
    except:
        font = ImageFont.load_default()

    # Calculate text position to center it
    bbox = draw.textbbox((0, 0), color_name, font=font)
    text_width = bbox[2] - bbox[0]
    text_height = bbox[3] - bbox[1]
    x = (224 - text_width) // 2
    y = (224 - text_height) // 2

    # Choose contrasting text color
    text_color = (255, 255, 255) if sum(rgb) < 384 else (0, 0, 0)
    draw.text((x, y), color_name, fill=text_color, font=font)

    return img

# Preprocessing function (matches your Dart code)
def preprocess_image(img):
    """Preprocess image: resize, normalize with mean=0.5, std=0.5."""
    # Convert to numpy array
    img_array = np.array(img).astype(np.float32)

    # Normalize: (pixel / 255.0 - 0.5) / 0.5  =  pixel / 127.5 - 1.0
    img_array = img_array / 127.5 - 1.0

    # Transpose from HWC to CHW (channels first)
    img_array = img_array.transpose(2, 0, 1)

    # Add batch dimension
    img_array = np.expand_dims(img_array, axis=0)

    return img_array

# Simple tokenization (matching your SigLIP tokenizer)
def tokenize_text(text):
    """Simple tokenization for testing. Uses basic vocab."""
    # For now, just create dummy token IDs
    # In production, this should match your actual tokenizer
    # Pad to 64 tokens with zeros
    tokens = [2] + [3] * min(len(text), 62) + [1]  # BOS, UNK tokens, EOS
    tokens = tokens + [0] * (64 - len(tokens))  # Pad with PAD tokens
    return np.array([tokens], dtype=np.int64)

# L2 normalization
def l2_normalize(v):
    """L2 normalize a vector."""
    norm = np.linalg.norm(v, axis=-1, keepdims=True)
    return v / (norm + 1e-8)

# Compute similarity
def compute_similarity(v1, v2):
    """Compute cosine similarity between two L2-normalized vectors."""
    return np.dot(v1, v2.T)[0, 0]

print("=== Test 1: Color Image vs Color Text ===\n")

# Test cases
test_cases = [
    ("red", (255, 0, 0)),
    ("blue", (0, 0, 255)),
    ("green", (0, 255, 0)),
]

# Generate embeddings for all images
image_embeddings = {}
for color_name, rgb in test_cases:
    img = create_colored_image(color_name, rgb)
    img_array = preprocess_image(img)

    # Run vision model
    vision_output = vision_session.run(None, {"pixel_values": img_array})[0]
    vision_embedding = l2_normalize(vision_output)

    image_embeddings[color_name] = vision_embedding
    print(f"Image '{color_name}': shape={vision_embedding.shape}, norm={np.linalg.norm(vision_embedding):.4f}")

print()

# Generate embeddings for all text
text_embeddings = {}
for color_name, _ in test_cases:
    tokens = tokenize_text(color_name)

    # Run text model
    text_output = text_session.run(None, {"input_ids": tokens})[0]
    text_embedding = l2_normalize(text_output)

    text_embeddings[color_name] = text_embedding
    print(f"Text '{color_name}': shape={text_embedding.shape}, norm={np.linalg.norm(text_embedding):.4f}")

print("\n=== Similarity Matrix ===\n")
print("         ", end="")
for text_name, _ in test_cases:
    print(f"{text_name:>8}", end="")
print()

for img_name, img_emb in image_embeddings.items():
    print(f"{img_name:>8} ", end="")
    for text_name, text_emb in text_embeddings.items():
        sim = compute_similarity(img_emb, text_emb)
        # Highlight diagonal (matching pairs)
        if img_name == text_name:
            print(f"*{sim:>7.4f}", end="")
        else:
            print(f" {sim:>7.4f}", end="")
    print()

print("\n=== Analysis ===")
print("Expected behavior:")
print("  - Diagonal values (matching pairs) should be HIGHEST")
print("  - Off-diagonal values should be lower")
print("  - Typical range for matches: 0.2 to 0.6")
print("  - If all values are near 0 (< 0.1), embeddings are NOT aligned!")

print("\n=== Checking Alignment ===")
all_sims = []
diagonal_sims = []
for img_name in image_embeddings:
    for text_name in text_embeddings:
        sim = compute_similarity(image_embeddings[img_name], text_embeddings[text_name])
        all_sims.append(sim)
        if img_name == text_name:
            diagonal_sims.append(sim)

avg_sim = np.mean(all_sims)
avg_diagonal = np.mean(diagonal_sims)

print(f"Average all similarities: {avg_sim:.4f}")
print(f"Average diagonal (matches): {avg_diagonal:.4f}")

if avg_diagonal > avg_sim + 0.05:
    print("[OK] Embeddings appear to be aligned!")
    print("     Matching pairs score higher than non-matching pairs.")
else:
    print("[ERROR] Embeddings do NOT appear to be aligned!")
    print("        Matching pairs should score significantly higher.")
    print("        This suggests the ONNX models are missing projection layers")
    print("        or there's an issue with preprocessing/normalization.")