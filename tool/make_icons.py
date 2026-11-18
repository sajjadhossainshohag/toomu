"""Regenerates every Toomu app icon from the mark below.

Run: python tool/make_icons.py   (needs Pillow and Google Chrome or Edge)
"""
import os
import pathlib
import subprocess
import tempfile

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
BRAND = ROOT / "branding"
RES = ROOT / "android/app/src/main/res"
WIN_ICO = ROOT / "windows/runner/resources/app_icon.ico"

# Aurora Monogram: a lowercase t whose crossbar is a play arrow, white on a violet/pink/cyan aurora.
# Drawn on a 100-unit icon; the adaptive layers use a 150-unit canvas around it (108dp shown as 72dp).
STEM = "M40 29 Q40 22 47 22 Q54 22 54 29 V61 Q54 67 60 67 H63 Q69.5 67 69.5 73.5 Q69.5 80 63 80 H57 Q40 80 40 63 Z"
BAR = ("M27 42 Q27 36 33 36 H58 V32.5 Q58 28.5 61.4 30.7 L72.5 38.6 Q76 41.5 72.5 44.4 "
       "L61.4 52.3 Q58 54.5 58 50.5 V48 H33 Q27 48 27 42 Z")
TEARDROP = "M50 0 A50 50 0 0 0 0 50 A50 50 0 0 0 50 100 H86 A14 14 0 0 0 100 86 V50 A50 50 0 0 0 50 0 Z"
GLOWS = (("16", "16", "40", "#7C4DFF", "1"), ("90", "28", "30", "#FF4FC3", ".85"),
         ("72", "96", "38", "#2FD0FF", ".7"), ("8", "92", "24", "#4B2BD9", "1"))

DEFS = """
<linearGradient id="stem" gradientUnits="userSpaceOnUse" x1="0" y1="22" x2="0" y2="80">
  <stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#E2D5FF"/>
</linearGradient>
<radialGradient id="gloss" gradientUnits="userSpaceOnUse" cx="18" cy="8" r="95">
  <stop offset="0" stop-color="#fff" stop-opacity=".30"/><stop offset=".6" stop-color="#fff" stop-opacity="0"/>
</radialGradient>
<filter id="blur" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="10"/></filter>
<filter id="sh" x="-30%" y="-30%" width="160%" height="170%">
  <feDropShadow dx="0" dy="2.4" stdDeviation="2.6" flood-color="#1B0866" flood-opacity="0.42"/>
</filter>
<clipPath id="tear"><path d="TEARDROP"/></clipPath>""".replace("TEARDROP", TEARDROP)

AURORA = ('<rect x="-25" y="-25" width="150" height="150" fill="#170C40"/><g filter="url(#blur)">'
          + "".join(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{c}" opacity="{o}"/>' for x, y, r, c, o in GLOWS)
          + '</g><rect x="-25" y="-25" width="150" height="150" fill="url(#gloss)"/>')
GLYPH = f'<g filter="url(#sh)"><path d="{STEM}" fill="url(#stem)"/><path d="{BAR}" fill="#fff"/></g>'


def svg(body, view="0 0 100 100"):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="{view}">'
            f'<defs>{DEFS}</defs>{body}</svg>')


def icon_svg(teardrop):
    return svg(f'<g clip-path="url(#tear)">{AURORA}{GLYPH}</g>' if teardrop else AURORA + GLYPH)


def mark_svg(color):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><path d="{STEM} {BAR}" fill="{color}"/></svg>'


def browser():
    for p in (r"C:\Program Files\Google\Chrome\Application\chrome.exe",
              r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
              "/usr/bin/google-chrome", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"):
        if os.path.exists(p):
            return p
    raise SystemExit("Chrome or Edge not found")


def render(svg_text, out):
    with tempfile.TemporaryDirectory() as tmp:
        src = pathlib.Path(tmp) / "icon.svg"
        src.write_text(svg_text, encoding="utf-8")
        subprocess.run([browser(), "--headless", "--disable-gpu", "--hide-scrollbars",
                        f"--user-data-dir={tmp}", "--window-size=1024,1024",
                        "--default-background-color=00000000", f"--screenshot={out}",
                        src.as_uri()], check=True, capture_output=True)
    return Image.open(out).convert("RGBA").crop((0, 0, 1024, 1024))


def adaptive_layers():
    # Vector drawables can't blur, so the aurora and the glyph's shadow ship as bitmaps.
    with tempfile.TemporaryDirectory() as tmp:
        layers = {name: render(svg(body, "-25 -25 150 150"), pathlib.Path(tmp) / f"{name}.png")
                  for name, body in {"background": AURORA, "foreground": GLYPH}.items()}
    for folder, px in {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}.items():
        for name, img in layers.items():
            img.resize((px, px), Image.LANCZOS).save(RES / f"mipmap-{folder}/ic_launcher_{name}.png")

    # Monochrome is drawn by alpha only.
    (RES / "drawable/ic_launcher_monochrome.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
        '    android:width="108dp" android:height="108dp"\n    android:viewportWidth="150" android:viewportHeight="150">\n'
        '  <group android:translateX="25" android:translateY="25">\n'
        f'    <path android:fillColor="#FFFFFFFF" android:pathData="{STEM} {BAR}"/>\n  </group>\n</vector>\n',
        encoding="utf-8")

    # Status bar icon: the glyph alone, filling the 20dp live area of the 24dp box.
    (RES / "drawable/ic_stat_toomu.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
        '    android:width="24dp" android:height="24dp"\n    android:viewportWidth="70" android:viewportHeight="70">\n'
        '  <group android:translateX="-16.5" android:translateY="-16">\n'
        f'    <path android:fillColor="#FFFFFFFF" android:pathData="{STEM} {BAR}"/>\n  </group>\n</vector>\n',
        encoding="utf-8")


def main():
    for name, text in {"toomu_logo.svg": icon_svg(True), "toomu_logo_square.svg": icon_svg(False),
                       "toomu_mark.svg": mark_svg("#7C4DFF"), "toomu_mark_white.svg": mark_svg("#fff")}.items():
        (BRAND / name).write_text(text, encoding="utf-8")

    teardrop = render(icon_svg(True), BRAND / "toomu_logo_1024.png")
    # Full square for the Play listing: Play applies its own mask.
    square = render(icon_svg(False), BRAND / "toomu_logo_square_1024.png")
    teardrop.save(BRAND / "toomu_logo_1024.png")
    square.convert("RGB").save(BRAND / "toomu_logo_square_1024.png")

    for folder, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        teardrop.resize((px, px), Image.LANCZOS).save(RES / f"mipmap-{folder}/ic_launcher.png")
        # Android 7-11 launch screen; 12+ shows the launcher icon instead.
        teardrop.resize((px * 7 // 3, px * 7 // 3), Image.LANCZOS).save(RES / f"mipmap-{folder}/splash_logo.png")

    # Windows: taskbar, title bar and Explorer pick the size they need.
    teardrop.save(WIN_ICO, sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])

    adaptive_layers()


if __name__ == "__main__":
    main()
