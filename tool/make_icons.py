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
IOS = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"

# Progress ring around a faceted play triangle with a download arrow on it.
RING = "M512 222 A290 290 0 1 1 512 802 A290 290 0 1 1 512 222 Z"
ARC = "M512 222 A290 290 0 1 1 222 512"
RING_W = 54
TRI = "M358 336 Q358 276 412 303 L744 470 Q798 497 744 524 L412 691 Q358 718 358 658 Z"
ARROW = ("M464 432 A30 30 0 0 1 524 432 L524 500 L560 500 Q584 500 568 518 L510 580 "
         "Q494 597 478 580 L420 518 Q404 500 428 500 L464 500 Z")
FACETS = (("M358 276 L494 497 L798 497 Z", "#A78BFF"),
          ("M358 276 L358 718 L494 497 Z", "#7C4DFF"),
          ("M358 718 L798 497 L494 497 Z", "#5B2BE0"))
FACET_ROUND = 40
# Maps the play mark (drawn around 525,497) into the ring's centre.
PLAY_SCALE, PLAY_PIVOT, PLAY_SHIFT = 0.66, (525, 497), (-13, 15)

# App primary gradient: ColorConstants.gradientEnd -> primary -> gradientStart.
BRAND_STOPS = (("0", "B69CFF"), ("0.5", "7C4DFF"), ("1", "5B2BE0"))
SVG_STOPS = "".join(f'<stop offset="{o}" stop-color="#{c}"/>' for o, c in BRAND_STOPS)
PLAY_TRANSFORM = (f"translate({PLAY_PIVOT[0] + PLAY_SHIFT[0]} {PLAY_PIVOT[1] + PLAY_SHIFT[1]}) "
                  f"scale({PLAY_SCALE}) translate({-PLAY_PIVOT[0]} {-PLAY_PIVOT[1]})")

DEFS = f"""
<linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
  <stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#EEE7FF"/>
</linearGradient>
<linearGradient id="brand" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="1024" y2="1024">{SVG_STOPS}</linearGradient>
<filter id="sh" x="-30%" y="-30%" width="160%" height="170%">
  <feDropShadow dx="0" dy="18" stdDeviation="22" flood-color="#2A0E8A" flood-opacity="0.35"/>
</filter>"""


def ring_svg(stroke, track_opacity):
    return (f'<path d="{RING}" fill="none" stroke="{stroke}" stroke-opacity="{track_opacity}" stroke-width="{RING_W}"/>'
            f'<path d="{ARC}" fill="none" stroke="{stroke}" stroke-width="{RING_W}" stroke-linecap="round"/>')


def icon_svg(rx):
    facets = "".join(f'<path d="{d}" fill="{c}" stroke="{c}" stroke-width="{FACET_ROUND}" stroke-linejoin="round"/>'
                     for d, c in FACETS)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
            f'<defs>{DEFS}</defs><rect width="1024" height="1024" rx="{rx}" fill="url(#bg)"/>'
            f'<g filter="url(#sh)">{ring_svg("url(#brand)", 0.18)}'
            f'<g transform="{PLAY_TRANSFORM}">{facets}<path d="{ARROW}" fill="#fff"/></g></g></svg>')


def mark_svg(color):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">{ring_svg(color, 0.25)}'
            f'<path d="{TRI} {ARROW}" fill="{color}" fill-rule="evenodd" transform="{PLAY_TRANSFORM}"/></svg>')


def browser():
    for p in (r"C:\Program Files\Google\Chrome\Application\chrome.exe",
              r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
              "/usr/bin/google-chrome", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"):
        if os.path.exists(p):
            return p
    raise SystemExit("Chrome or Edge not found")


def render(svg, out):
    with tempfile.TemporaryDirectory() as tmp:
        src = pathlib.Path(tmp) / "icon.svg"
        src.write_text(svg, encoding="utf-8")
        subprocess.run([browser(), "--headless", "--disable-gpu", "--hide-scrollbars",
                        f"--user-data-dir={tmp}", "--window-size=1024,1024",
                        "--default-background-color=00000000", f"--screenshot={out}",
                        src.as_uri()], check=True, capture_output=True)
    return Image.open(out).convert("RGBA").crop((0, 0, 1024, 1024))


def android_vectors():
    head = ('<?xml version="1.0" encoding="utf-8"?>\n<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
            '    xmlns:aapt="http://schemas.android.com/aapt"\n    android:width="108dp" android:height="108dp"\n'
            '    android:viewportWidth="1024" android:viewportHeight="1024">\n')
    brand = ('<aapt:attr name="android:strokeColor"><gradient android:type="linear" android:startX="0" android:startY="0" '
             'android:endX="1024" android:endY="1024">'
             + "".join(f'<item android:offset="{o}" android:color="#FF{c}"/>' for o, c in BRAND_STOPS)
             + '</gradient></aapt:attr>')
    play_group = (f'    <group android:pivotX="{PLAY_PIVOT[0]}" android:pivotY="{PLAY_PIVOT[1]}" '
                  f'android:scaleX="{PLAY_SCALE}" android:scaleY="{PLAY_SCALE}" '
                  f'android:translateX="{PLAY_SHIFT[0]}" android:translateY="{PLAY_SHIFT[1]}">\n')

    def ring(track, arc):
        return (f'    <path android:pathData="{RING}" android:strokeWidth="{RING_W}" {track}</path>\n'
                f'    <path android:pathData="{ARC}" android:strokeWidth="{RING_W}" android:strokeLineCap="round" {arc}</path>\n')

    # Adaptive icon masks clip to the central 66dp of 108dp, so the mark is shrunk to stay inside it.
    open_fg = '  <group android:pivotX="512" android:pivotY="512" android:scaleX="0.72" android:scaleY="0.72">\n'

    bg = (head + '  <path android:pathData="M0,0h1024v1024h-1024z"><aapt:attr name="android:fillColor">'
          '<gradient android:type="linear" android:startX="0" android:startY="0" android:endX="1024" android:endY="1024">'
          '<item android:offset="0" android:color="#FFFFFFFF"/><item android:offset="1" android:color="#FFEEE7FF"/>'
          '</gradient></aapt:attr></path>\n</vector>\n')
    fg = (head + open_fg + ring(f'android:strokeAlpha="0.18">{brand}', f'>{brand}') + play_group
          + "".join(f'      <path android:pathData="{d}" android:fillColor="{c}" android:strokeColor="{c}" '
                    f'android:strokeWidth="{FACET_ROUND}" android:strokeLineJoin="round"/>\n' for d, c in FACETS)
          + f'      <path android:pathData="{ARROW}" android:fillColor="#FFFFFFFF"/>\n    </group>\n  </group>\n</vector>\n')
    # Monochrome is drawn by alpha only, so the arrow must be a real hole in the triangle.
    mono = (head + open_fg + ring('android:strokeColor="#FFFFFFFF" android:strokeAlpha="0.3">',
                                  'android:strokeColor="#FFFFFFFF">') + play_group
            + f'      <path android:fillType="evenOdd" android:fillColor="#FFFFFFFF" android:pathData="{TRI} {ARROW}"/>\n'
            + '    </group>\n  </group>\n</vector>\n')
    for name, xml in {"background": bg, "foreground": fg, "monochrome": mono}.items():
        (RES / f"drawable/ic_launcher_{name}.xml").write_text(xml, encoding="utf-8")


def main():
    for name, svg in {"toomu_logo.svg": icon_svg(230), "toomu_logo_square.svg": icon_svg(0),
                      "toomu_mark.svg": mark_svg("#7C4DFF"), "toomu_mark_white.svg": mark_svg("#fff")}.items():
        (BRAND / name).write_text(svg, encoding="utf-8")

    rounded = render(icon_svg(230), BRAND / "toomu_logo_1024.png")
    square = render(icon_svg(0), BRAND / "toomu_logo_square_1024.png")
    rounded.save(BRAND / "toomu_logo_1024.png")
    square.convert("RGB").save(BRAND / "toomu_logo_square_1024.png")

    for folder, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        rounded.resize((px, px), Image.LANCZOS).save(RES / f"mipmap-{folder}/ic_launcher.png")

    # App Store rejects icons with an alpha channel; iOS applies its own corner mask.
    for f in IOS.glob("Icon-App-*.png"):
        pt, scale = f.stem.removeprefix("Icon-App-").split("@")
        px = round(float(pt.split("x")[0]) * int(scale.rstrip("x")))
        square.convert("RGB").resize((px, px), Image.LANCZOS).save(f)

    android_vectors()


if __name__ == "__main__":
    main()
