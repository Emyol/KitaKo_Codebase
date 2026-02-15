#!/usr/bin/env python3
"""Export SigLIP using get_image_features/get_text_features (the CORRECT way)."""

import torch
import torch.nn as nn
from transformers import SiglipModel
import os

class SigLIPVisionCorrect(nn.Module):
    """Vision model that outputs pooler_output (aligned embedding)."""

    def __init__(self, vision_model):
        super().__init__()
        self.vision_model = vision_model

    def forward(self, pixel_values):
        # vision_model returns BaseModelOutputWithPooling
        # pooler_output is the [batch, 768] aligned embedding
        outputs = self.vision_model(pixel_values=pixel_values)
        return outputs.pooler_output


class SigLIPTextCorrect(nn.Module):
    """Text model that outputs pooler_output (aligned embedding)."""

    def __init__(self, text_model):
        super().__init__()
        self.text_model = text_model

    def forward(self, input_ids):
        # text_model returns BaseModelOutputWithPooling
        # pooler_output is the [batch, 768] aligned embedding
        outputs = self.text_model(input_ids=input_ids)
        return outputs.pooler_output


def main():
    model_id = "google/siglip-base-patch16-224"
    output_dir = "onnx_models_correct"

    print(f"Loading model: {model_id}")
    model = SiglipModel.from_pretrained(model_id)
    model.eval()

    os.makedirs(output_dir, exist_ok=True)

    # Export Vision Model
    print("\n=== Exporting Vision Model (CORRECT) ===")
    vision_wrapper = SigLIPVisionCorrect(model.vision_model)
    vision_wrapper.eval()

    dummy_pixel_values = torch.randn(1, 3, 224, 224)

    # Test forward pass
    with torch.no_grad():
        vision_output = vision_wrapper(dummy_pixel_values)
        print(f"Vision output shape: {vision_output.shape}")
        print(f"Vision output first 5: {vision_output[0, :5].tolist()}")
        print(f"Vision output norm: {torch.norm(vision_output).item():.4f}")

        # Check if normalized
        is_normalized = torch.allclose(torch.norm(vision_output, dim=-1), torch.ones(1), atol=1e-3)
        print(f"Is L2 normalized: {is_normalized}")

    vision_path = os.path.join(output_dir, "vision_model.onnx")

    # Suppress output
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
            output_names=["image_features"],
            dynamic_axes={
                "pixel_values": {0: "batch_size"},
                "image_features": {0: "batch_size"}
            },
            opset_version=17,
            do_constant_folding=True,
        )
    finally:
        sys.stdout = old_stdout
    print(f"[OK] Exported vision model to: {vision_path}")
    print(f"  Size: {os.path.getsize(vision_path) / 1024 / 1024:.2f} MB")

    # Export Text Model
    print("\n=== Exporting Text Model (CORRECT) ===")
    text_wrapper = SigLIPTextCorrect(model.text_model)
    text_wrapper.eval()

    dummy_input_ids = torch.randint(0, 32000, (1, 64))

    # Test forward pass
    with torch.no_grad():
        text_output = text_wrapper(dummy_input_ids)
        print(f"Text output shape: {text_output.shape}")
        print(f"Text output first 5: {text_output[0, :5].tolist()}")
        print(f"Text output norm: {torch.norm(text_output).item():.4f}")

        # Check if normalized
        is_normalized = torch.allclose(torch.norm(text_output, dim=-1), torch.ones(1), atol=1e-3)
        print(f"Is L2 normalized: {is_normalized}")

    text_path = os.path.join(output_dir, "text_model.onnx")

    sys.stdout = io.StringIO()
    try:
        torch.onnx.export(
            text_wrapper,
            dummy_input_ids,
            text_path,
            input_names=["input_ids"],
            output_names=["text_features"],
            dynamic_axes={
                "input_ids": {0: "batch_size", 1: "sequence_length"},
                "text_features": {0: "batch_size"}
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
    import numpy as np

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

    # Check normalization
    vision_norm = np.linalg.norm(vision_onnx_output, axis=-1)
    text_norm = np.linalg.norm(text_onnx_output, axis=-1)

    print(f"\nVision ONNX norm: {vision_norm[0]:.4f}")
    print(f"Text ONNX norm: {text_norm[0]:.4f}")

    # Compute similarity
    def normalize(v):
        return v / np.linalg.norm(v, axis=-1, keepdims=True)

    # Only normalize if not already normalized
    if not np.allclose(vision_norm, 1.0, atol=1e-3):
        print("Vision output needs normalization")
        v_norm = normalize(vision_onnx_output)
    else:
        print("Vision output already normalized!")
        v_norm = vision_onnx_output

    if not np.allclose(text_norm, 1.0, atol=1e-3):
        print("Text output needs normalization")
        t_norm = normalize(text_onnx_output)
    else:
        print("Text output already normalized!")
        t_norm = text_onnx_output

    similarity = np.dot(v_norm[0], t_norm[0])

    print(f"\nSimilarity between vision and text: {similarity:.4f}")
    print(f"(Random should be near 0, these are random inputs so ~0 is expected)")

    print("\n[SUCCESS] Export complete with CORRECT methods!")
    print(f"\nModels saved to: {output_dir}/")
    print(f"\nNext: Test these models with colored images to verify alignment")


if __name__ == "__main__":
    main()