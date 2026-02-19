#!/usr/bin/env python3
"""Test Xenova's pre-exported ONNX models."""

import onnxruntime as ort
import numpy as np
from PIL import Image, ImageDraw, ImageFont
import json
import os

# Model paths
model_dir = "xenova_models/onnx"
vision_model = f"{model_dir}/vision_model_quantized.onnx"
text_model = f"{model_dir}/text_model_quantized.onnx"

# Tokenizer path
tokenizer_path = "../apps/kitako_app/assets/tokenizer/tokenizer.json"

print("=== Testing Xenova Pre-Exported ONNX Models ===\n")

# Check if models exist
if not os.path.exists(vision_model):
    print(f"ERROR: Vision model not found at {vision_model}")
    exit(1)
if not os.path.exists(text_model):
    print(f"ERROR: Text model not found at {text_model}")
    exit(1)

# Load tokenizer
print(f"Loading tokenizer from: {tokenizer_path}")
with open(tokenizer_path, 'r', encoding='utf-8') as f:
    tokenizer_data = json.load(f)

vocab = tokenizer_data['model']['vocab']
vocab_dict = {}
for i, item in enumerate(vocab):
    if isinstance(item, list) and len(item) >= 1:
        token = item[0]
        vocab_dict[token] = i

unk_token_id = 3
eos_token_id = 1
pad_token_id = 0

def simple_tokenize(text):
    """Simple tokenization."""
    tokens = []
    for word in text.lower().split():
        if word in vocab_dict:
            tokens.append(vocab_dict[word])
        else:
            for char in word:
                if char in vocab_dict:
                    tokens.append(vocab_dict[char])
                    break
            else:
                tokens.append(unk_token_id)

    tokens.append(eos_token_id)

    if len(tokens) < 64:
        tokens = tokens + [pad_token_id] * (64 - len(tokens))
    else:
        tokens = tokens[:63] + [eos_token_id]

    return np.array([tokens], dtype=np.int64)

# Load models
print("Loading Xenova ONNX models...")
vision_session = ort.InferenceSession(vision_model)
text_session = ort.InferenceSession(text_model)
print("[OK] Models loaded\n")

# Check model inputs/outputs
print("=== Model Signatures ===")
print("Vision inputs:", [inp.name for inp in vision_session.get_inputs()])
print("Vision outputs:", [out.name for out in vision_session.get_outputs()])
print("Text inputs:", [inp.name for inp in text_session.get_inputs()])
print("Text outputs:", [out.name for out in text_session.get_outputs()])
print()

# Create test images
def create_colored_image(color_name, rgb):
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

def preprocess_image(img):
    img_array = np.array(img).astype(np.float32)
    img_array = img_array / 127.5 - 1.0
    img_array = img_array.transpose(2, 0, 1)
    img_array = np.expand_dims(img_array, axis=0)
    return img_array

def l2_normalize(v):
    norm = np.linalg.norm(v, axis=-1, keepdims=True)
    return v / (norm + 1e-8)

def compute_similarity(v1, v2):
    return np.dot(v1, v2.T)[0, 0]

print("=== Test Cases ===\n")

test_cases = [
    ("red", (255, 0, 0)),
    ("blue", (0, 0, 255)),
    ("green", (0, 255, 0)),
]

# Generate embeddings
image_embeddings = {}
for color_name, rgb in test_cases:
    img = create_colored_image(color_name, rgb)
    img_array = preprocess_image(img)

    # Get all outputs, pooler_output is the second one (index 1)
    vision_outputs = vision_session.run(None, {"pixel_values": img_array})
    vision_output = vision_outputs[1]  # pooler_output
    norm_before = np.linalg.norm(vision_output)

    # Check if already normalized
    if abs(norm_before - 1.0) < 0.01:
        print(f"Image '{color_name}': norm={norm_before:.4f} (already normalized!)")
        vision_embedding = vision_output
    else:
        print(f"Image '{color_name}': norm={norm_before:.4f} (needs normalization)")
        vision_embedding = l2_normalize(vision_output)

    image_embeddings[color_name] = vision_embedding

print()

text_embeddings = {}
for color_name, _ in test_cases:
    tokens = simple_tokenize(color_name)
    print(f"Text '{color_name}': tokens = {tokens[0][:10].tolist()}...")

    # Get all outputs, pooler_output is the second one (index 1)
    text_outputs = text_session.run(None, {"input_ids": tokens})
    text_output = text_outputs[1]  # pooler_output
    norm_before = np.linalg.norm(text_output)

    # Check if already normalized
    if abs(norm_before - 1.0) < 0.01:
        print(f"  norm={norm_before:.4f} (already normalized!)")
        text_embedding = text_output
    else:
        print(f"  norm={norm_before:.4f} (needs normalization)")
        text_embedding = l2_normalize(text_output)

    text_embeddings[color_name] = text_embedding

print("\n=== Similarity Matrix (Xenova Models) ===\n")
print("         ", end="")
for text_name, _ in test_cases:
    print(f"{text_name:>8}", end="")
print()

for img_name, img_emb in image_embeddings.items():
    print(f"{img_name:>8} ", end="")
    for text_name, text_emb in text_embeddings.items():
        sim = compute_similarity(img_emb, text_emb)
        if img_name == text_name:
            print(f"*{sim:>7.4f}", end="")
        else:
            print(f" {sim:>7.4f}", end="")
    print()

print("\n=== Analysis ===")
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
print(f"Difference: {avg_diagonal - avg_sim:.4f}")

if avg_diagonal > avg_sim + 0.05:
    print("\n[OK] Xenova models ARE ALIGNED!")
    print("     Matching pairs score higher than non-matching pairs.")
    print("     These models should work for your app!")
else:
    print("\n[ERROR] Xenova models also show weak alignment.")
    print("        Expected diagonal >> average, but they're similar.")