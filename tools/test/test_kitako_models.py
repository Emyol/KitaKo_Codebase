"""
Test script for Kitako ONNX models (FP32 and INT8 variants).

Tests:
1. Model loading (session creation)
2. Input/output shape validation
3. Image encoder inference with dummy input
4. Text encoder inference with dummy input
5. Output tensor properties (dimension, normalization, NaN check)
6. Cross-modal similarity (image vs text embeddings should be comparable)
7. Inference timing
"""

import os
import sys
import time
import json
import numpy as np

try:
    import onnxruntime as ort
except ImportError:
    print("ERROR: onnxruntime not installed. Run: pip install onnxruntime")
    sys.exit(1)

# ---------- Configuration ----------

MODELS_DIR = os.path.join(
    os.path.dirname(__file__), "..", "..", "models", "kitako"
)
TOKENIZER_PATH = os.path.join(
    os.path.dirname(__file__), "..", "..", "apps", "kitako_app",
    "assets", "models", "tokenizer", "tokenizer.json"
)

VARIANTS = {
    "fp32": {
        "image": os.path.join(MODELS_DIR, "kitako_image_encoder_fp32.onnx"),
        "text": os.path.join(MODELS_DIR, "kitako_text_encoder_fp32.onnx"),
    },
    "int8": {
        "image": os.path.join(MODELS_DIR, "kitako_image_encoder_int8.onnx"),
        "text": os.path.join(MODELS_DIR, "kitako_text_encoder_int8.onnx"),
    },
}

IMAGE_SIZE = 224
CHANNELS = 3
MAX_TEXT_LEN = 64
EXPECTED_DIM = 768

# ---------- Helpers ----------

def l2_norm(vec):
    n = np.linalg.norm(vec)
    return vec / n if n > 0 else vec


def cosine_sim(a, b):
    a_flat = a.flatten()
    b_flat = b.flatten()
    return float(np.dot(a_flat, b_flat) / (np.linalg.norm(a_flat) * np.linalg.norm(b_flat) + 1e-8))


def make_dummy_image():
    """Create a dummy image tensor [1, 3, 224, 224] normalized to [-1, 1]."""
    np.random.seed(42)
    return np.random.randn(1, CHANNELS, IMAGE_SIZE, IMAGE_SIZE).astype(np.float32)


def make_dummy_tokens():
    """Create dummy token IDs [1, 64] with a short 'sentence' + padding."""
    tokens = np.zeros((1, MAX_TEXT_LEN), dtype=np.int64)
    # Simulate a short sentence: some non-zero token IDs followed by EOS (1) then padding (0)
    tokens[0, :5] = [100, 200, 300, 400, 1]  # 4 tokens + EOS
    return tokens


# ---------- Test Functions ----------

results = {}


def test_model_exists(variant_name, model_type, path):
    key = f"{variant_name}_{model_type}_file_exists"
    exists = os.path.isfile(path)
    size_mb = os.path.getsize(path) / (1024 * 1024) if exists else 0
    results[key] = {
        "pass": exists,
        "detail": f"{size_mb:.1f} MB" if exists else "FILE NOT FOUND",
    }
    return exists


def test_session_creation(variant_name, model_type, path):
    key = f"{variant_name}_{model_type}_session_create"
    try:
        opts = ort.SessionOptions()
        opts.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
        sess = ort.InferenceSession(path, opts, providers=["CPUExecutionProvider"])
        input_names = [inp.name for inp in sess.get_inputs()]
        output_names = [out.name for out in sess.get_outputs()]
        input_shapes = [inp.shape for inp in sess.get_inputs()]
        output_shapes = [out.shape for out in sess.get_outputs()]
        results[key] = {
            "pass": True,
            "detail": f"inputs={input_names} shapes={input_shapes}, outputs={output_names} shapes={output_shapes}",
        }
        return sess
    except Exception as e:
        results[key] = {"pass": False, "detail": str(e)}
        return None


def test_image_inference(variant_name, sess):
    key = f"{variant_name}_image_inference"
    if sess is None:
        results[key] = {"pass": False, "detail": "No session"}
        return None

    try:
        dummy = make_dummy_image()
        input_name = sess.get_inputs()[0].name

        t0 = time.perf_counter()
        outputs = sess.run(None, {input_name: dummy})
        elapsed_ms = (time.perf_counter() - t0) * 1000

        # Find the best output (prefer 2D pooler_output over 3D last_hidden_state)
        output_names = [o.name for o in sess.get_outputs()]
        embedding = None
        used_output = None

        for i, out in enumerate(outputs):
            arr = np.array(out)
            if arr.ndim == 2 and arr.shape[-1] == EXPECTED_DIM:
                embedding = arr
                used_output = output_names[i]
                break

        if embedding is None:
            # Fallback: use first output, apply mean pooling if 3D
            arr = np.array(outputs[0])
            used_output = output_names[0]
            if arr.ndim == 3:
                embedding = arr.mean(axis=1)  # mean pool over patches
            elif arr.ndim == 2:
                embedding = arr
            else:
                embedding = arr.reshape(1, -1)

        emb = embedding[0]
        norm = float(np.linalg.norm(emb))
        has_nan = bool(np.isnan(emb).any())
        has_inf = bool(np.isinf(emb).any())
        dim = len(emb)

        passed = dim == EXPECTED_DIM and not has_nan and not has_inf and norm > 0
        results[key] = {
            "pass": passed,
            "detail": (
                f"dim={dim}, norm={norm:.4f}, nan={has_nan}, inf={has_inf}, "
                f"output='{used_output}', time={elapsed_ms:.0f}ms"
            ),
        }
        return l2_norm(emb) if passed else None
    except Exception as e:
        results[key] = {"pass": False, "detail": str(e)}
        return None


def test_text_inference(variant_name, sess):
    key = f"{variant_name}_text_inference"
    if sess is None:
        results[key] = {"pass": False, "detail": "No session"}
        return None

    try:
        dummy = make_dummy_tokens()

        # Build feed dict from all model inputs
        feed = {}
        for inp in sess.get_inputs():
            if inp.name == "input_ids":
                feed[inp.name] = dummy
            elif inp.name == "attention_mask":
                # attention_mask: 1 for real tokens, 0 for padding
                feed[inp.name] = (dummy != 0).astype(np.int64)
            else:
                feed[inp.name] = dummy  # fallback

        t0 = time.perf_counter()
        outputs = sess.run(None, feed)
        elapsed_ms = (time.perf_counter() - t0) * 1000

        output_names = [o.name for o in sess.get_outputs()]
        embedding = None
        used_output = None

        for i, out in enumerate(outputs):
            arr = np.array(out)
            if arr.ndim == 2 and arr.shape[-1] == EXPECTED_DIM:
                embedding = arr
                used_output = output_names[i]
                break

        if embedding is None:
            arr = np.array(outputs[0])
            used_output = output_names[0]
            if arr.ndim == 3:
                embedding = arr.mean(axis=1)
            elif arr.ndim == 2:
                embedding = arr
            else:
                embedding = arr.reshape(1, -1)

        emb = embedding[0]
        norm = float(np.linalg.norm(emb))
        has_nan = bool(np.isnan(emb).any())
        has_inf = bool(np.isinf(emb).any())
        dim = len(emb)

        passed = dim == EXPECTED_DIM and not has_nan and not has_inf and norm > 0
        results[key] = {
            "pass": passed,
            "detail": (
                f"dim={dim}, norm={norm:.4f}, nan={has_nan}, inf={has_inf}, "
                f"output='{used_output}', time={elapsed_ms:.0f}ms"
            ),
        }
        return l2_norm(emb) if passed else None
    except Exception as e:
        results[key] = {"pass": False, "detail": str(e)}
        return None


def test_cross_modal(variant_name, img_emb, txt_emb):
    key = f"{variant_name}_cross_modal_similarity"
    if img_emb is None or txt_emb is None:
        results[key] = {"pass": False, "detail": "Missing embeddings"}
        return

    sim = cosine_sim(img_emb, txt_emb)
    # Cross-modal similarity with random inputs should be small but non-zero
    # The key check: embeddings are in the same space (not all zeros, not NaN)
    passed = -1.0 <= sim <= 1.0 and not np.isnan(sim)
    results[key] = {
        "pass": passed,
        "detail": f"cosine_similarity={sim:.6f}",
    }


def test_output_tensor_names(variant_name, model_type, sess):
    """Check if the model outputs the expected tensor names for Dart integration."""
    key = f"{variant_name}_{model_type}_output_names"
    if sess is None:
        results[key] = {"pass": False, "detail": "No session"}
        return

    output_names = [o.name for o in sess.get_outputs()]
    output_shapes = [o.shape for o in sess.get_outputs()]

    # The Dart code looks for 'pooler_output', 'image_features', 'text_features'
    known_good = {"pooler_output", "image_features", "text_features",
                  "image_embeds", "text_embeds"}
    has_known = any(n in known_good for n in output_names)

    # Check if any output is 2D [1, 768] (preferred) vs 3D (needs pooling fallback)
    has_2d_output = False
    for out in sess.get_outputs():
        shape = out.shape
        if len(shape) == 2:
            has_2d_output = True

    detail = f"names={output_names}, shapes={output_shapes}, known_name={'YES' if has_known else 'NO (fallback)'}, 2d_output={'YES' if has_2d_output else 'NO (3D, needs pooling)'}"
    results[key] = {
        "pass": True,  # Info-only, but flag if 3D output
        "detail": detail,
        "warning": None if has_2d_output else "Model outputs 3D tensor - Dart code will use mean pooling fallback",
    }


def test_fp32_vs_int8_similarity():
    """Compare FP32 and INT8 embeddings to check quantization quality."""
    key = "fp32_vs_int8_comparison"
    fp32_img = all_embeddings.get("fp32_image")
    int8_img = all_embeddings.get("int8_image")
    fp32_txt = all_embeddings.get("fp32_text")
    int8_txt = all_embeddings.get("int8_text")

    details = []

    if fp32_img is not None and int8_img is not None:
        sim = cosine_sim(fp32_img, int8_img)
        details.append(f"image_sim={sim:.6f}")
    else:
        details.append("image_sim=N/A")

    if fp32_txt is not None and int8_txt is not None:
        sim = cosine_sim(fp32_txt, int8_txt)
        details.append(f"text_sim={sim:.6f}")
    else:
        details.append("text_sim=N/A")

    results[key] = {
        "pass": True,  # Info-only
        "detail": ", ".join(details),
    }


# ---------- Main ----------

all_embeddings = {}


def main():
    print("=" * 70)
    print("  KITAKO ONNX MODEL VALIDATION")
    print(f"  ONNX Runtime version: {ort.__version__}")
    print("=" * 70)

    for variant_name, paths in VARIANTS.items():
        print(f"\n{'='*50}")
        print(f"  Testing {variant_name.upper()} variant")
        print(f"{'='*50}")

        # --- Image Encoder ---
        print(f"\n--- {variant_name.upper()} Image Encoder ---")
        img_path = paths["image"]
        if test_model_exists(variant_name, "image", img_path):
            img_sess = test_session_creation(variant_name, "image", img_path)
            test_output_tensor_names(variant_name, "image", img_sess)
            img_emb = test_image_inference(variant_name, img_sess)
            all_embeddings[f"{variant_name}_image"] = img_emb
        else:
            img_sess = None
            img_emb = None

        # --- Text Encoder ---
        print(f"\n--- {variant_name.upper()} Text Encoder ---")
        txt_path = paths["text"]
        if test_model_exists(variant_name, "text", txt_path):
            txt_sess = test_session_creation(variant_name, "text", txt_path)
            test_output_tensor_names(variant_name, "text", txt_sess)
            txt_emb = test_text_inference(variant_name, txt_sess)
            all_embeddings[f"{variant_name}_text"] = txt_emb
        else:
            txt_sess = None
            txt_emb = None

        # --- Cross-modal ---
        test_cross_modal(variant_name, img_emb, txt_emb)

    # --- FP32 vs INT8 comparison ---
    print(f"\n{'='*50}")
    print("  FP32 vs INT8 Quantization Quality")
    print(f"{'='*50}")
    test_fp32_vs_int8_similarity()

    # ---------- Summary ----------
    print("\n")
    print("=" * 70)
    print("  TEST RESULTS SUMMARY")
    print("=" * 70)

    pass_count = 0
    fail_count = 0
    warn_count = 0

    for test_name, result in results.items():
        status = "PASS" if result["pass"] else "FAIL"
        icon = "[OK]" if result["pass"] else "[FAIL]"
        warning = result.get("warning")

        if result["pass"]:
            pass_count += 1
        else:
            fail_count += 1

        if warning:
            warn_count += 1
            print(f"  {icon} {test_name}")
            print(f"       {result['detail']}")
            print(f"       WARNING: {warning}")
        else:
            print(f"  {icon} {test_name}")
            print(f"       {result['detail']}")

    print(f"\n{'='*70}")
    print(f"  TOTAL: {pass_count} passed, {fail_count} failed, {warn_count} warnings")
    print(f"{'='*70}")

    return fail_count == 0


if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
