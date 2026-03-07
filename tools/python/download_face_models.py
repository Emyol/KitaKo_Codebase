"""
Download SCRFD face detector and ArcFace face embedder ONNX models
for KitaKo face recognition feature.

Models:
- SCRFD-2.5G (face detection, ~3MB)
- ArcFace w600k_mbf (face embedding, ~12MB)

Uses huggingface_hub to download from InsightFace model repos.
"""

import os
import sys
from pathlib import Path

def download_models():
    output_dir = Path(__file__).parent.parent.parent / "assets" / "face_models"
    output_dir.mkdir(parents=True, exist_ok=True)

    detector_path = output_dir / "face_detector.onnx"
    embedder_path = output_dir / "face_embedder.onnx"

    print(f"Output directory: {output_dir}")

    # Try huggingface_hub first
    try:
        from huggingface_hub import hf_hub_download
        print("Using huggingface_hub for downloads...")

        # Download SCRFD-2.5G detector
        if not detector_path.exists():
            print("Downloading SCRFD-2.5G face detector...")
            downloaded = hf_hub_download(
                repo_id="onnx-community/scrfd_2.5g_bnkps",
                filename="onnx/model.onnx",
                local_dir=str(output_dir / "_tmp_detector"),
            )
            # Copy to our target path
            import shutil
            shutil.copy2(downloaded, str(detector_path))
            shutil.rmtree(str(output_dir / "_tmp_detector"), ignore_errors=True)
            print(f"  -> Saved: {detector_path} ({detector_path.stat().st_size / 1024 / 1024:.1f} MB)")
        else:
            print(f"  Detector already exists: {detector_path}")

        # Download ArcFace w600k_mbf embedder
        if not embedder_path.exists():
            print("Downloading ArcFace w600k_mbf face embedder...")
            downloaded = hf_hub_download(
                repo_id="onnx-community/arcface_w600k_mbf",
                filename="onnx/model.onnx",
                local_dir=str(output_dir / "_tmp_embedder"),
            )
            import shutil
            shutil.copy2(downloaded, str(embedder_path))
            shutil.rmtree(str(output_dir / "_tmp_embedder"), ignore_errors=True)
            print(f"  -> Saved: {embedder_path} ({embedder_path.stat().st_size / 1024 / 1024:.1f} MB)")
        else:
            print(f"  Embedder already exists: {embedder_path}")

        print("\nDone! Models saved to:", output_dir)
        return True

    except ImportError:
        print("huggingface_hub not available, trying urllib...")
    except Exception as e:
        print(f"huggingface_hub download failed: {e}")
        print("Trying alternative download method...")

    # Fallback: direct URL download
    try:
        import urllib.request
        import ssl

        # Create unverified context as fallback
        ctx = ssl.create_default_context()

        # SCRFD from HF direct URL
        if not detector_path.exists():
            print("Downloading SCRFD-2.5G via direct URL...")
            url = "https://huggingface.co/onnx-community/scrfd_2.5g_bnkps/resolve/main/onnx/model.onnx"
            urllib.request.urlretrieve(url, str(detector_path))
            print(f"  -> Saved: {detector_path} ({detector_path.stat().st_size / 1024 / 1024:.1f} MB)")

        if not embedder_path.exists():
            print("Downloading ArcFace w600k_mbf via direct URL...")
            url = "https://huggingface.co/onnx-community/arcface_w600k_mbf/resolve/main/onnx/model.onnx"
            urllib.request.urlretrieve(url, str(embedder_path))
            print(f"  -> Saved: {embedder_path} ({embedder_path.stat().st_size / 1024 / 1024:.1f} MB)")

        print("\nDone! Models saved to:", output_dir)
        return True

    except Exception as e:
        print(f"Download failed: {e}")
        print("\nManual download instructions:")
        print(f"  1. Download SCRFD: https://huggingface.co/onnx-community/scrfd_2.5g_bnkps/resolve/main/onnx/model.onnx")
        print(f"     Save as: {detector_path}")
        print(f"  2. Download ArcFace: https://huggingface.co/onnx-community/arcface_w600k_mbf/resolve/main/onnx/model.onnx")
        print(f"     Save as: {embedder_path}")
        return False


if __name__ == "__main__":
    success = download_models()
    sys.exit(0 if success else 1)
