#!/usr/bin/env python3
"""Export the fine-tuned SigLIP model (merged_epoch8_step6024) to split ONNX files.

This script loads the fine-tuned SigLIP model from safetensors and exports it
as two separate ONNX files (vision encoder + text encoder) compatible with
the KitaKo app's ONNX Runtime Mobile inference pipeline.

Output files:
  - finetuned_vision_model_fp32.onnx  (vision encoder, ~354 MB)
  - finetuned_text_model_fp32.onnx    (text encoder, ~421 MB)

The output tensor names match what the app expects:
  - Vision: "image_features" (shape [batch, 768])
  - Text:   "text_features"  (shape [batch, 768])
"""

import torch
import torch.nn as nn
from transformers import SiglipModel
import os
import sys
import io
import numpy as np

# Path to the fine-tuned model
MODEL_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "apps", "kitako_app", "assets", "model", "merged_epoch8_step6024"
)

OUTPUT_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "apps", "kitako_app", "assets", "model", "merged_epoch8_step6024", "onnx"
)


class SigLIPVisionWrapper(nn.Module):
    """Vision model wrapper that outputs pooler_output (aligned embedding)."""

    def __init__(self, vision_model):
        super().__init__()
        self.vision_model = vision_model

    def forward(self, pixel_values):
        outputs = self.vision_model(pixel_values=pixel_values)
        return outputs.pooler_output  # [batch, 768]


class SigLIPTextWrapper(nn.Module):
    """Text model wrapper that outputs pooler_output (aligned embedding)."""

    def __init__(self, text_model):
        super().__init__()
        self.text_model = text_model

    def forward(self, input_ids):
        outputs = self.text_model(input_ids=input_ids)
        return outputs.pooler_output  # [batch, 768]


def main():
    print(f"=" * 60)
    print(f"Exporting Fine-Tuned SigLIP Model to ONNX")
    print(f"=" * 60)
    print(f"Model path: {MODEL_PATH}")
    print(f"Output dir: {OUTPUT_DIR}")

    if not os.path.exists(MODEL_PATH):
        print(f"ERROR: Model path does not exist: {MODEL_PATH}")
        sys.exit(1)

    config_path = os.path.join(MODEL_PATH, "config.json")
    if not os.path.exists(config_path):
        print(f"ERROR: config.json not found in {MODEL_PATH}")
        sys.exit(1)

    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # Load the fine-tuned model
    print(f"\nLoading fine-tuned model from: {MODEL_PATH}")
    print("This may take a moment for a 1.5GB model...")
    model = SiglipModel.from_pretrained(MODEL_PATH)
    model.eval()
    print("Model loaded successfully!")

    # Read config to get parameters
    import json
    with open(config_path, "r") as f:
        config = json.load(f)

    image_size = config.get("vision_config", {}).get("image_size", 224)
    vocab_size = config.get("text_config", {}).get("vocab_size", 256000)
    max_len = config.get("text_config", {}).get("max_position_embeddings", 64)
    hidden_size = config.get("text_config", {}).get("hidden_size", 768)

    print(f"\nModel config:")
    print(f"  Image size: {image_size}x{image_size}")
    print(f"  Vocab size: {vocab_size}")
    print(f"  Max text length: {max_len}")
    print(f"  Hidden size: {hidden_size}")

    # ===================== EXPORT VISION MODEL =====================
    print(f"\n{'='*60}")
    print("Exporting Vision Model...")
    print(f"{'='*60}")

    vision_wrapper = SigLIPVisionWrapper(model.vision_model)
    vision_wrapper.eval()

    dummy_pixel_values = torch.randn(1, 3, image_size, image_size)

    # Test forward pass
    with torch.no_grad():
        vision_output = vision_wrapper(dummy_pixel_values)
        print(f"  Output shape: {vision_output.shape}")
        print(f"  Output norm: {torch.norm(vision_output).item():.4f}")
        print(f"  First 5 values: {vision_output[0, :5].tolist()}")

    vision_path = os.path.join(OUTPUT_DIR, "finetuned_vision_model_fp32.onnx")

    # Use legacy (TorchScript) exporter for compatibility
    torch.onnx.export(
        vision_wrapper,
        dummy_pixel_values,
        vision_path,
        input_names=["pixel_values"],
        output_names=["image_features"],
        dynamic_axes={
            "pixel_values": {0: "batch_size"},
            "image_features": {0: "batch_size"},
        },
        opset_version=17,
        do_constant_folding=True,
        dynamo=False,
    )

    vision_size_mb = os.path.getsize(vision_path) / (1024 * 1024)
    print(f"  Exported to: {vision_path}")
    print(f"  Size: {vision_size_mb:.2f} MB")

    # ===================== EXPORT TEXT MODEL =====================
    print(f"\n{'='*60}")
    print("Exporting Text Model...")
    print(f"{'='*60}")

    text_wrapper = SigLIPTextWrapper(model.text_model)
    text_wrapper.eval()

    dummy_input_ids = torch.randint(0, vocab_size, (1, max_len))

    # Test forward pass
    with torch.no_grad():
        text_output = text_wrapper(dummy_input_ids)
        print(f"  Output shape: {text_output.shape}")
        print(f"  Output norm: {torch.norm(text_output).item():.4f}")
        print(f"  First 5 values: {text_output[0, :5].tolist()}")

    text_path = os.path.join(OUTPUT_DIR, "finetuned_text_model_fp32.onnx")

    # Use legacy (TorchScript) exporter for compatibility
    torch.onnx.export(
        text_wrapper,
        dummy_input_ids,
        text_path,
        input_names=["input_ids"],
        output_names=["text_features"],
        dynamic_axes={
            "input_ids": {0: "batch_size", 1: "sequence_length"},
            "text_features": {0: "batch_size"},
        },
        opset_version=17,
        do_constant_folding=True,
        dynamo=False,
    )

    text_size_mb = os.path.getsize(text_path) / (1024 * 1024)
    print(f"  Exported to: {text_path}")
    print(f"  Size: {text_size_mb:.2f} MB")

    # ===================== VERIFY WITH ONNX RUNTIME =====================
    print(f"\n{'='*60}")
    print("Verifying ONNX models with ONNX Runtime...")
    print(f"{'='*60}")

    try:
        import onnxruntime as ort

        # Verify vision model
        vision_session = ort.InferenceSession(vision_path)
        vision_inputs = vision_session.get_inputs()
        vision_outputs = vision_session.get_outputs()
        print(f"\n  Vision model inputs:  {[(i.name, i.shape) for i in vision_inputs]}")
        print(f"  Vision model outputs: {[(o.name, o.shape) for o in vision_outputs]}")

        vision_result = vision_session.run(
            None, {"pixel_values": dummy_pixel_values.numpy()}
        )[0]
        print(f"  Vision ONNX output shape: {vision_result.shape}")

        # Compare with PyTorch
        with torch.no_grad():
            pt_vision = vision_wrapper(dummy_pixel_values).numpy()
        vision_diff = np.max(np.abs(vision_result - pt_vision))
        print(f"  Max diff PyTorch vs ONNX (vision): {vision_diff:.8f}")

        # Verify text model
        text_session = ort.InferenceSession(text_path)
        text_inputs = text_session.get_inputs()
        text_outputs = text_session.get_outputs()
        print(f"\n  Text model inputs:  {[(i.name, i.shape) for i in text_inputs]}")
        print(f"  Text model outputs: {[(o.name, o.shape) for o in text_outputs]}")

        text_result = text_session.run(
            None, {"input_ids": dummy_input_ids.numpy().astype(np.int64)}
        )[0]
        print(f"  Text ONNX output shape: {text_result.shape}")

        with torch.no_grad():
            pt_text = text_wrapper(dummy_input_ids).numpy()
        text_diff = np.max(np.abs(text_result - pt_text))
        print(f"  Max diff PyTorch vs ONNX (text): {text_diff:.8f}")

        if vision_diff < 1e-4 and text_diff < 1e-4:
            print("\n  ✅ ONNX models verified - output matches PyTorch!")
        else:
            print(f"\n  ⚠️  Some numerical differences detected (vision: {vision_diff:.6f}, text: {text_diff:.6f})")
            print("     This is usually acceptable for FP32 models.")

    except ImportError:
        print("  ⚠️ onnxruntime not installed, skipping verification.")

    # ===================== SUMMARY =====================
    print(f"\n{'='*60}")
    print("EXPORT COMPLETE")
    print(f"{'='*60}")
    print(f"  Vision model: {vision_path} ({vision_size_mb:.1f} MB)")
    print(f"  Text model:   {text_path} ({text_size_mb:.1f} MB)")
    print(f"\nNext steps:")
    print(f"  1. Push to phone via ADB:")
    print(f"     adb push \"{vision_path}\" /data/local/tmp/finetuned_vision_model_fp32.onnx")
    print(f"     adb push \"{text_path}\" /data/local/tmp/finetuned_text_model_fp32.onnx")
    print(f"  2. The app will auto-detect these models on restart.")


if __name__ == "__main__":
    main()
