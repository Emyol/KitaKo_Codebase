#!/usr/bin/env python3
"""
Test script to verify ONNX SigLIP models produce aligned vision/text embeddings.
This helps diagnose why the Flutter app shows negative similarity between
vision and text embeddings.
"""

import os
import sys
import numpy as np
from pathlib import Path

# Add parent dir to path for imports
script_dir = Path(__file__).parent
project_root = script_dir.parent

# Model paths
VISION_MODEL = project_root / "assets/models/onnx/siglip_vision_encoder_quant.onnx"
TEXT_MODEL = project_root / "assets/models/onnx/siglip_text_encoder_quant.onnx"
TOKENIZER_PATH = project_root / "apps/kitako_app/assets/tokenizer/tokenizer.json"

# Test image (use any image from dataset)
TEST_IMAGES_DIR = project_root / "dataset/images/taglish_test_images"


def install_deps():
    """Install required packages if missing."""
    import subprocess
    packages = ["onnxruntime", "pillow", "tokenizers", "numpy"]
    for pkg in packages:
        try:
            __import__(pkg.replace("-", "_"))
        except ImportError:
            print(f"Installing {pkg}...")
            subprocess.check_call([sys.executable, "-m", "pip", "install", pkg, "-q"])


def load_tokenizer(tokenizer_path: str):
    """Load the SigLIP tokenizer."""
    from tokenizers import Tokenizer
    return Tokenizer.from_file(tokenizer_path)


def tokenize_text(tokenizer, text: str, max_length: int = 64):
    """Tokenize text for SigLIP model."""
    encoding = tokenizer.encode(text)
    token_ids = encoding.ids[:max_length]
    
    # Pad to max_length
    if len(token_ids) < max_length:
        token_ids = token_ids + [0] * (max_length - len(token_ids))
    
    return np.array([token_ids], dtype=np.int64)


def preprocess_image(image_path: str, size: int = 224):
    """Preprocess image for SigLIP model (NCHW format, normalized)."""
    from PIL import Image
    
    img = Image.open(image_path).convert("RGB")
    img = img.resize((size, size), Image.Resampling.BILINEAR)
    
    # Convert to numpy array
    img_array = np.array(img, dtype=np.float32) / 255.0
    
    # Normalize with ImageNet mean/std (SigLIP uses similar)
    mean = np.array([0.485, 0.456, 0.406], dtype=np.float32)
    std = np.array([0.229, 0.224, 0.225], dtype=np.float32)
    img_array = (img_array - mean) / std
    
    # Convert to NCHW format [1, 3, 224, 224]
    img_array = np.transpose(img_array, (2, 0, 1))
    img_array = np.expand_dims(img_array, axis=0)
    
    return img_array.astype(np.float32)


def l2_normalize(embedding: np.ndarray) -> np.ndarray:
    """L2 normalize an embedding vector."""
    norm = np.linalg.norm(embedding)
    if norm == 0:
        return embedding
    return embedding / norm


def cosine_similarity(a: np.ndarray, b: np.ndarray) -> float:
    """Compute cosine similarity between two vectors."""
    return float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b) + 1e-8))


def test_models():
    """Test vision and text encoders produce aligned embeddings."""
    import onnxruntime as ort
    
    print("=" * 60)
    print("ONNX SigLIP Embedding Test")
    print("=" * 60)
    
    # Check if model files exist
    if not VISION_MODEL.exists():
        print(f"ERROR: Vision model not found: {VISION_MODEL}")
        return
    if not TEXT_MODEL.exists():
        print(f"ERROR: Text model not found: {TEXT_MODEL}")
        return
    if not TOKENIZER_PATH.exists():
        print(f"ERROR: Tokenizer not found: {TOKENIZER_PATH}")
        return
    
    print(f"\nVision model: {VISION_MODEL}")
    print(f"Text model: {TEXT_MODEL}")
    print(f"Tokenizer: {TOKENIZER_PATH}")
    
    # Load tokenizer
    print("\nLoading tokenizer...")
    tokenizer = load_tokenizer(str(TOKENIZER_PATH))
    print(f"  Vocab size: {tokenizer.get_vocab_size()}")
    
    # Load vision encoder
    print("\nLoading vision encoder...")
    vision_session = ort.InferenceSession(str(VISION_MODEL))
    vision_inputs = vision_session.get_inputs()
    vision_outputs = vision_session.get_outputs()
    print(f"  Inputs: {[(i.name, i.shape) for i in vision_inputs]}")
    print(f"  Outputs: {[(o.name, o.shape) for o in vision_outputs]}")
    
    # Load text encoder
    print("\nLoading text encoder...")
    text_session = ort.InferenceSession(str(TEXT_MODEL))
    text_inputs = text_session.get_inputs()
    text_outputs = text_session.get_outputs()
    print(f"  Inputs: {[(i.name, i.shape) for i in text_inputs]}")
    print(f"  Outputs: {[(o.name, o.shape) for o in text_outputs]}")
    
    # Find a test image
    test_images = list(TEST_IMAGES_DIR.glob("*.jpg")) + list(TEST_IMAGES_DIR.glob("*.png"))
    if not test_images:
        print(f"\nERROR: No test images found in {TEST_IMAGES_DIR}")
        return
    
    test_image = test_images[0]
    print(f"\nTest image: {test_image.name}")
    
    # Generate vision embedding
    print("\n--- Vision Embedding ---")
    img_input = preprocess_image(str(test_image))
    print(f"Input shape: {img_input.shape}, dtype: {img_input.dtype}")
    
    vision_result = vision_session.run(None, {"pixel_values": img_input})
    vision_output = vision_result[0]
    print(f"Output shape: {vision_output.shape}")
    print(f"Output range: [{vision_output.min():.4f}, {vision_output.max():.4f}]")
    
    # Handle different output shapes
    if len(vision_output.shape) == 3:
        # Shape: [1, num_patches, embedding_dim] - need pooling
        num_patches = vision_output.shape[1]
        print(f"3D output with {num_patches} patches, using MEAN pooling...")
        vision_embedding = vision_output[0].mean(axis=0)  # Mean over patches
    elif len(vision_output.shape) == 2:
        # Shape: [1, embedding_dim] - already pooled
        vision_embedding = vision_output[0]
    else:
        vision_embedding = vision_output.flatten()
    
    vision_embedding = l2_normalize(vision_embedding)
    print(f"Vision embedding shape: {vision_embedding.shape}")
    print(f"Vision embedding norm: {np.linalg.norm(vision_embedding):.4f}")
    print(f"First 10 values: {vision_embedding[:10]}")
    
    # Generate text embeddings for various queries
    print("\n--- Text Embeddings ---")
    test_queries = [
        "a photo",
        "a person",
        "a dog",
        "nature",
        "billiards",
        "monkey",
        "food",
        "sunset",
    ]
    
    for query in test_queries:
        tokens = tokenize_text(tokenizer, query)
        
        text_result = text_session.run(None, {"input_ids": tokens})
        text_output = text_result[0]
        
        # Handle different output shapes
        if len(text_output.shape) == 3:
            # Shape: [1, seq_len, embedding_dim] - need pooling
            # Find last non-zero token position
            non_pad_mask = tokens[0] != 0
            num_tokens = non_pad_mask.sum()
            print(f"Query: '{query}' ({num_tokens} tokens)")
            
            # Mean pooling over non-padding tokens
            text_embedding = text_output[0, :num_tokens, :].mean(axis=0)
        elif len(text_output.shape) == 2:
            text_embedding = text_output[0]
            print(f"Query: '{query}'")
        else:
            text_embedding = text_output.flatten()
            print(f"Query: '{query}'")
        
        text_embedding = l2_normalize(text_embedding)
        
        # Compute similarity with vision embedding
        similarity = cosine_similarity(vision_embedding, text_embedding)
        print(f"  Similarity with image: {similarity:.4f}")
    
    # Test if vision embeddings are consistent
    print("\n--- Vision Embedding Consistency ---")
    if len(test_images) > 1:
        img2_input = preprocess_image(str(test_images[1]))
        vision_result2 = vision_session.run(None, {"pixel_values": img2_input})
        vision_output2 = vision_result2[0]
        
        if len(vision_output2.shape) == 3:
            vision_embedding2 = vision_output2[0].mean(axis=0)
        else:
            vision_embedding2 = vision_output2[0] if len(vision_output2.shape) == 2 else vision_output2.flatten()
        
        vision_embedding2 = l2_normalize(vision_embedding2)
        
        img_similarity = cosine_similarity(vision_embedding, vision_embedding2)
        print(f"Similarity between image 1 and image 2: {img_similarity:.4f}")
    
    print("\n" + "=" * 60)
    print("DIAGNOSIS:")
    print("=" * 60)
    print("""
If you see:
- NEGATIVE similarities (-0.1 to -0.5): Vision and text encoders are NOT aligned.
  The ONNX models may be missing projection layers.
  
- VERY LOW similarities (0.0 to 0.1): Embeddings are in different spaces.
  Check if the model needs special preprocessing or post-processing.
  
- REASONABLE similarities (0.2 to 0.5): Models are working correctly!
  Higher similarities for relevant queries indicate good alignment.
""")


if __name__ == "__main__":
    install_deps()
    test_models()
