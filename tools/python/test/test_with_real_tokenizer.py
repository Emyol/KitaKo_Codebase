#!/usr/bin/env python3
"""Test ONNX models with REAL SigLIP tokenizer."""

import onnxruntime as ort
import numpy as np
from PIL import Image, ImageDraw, ImageFont
import json

# Model paths
model_dir = "onnx_models_complete"
vision_model = f"{model_dir}/vision_model.onnx"
text_model = f"{model_dir}/text_model.onnx"

# Tokenizer path
tokenizer_path = "../apps/kitako_app/assets/tokenizer/tokenizer.json"

print("=== Testing with REAL Tokenizer ===\n")

# Load tokenizer
print(f"Loading tokenizer from: {tokenizer_path}")
with open(tokenizer_path, 'r', encoding='utf-8') as f:
    tokenizer_data = json.load(f)

vocab = tokenizer_data['model']['vocab']
print(f"Vocab size: {len(vocab)}")

# Build vocab dict (format is [['token', score], ...])
vocab_dict = {}
for i, item in enumerate(vocab):
    if isinstance(item, list) and len(item) >= 1:
        token = item[0]
        vocab_dict[token] = i

# Special tokens
unk_token_id = 3
eos_token_id = 1
pad_token_id = 0

print(f"UNK: {unk_token_id}, EOS: {eos_token_id}, PAD: {pad_token_id}\n")

def simple_tokenize(text):
    """Very simple tokenization - split on spaces and look up in vocab."""
    tokens = []
    for word in text.lower().split():
        # Try to find token
        if word in vocab_dict:
            tokens.append(vocab_dict[word])
        else:
            # Try character by character
            found = False
            for char in word:
                if char in vocab_dict:
                    tokens.append(vocab_dict[char])
                    found = True
                    break
            if not found:
                tokens.append(unk_token_id)

    # Add EOS
    tokens.append(eos_token_id)

    # Pad or truncate to 64
    if len(tokens) < 64:
        tokens = tokens + [pad_token_id] * (64 - len(tokens))
    else:
        tokens = tokens[:63] + [eos_token_id]

    return np.array([tokens], dtype=np.int64)

# Load models
print("Loading ONNX models...")
vision_session = ort.InferenceSession(vision_model)
text_session = ort.InferenceSession(text_model)
print("[OK] Models loaded\n")

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

    vision_output = vision_session.run(None, {"pixel_values": img_array})[0]
    vision_embedding = l2_normalize(vision_output)

    image_embeddings[color_name] = vision_embedding
    print(f"Image '{color_name}': norm before L2 = {np.linalg.norm(vision_output):.4f}")

print()

text_embeddings = {}
for color_name, _ in test_cases:
    tokens = simple_tokenize(color_name)
    print(f"Text '{color_name}': tokens = {tokens[0][:10].tolist()}...")

    text_output = text_session.run(None, {"input_ids": tokens})[0]
    text_embedding = l2_normalize(text_output)

    text_embeddings[color_name] = text_embedding
    print(f"  norm before L2 = {np.linalg.norm(text_output):.4f}")

print("\n=== Similarity Matrix ===\n")
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
    print("[OK] Embeddings ARE aligned!")
    print("     Matching pairs score higher!")
else:
    print("[ERROR] Embeddings are NOT aligned!")
    print("        The ONNX export is fundamentally broken.")