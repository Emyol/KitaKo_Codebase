"""
mirror.py — Launch scrcpy to mirror a connected Android phone.

Requires:
  - scrcpy installed (via winget: winget install Genymobile.scrcpy)
  - ADB in PATH or ANDROID_HOME set
  - A device connected with USB debugging enabled
"""

import argparse
import shutil
import subprocess
import sys


def check_scrcpy(explicit: str | None) -> str:
    if explicit:
        return explicit
    path = shutil.which("scrcpy")
    if path is None:
        print("[ERROR] scrcpy not found in PATH.")
        print("  Install it with: winget install Genymobile.scrcpy")
        sys.exit(1)
    return path


def get_device():
    try:
        import adbutils
    except ImportError:
        print("[ERROR] adbutils not installed. Run setup.bat first.")
        sys.exit(1)

    client = adbutils.AdbClient()
    devices = client.device_list()

    if not devices:
        print("[ERROR] No Android device detected.")
        print("  Make sure USB debugging is enabled and the device is connected.")
        sys.exit(1)

    if len(devices) == 1:
        device = devices[0]
        info = device.prop.get("ro.product.model", "Unknown")
        print(f"  Device : {info} ({device.serial})")
        return device.serial

    # Multiple devices — let user pick
    print("Multiple devices found:")
    for i, d in enumerate(devices):
        info = d.prop.get("ro.product.model", "Unknown")
        print(f"  [{i}] {info} ({d.serial})")
    choice = input("Select device number: ").strip()
    return devices[int(choice)].serial


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--scrcpy", default=None, help="Path to scrcpy executable")
    args = parser.parse_args()

    scrcpy = check_scrcpy(args.scrcpy)
    serial = get_device()

    cmd = [
        scrcpy,
        "--serial", serial,
        "--window-title", "KitaKo — Phone Mirror",
        "--max-size", "1080",
        "--max-fps", "60",
        "--stay-awake",
        "--show-touches",
        "--window-x", "100",
        "--window-y", "50",
    ]

    print(f"\n  Launching mirror... (close the scrcpy window to stop)\n")
    subprocess.run(cmd)


if __name__ == "__main__":
    main()
