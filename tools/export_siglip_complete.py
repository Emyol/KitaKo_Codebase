#!/usr/bin/env python3
"""Export complete SigLIP models with projection layers."""

import torch
import torch.nn as nn
from transformers import SiglipModel
import os

class SigLIPVisionComplete(nn.Module):
    """Complete vision model: embeddings -> encoder -> post_layernorm -> head (projection)."""

    def __init__(self, model):
        super().__init__()
        self.vision_model = model.vision_model

    def forward(self, pixel_values):
        # This calls the full vision model including the head (projection)
        return self.vision_model(pixel_values=pixel_values).pooler_output


class SigLIPTextComplete(nn.Module):
    """Complete text model: embeddings -> encoder -> final_layer_norm -> head (projection)."""

    def __init__(self, model):
        super().__init__()
        self.text_model = model.text_model

    def forward(self, input_ids):
        # This calls the full text model including the head (projection)
        return self.text_model(input_ids=input_ids).pooler_output


def main():
    model_id = "google/siglip-base-patch16-224"
    output_dir = "onnx_models_complete"

    print(f"Loading model: {model_id}")
    model = SiglipModel.from_pretrained(model_id)
    model.eval()

    os.makedirs(output_dir, exist_ok=True)

    # Export Vision Model
    print("\n=== Exporting Vision Model ===")
    vision_wrapper = SigLIPVisionComplete(model)
    vision_wrapper.eval()

    # Create dummy input (batch_size=1, channels=3, height=224, width=224)
    dummy_pixel_values = torch.randn(1, 3, 224, 224)

    # Test forward pass
    with torch.no_grad():
        vision_output = vision_wrapper(dummy_pixel_values)
        print(f"Vision output shape: {vision_output.shape}")
        print(f"Vision output first 10: {vision_output[0, :10].tolist()}")
        print(f"Vision output norm: {torch.norm(vision_output).item():.4f}")

    vision_path = os.path.join(output_dir, "vision_model.onnx")

    # Redirect stdout to suppress Unicode warnings
    import sys
    import io
    old_stdout = sys.stdout
    sys.stdout = io.StringIO()

    try:
        torch.onnx.export(
            vision_wrapper,
            dummy_pixel_values,
            vision_path,
            input_names=["pixel_values"],
            output_names=["pooler_output"],
            dynamic_axes={
                "pixel_values": {0: "batch_size"},
                "pooler_output": {0: "batch_size"}
            },
            opset_version=17,
            do_constant_folding=True,
        )
    finally:
        sys.stdout = old_stdout
    print(f"[OK] Exported vision model to: {vision_path}")
    print(f"  Size: {os.path.getsize(vision_path) / 1024 / 1024:.2f} MB")

    # Export Text Model
    print("\n=== Exporting Text Model ===")
    text_wrapper = SigLIPTextComplete(model)
    text_wrapper.eval()

    # Create dummy input (batch_size=1, sequence_length=64)
    dummy_input_ids = torch.randint(0, 32000, (1, 64))

    # Test forward pass
    with torch.no_grad():
        text_output = text_wrapper(dummy_input_ids)
        print(f"Text output shape: {text_output.shape}")
        print(f"Text output first 10: {text_output[0, :10].tolist()}")
        print(f"Text output norm: {torch.norm(text_output).item():.4f}")

    text_path = os.path.join(output_dir, "text_model.onnx")

    sys.stdout = io.StringIO()
    try:
        torch.onnx.export(
            text_wrapper,
            dummy_input_ids,
            text_path,
            input_names=["input_ids"],
            output_names=["pooler_output"],
            dynamic_axes={
                "input_ids": {0: "batch_size", 1: "sequence_length"},
                "pooler_output": {0: "batch_size"}
            },
            opset_version=17,
            do_constant_folding=True,
        )
    finally:
        sys.stdout = old_stdout
    print(f"[OK] Exported text model to: {text_path}")
    print(f"  Size: {os.path.getsize(text_path) / 1024 / 1024:.2f} MB")

    # Test alignment
    print("\n=== Testing Alignment ===")
    import onnxruntime as ort

    vision_session = ort.InferenceSession(vision_path)
    text_session = ort.InferenceSession(text_path)

    # Run ONNX models
    vision_onnx_output = vision_session.run(
        None,
        {"pixel_values": dummy_pixel_values.numpy()}
    )[0]

    text_onnx_output = text_session.run(
        None,
        {"input_ids": dummy_input_ids.numpy()}
    )[0]

    print(f"Vision ONNX output shape: {vision_onnx_output.shape}")
    print(f"Text ONNX output shape: {text_onnx_output.shape}")

    # Compare with PyTorch
    vision_torch_output = vision_output.numpy()
    text_torch_output = text_output.numpy()

    vision_match = np.allclose(vision_onnx_output, vision_torch_output, atol=1e-4)
    text_match = np.allclose(text_onnx_output, text_torch_output, atol=1e-4)

    print(f"\nVision ONNX matches PyTorch: {vision_match}")
    print(f"Text ONNX matches PyTorch: {text_match}")

    # Compute similarity
    def normalize(v):
        return v / np.linalg.norm(v, axis=-1, keepdims=True)

    v_norm = normalize(vision_onnx_output)
    t_norm = normalize(text_onnx_output)
    similarity = np.dot(v_norm[0], t_norm[0])

    print(f"\nSimilarity between vision and text embeddings: {similarity:.4f}")
    print(f"(Random embeddings should be near 0, matched should be positive)")

    print("\n[SUCCESS] Export complete!")
    print(f"\nNext steps:")
    print(f"1. Quantize the models (optional)")
    print(f"2. Copy to Android device:")
    print(f"   adb push {vision_path} /data/local/tmp/")
    print(f"   adb push {text_path} /data/local/tmp/")


if __name__ == "__main__":
    import numpy as np
    main()