#!/usr/bin/env python3
"""Export merged_epoch3_end_ver2 SigLIP model to split ONNX files.

Outputs:
  - merged_epoch3_end_vision_fp32.onnx  (vision encoder, ~354 MB)
  - merged_epoch3_end_text_fp32.onnx    (text encoder, ~421 MB)

Output tensor names match what the KitaKo app expects:
  - Vision: "image_features" (shape [batch, 768])
  - Text:   "text_features"  (shape [batch, 768])
"""

import os
import sys
import json
import numpy as np
import torch
import torch.nn as nn
from transformers import SiglipModel

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
MODEL_PATH = os.path.join(ROOT, "assets", "merged_epoch3_end")
OUTPUT_DIR = os.path.join(ROOT, "assets", "merged_epoch3_end", "onnx")


class VisionWrapper(nn.Module):
    def __init__(self, vision_model):
        super().__init__()
        self.vision_model = vision_model

    def forward(self, pixel_values):
        return self.vision_model(pixel_values=pixel_values).pooler_output


class TextWrapper(nn.Module):
    def __init__(self, text_model):
        super().__init__()
        self.text_model = text_model

    def forward(self, input_ids):
        return self.text_model(input_ids=input_ids).pooler_output


def main():
    print("=" * 60)
    print("Exporting merged_epoch3_end SigLIP -> ONNX")
    print("=" * 60)

    if not os.path.exists(MODEL_PATH):
        print(f"ERROR: Model not found at {MODEL_PATH}")
        sys.exit(1)

    os.makedirs(OUTPUT_DIR, exist_ok=True)

    with open(os.path.join(MODEL_PATH, "config.json")) as f:
        cfg = json.load(f)

    image_size  = cfg["vision_config"]["image_size"]   # 224
    vocab_size  = cfg["text_config"]["vocab_size"]      # 256000
    max_len     = cfg["text_config"]["max_position_embeddings"]  # 64

    print(f"image_size={image_size}, vocab_size={vocab_size}, max_len={max_len}")

    print("\nLoading model (this may take a moment)...")
    model = SiglipModel.from_pretrained(MODEL_PATH)
    model.eval()
    print("Model loaded.")

    # ── Vision ──────────────────────────────────────────────────────────────
    vision_path = os.path.join(OUTPUT_DIR, "merged_epoch3_end_vision_fp32.onnx")
    vision_wrapper = VisionWrapper(model.vision_model)
    vision_wrapper.eval()
    dummy_pixels = torch.randn(1, 3, image_size, image_size)

    with torch.no_grad():
        out = vision_wrapper(dummy_pixels)
        print(f"\nVision forward: shape={out.shape}, norm={torch.norm(out).item():.4f}")

    print(f"Exporting vision -> {vision_path}")
    torch.onnx.export(
        vision_wrapper, dummy_pixels, vision_path,
        input_names=["pixel_values"],
        output_names=["image_features"],
        dynamic_axes={"pixel_values": {0: "batch"}, "image_features": {0: "batch"}},
        opset_version=17,
        do_constant_folding=True,
        dynamo=False,
    )
    print(f"Vision size: {os.path.getsize(vision_path) / 1e6:.1f} MB")

    # ── Text ────────────────────────────────────────────────────────────────
    text_path = os.path.join(OUTPUT_DIR, "merged_epoch3_end_text_fp32.onnx")
    text_wrapper = TextWrapper(model.text_model)
    text_wrapper.eval()
    dummy_ids = torch.randint(0, vocab_size, (1, max_len))

    with torch.no_grad():
        out = text_wrapper(dummy_ids)
        print(f"\nText forward: shape={out.shape}, norm={torch.norm(out).item():.4f}")

    print(f"Exporting text -> {text_path}")
    torch.onnx.export(
        text_wrapper, dummy_ids, text_path,
        input_names=["input_ids"],
        output_names=["text_features"],
        dynamic_axes={"input_ids": {0: "batch", 1: "seq"}, "text_features": {0: "batch"}},
        opset_version=17,
        do_constant_folding=True,
        dynamo=False,
    )
    print(f"Text size: {os.path.getsize(text_path) / 1e6:.1f} MB")

    # ── Verify with ONNX Runtime ─────────────────────────────────────────────
    print("\nVerifying with ONNX Runtime...")
    try:
        import onnxruntime as ort

        vs = ort.InferenceSession(vision_path)
        vr = vs.run(None, {"pixel_values": dummy_pixels.numpy()})[0]
        with torch.no_grad():
            vt = vision_wrapper(dummy_pixels).numpy()
        print(f"Vision max diff (PT vs ORT): {np.max(np.abs(vr - vt)):.8f}")

        ts = ort.InferenceSession(text_path)
        tr = ts.run(None, {"input_ids": dummy_ids.numpy().astype(np.int64)})[0]
        with torch.no_grad():
            tt = text_wrapper(dummy_ids).numpy()
        print(f"Text   max diff (PT vs ORT): {np.max(np.abs(tr - tt)):.8f}")

        print("\nONNX models verified successfully!")
    except Exception as e:
        print(f"⚠️  Verification error: {e}")

    print("\n--- File sizes for model_download_service.dart ---")
    print(f"vision: {os.path.getsize(vision_path)} bytes")
    print(f"text:   {os.path.getsize(text_path)} bytes")
    print("\nDone.")


if __name__ == "__main__":
    main()
