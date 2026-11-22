"""Build the KitaKo user manual: inject photo credits, then print to PDF.

Usage:  python docs/user-manual/build.py [--html-only]
Outputs: KitaKo_User_Manual.html and KitaKo_User_Manual.pdf next to this file.
"""
import html, json, re, subprocess, pathlib, shutil

here = pathlib.Path(__file__).resolve().parent
src = (here / "manual.src.html").read_text(encoding="utf-8")
credits = json.loads((here / "assets/photos/_credits.json").read_text(encoding="utf-8"))
rows = []
for c in sorted(credits, key=lambda c: c["file"]):
    raw = c.get("artist", "") or ""
    text = re.sub(r"<[^>]*>?", " ", raw).strip()
    if not text or "=" in text or "href" in raw and not re.search(r">[^<]+<", raw):
        m = re.search(r"User:([^&\"/ ]+)", raw)
        text = m.group(1).replace("_", " ") if m else "Wikimedia Commons contributor"
    if text.endswith(":"):
        m = re.search(r"User:([^&\"/ ]+)", raw)
        if m: text += " " + m.group(1).replace("_", " ")
    artist = html.escape(re.sub(r"\s+", " ", text))
    title = html.escape(c.get("title", "").replace("File:", ""))
    rows.append(f'<div><b>{c["file"]}</b> · {title} · {artist} · {html.escape(c.get("license",""))}</div>')
out = here / "KitaKo_User_Manual.html"
out.write_text(src.replace("<!--CREDITS-->", "\n".join(rows)), encoding="utf-8")

chrome = next(p for p in [
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    shutil.which("chromium") or "", shutil.which("google-chrome") or "",
] if p and pathlib.Path(p).exists())
import os, sys, tempfile, time
if "--html-only" in sys.argv:
    print("wrote", out.name); raise SystemExit

tmp = pathlib.Path(tempfile.gettempdir()) / f"kitako_manual_{int(time.time())}.pdf"
with tempfile.TemporaryDirectory(prefix="kk_chrome_", ignore_cleanup_errors=True) as profile:
    subprocess.run([chrome, "--headless=new", "--disable-gpu", "--no-pdf-header-footer",
                    f"--user-data-dir={profile}",
                    "--virtual-time-budget=8000", f"--print-to-pdf={tmp}",
                    out.as_uri()], check=True, capture_output=True)
if not tmp.exists() or tmp.stat().st_size < 10_000:
    raise SystemExit("PDF was not produced; is Chrome working?")
pdf = here / "KitaKo_User_Manual.pdf"
try:
    os.replace(tmp, pdf)
except PermissionError:
    raise SystemExit(f"{pdf.name} is open in another program; close it and rerun. Fresh copy: {tmp}")
print("wrote", out.name, "and", pdf.name)
