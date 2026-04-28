#!/usr/bin/env python3
"""
Export SigLIP model to ONNX format using the LEGACY exporter.

This uses opset 13 which is compatible with ONNX Runtime 1.4.x on Android.

Requirements:
    pip install transformers torch onnx onnxruntime
"""

import os
import sys
import warnings

# Force legacy ONNX exporter (disable dynamo)
os.environ["TORCH_ONNX_USE_DYNAMO"] = "0"
os.environ["TORCH_DYNAMO_DISABLE"] = "1"
warnings.filterwarnings("ignore", category=UserWarning)
warnings.filterwarnings("ignore", category=FutureWarning)

import torch
# Disable dynamo completely
torch._dynamo.config.disable = True

def export_siglip():
    """Export SigLIP using the legacy ONNX exporter with opset 13."""
    from transformers import SiglipModel
    import onnx
    from onnxruntime.quantization import quantize_dynamic, QuantType
    
    SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
    PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
    ONNX_DIR = os.path.join(PROJECT_ROOT, "assets", "models", "onnx")
    os.makedirs(ONNX_DIR, exist_ok=True)
    
    # Load the model
    model_id = "google/siglip-base-patch16-224"
    print(f"Loading {model_id}...")
    
    model = SiglipModel.from_pretrained(model_id, torch_dtype=torch.float32)
    model.eval()
    
    # ==================== VISION ENCODER ====================
    print("\n=== Exporting Vision Encoder (opset 13) ===")
    
    class VisionWrapper(torch.nn.Module):
        def __init__(self, vision_model):
            super().__init__()
            self.vision_model = vision_model
            
        def forward(self, pixel_values):
            outputs = self.vision_model(pixel_values=pixel_values, return_dict=False)
            # outputs is (last_hidden_state, pooler_output)
            return outputs[1]  # Just return pooler_output (the embedding)
    
    vision_wrapper = VisionWrapper(model.vision_model)
    vision_wrapper.eval()
    
    dummy_pixel_values = torch.randn(1, 3, 224, 224)
    vision_path = os.path.join(ONNX_DIR, "siglip_vision_v13.onnx")
    
    with torch.no_grad():
        torch.onnx.export(
            vision_wrapper,
            (dummy_pixel_values,),
            vision_path,
            export_params=True,
            opset_version=13,  # Use opset 13 for Android compatibility
            do_constant_folding=True,
            input_names=["pixel_values"],
            output_names=["embedding"],
            dynamic_axes={
                "pixel_values": {0: "batch_size"},
                "embedding": {0: "batch_size"},
            },
        )
    
    print(f"  Saved to {vision_path}")
    
    # Verify
    onnx_model = onnx.load(vision_path)
    onnx.checker.check_model(onnx_model)
    print(f"  IR version: {onnx_model.ir_version}")
    print(f"  Opset: {[op.version for op in onnx_model.opset_import]}")
    print(f"  Size: {os.path.getsize(vision_path) / (1024*1024):.2f} MB")
    
    # Quantize
    print("\n  Quantizing vision encoder...")
    vision_quant_path = os.path.join(ONNX_DIR, "siglip_vision_encoder_quant.onnx")
    quantize_dynamic(
        vision_path,
        vision_quant_path,
        weight_type=QuantType.QUInt8,
    )
    print(f"  Quantized size: {os.path.getsize(vision_quant_path) / (1024*1024):.2f} MB")
    
    # ==================== TEXT ENCODER ====================
    print("\n=== Exporting Text Encoder (opset 13) ===")
    
    class TextWrapper(torch.nn.Module):
        def __init__(self, text_model):
            super().__init__()
            self.text_model = text_model
            
        def forward(self, input_ids):
            outputs = self.text_model(input_ids=input_ids, return_dict=False)
            # outputs is (last_hidden_state, pooler_output)
            return outputs[1]  # Just return pooler_output (the embedding)
    
    text_wrapper = TextWrapper(model.text_model)
    text_wrapper.eval()
    
    dummy_input_ids = torch.randint(0, 32000, (1, 64), dtype=torch.long)
    text_path = os.path.join(ONNX_DIR, "siglip_text_v13.onnx")
    
    with torch.no_grad():
        torch.onnx.export(
            text_wrapper,
            (dummy_input_ids,),
            text_path,
            export_params=True,
            opset_version=13,  # Use opset 13 for Android compatibility
            do_constant_folding=True,
            input_names=["input_ids"],
            output_names=["embedding"],
            dynamic_axes={
                "input_ids": {0: "batch_size", 1: "sequence_length"},
                "embedding": {0: "batch_size"},
            },
        )
    
    print(f"  Saved to {text_path}")
    
    # Verify
    onnx_model = onnx.load(text_path)
    onnx.checker.check_model(onnx_model)
    print(f"  IR version: {onnx_model.ir_version}")
    print(f"  Opset: {[op.version for op in onnx_model.opset_import]}")
    print(f"  Size: {os.path.getsize(text_path) / (1024*1024):.2f} MB")
    
    # Quantize
    print("\n  Quantizing text encoder...")
    text_quant_path = os.path.join(ONNX_DIR, "siglip_text_encoder_quant.onnx")
    quantize_dynamic(
        text_path,
        text_quant_path,
        weight_type=QuantType.QUInt8,
    )
    print(f"  Quantized size: {os.path.getsize(text_quant_path) / (1024*1024):.2f} MB")
    
    print("\n" + "=" * 60)
    print("✓ Export complete!")
    print("=" * 60)
    print(f"\nModels saved to: {ONNX_DIR}")
    print("\nNext: Push to Android device with:")
    print("  adb push siglip_vision_encoder_quant.onnx /sdcard/")
    print("  adb push siglip_text_encoder_quant.onnx /sdcard/")


if __name__ == "__main__":
    export_siglip()
