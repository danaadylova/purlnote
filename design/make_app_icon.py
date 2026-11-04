"""Draws the Purlnote app icon and writes every size iOS and Android need.

The icon is a marigold lowercase "p" in Bricolage Grotesque Bold on plum,
the colors from the app's theme. iOS and Android round the corners
themselves, so the master image is a full square with no transparency.

Run from the repository root:
    python3 design/make_app_icon.py path/to/BricolageGrotesque-Bold.ttf
"""

import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

PLUM = (0x3B, 0x1C, 0x34)
MARIGOLD = (0xE7, 0xA3, 0x3E)
MASTER_SIZE = 1024

ROOT = Path(__file__).resolve().parent.parent
IOS_ICONS = ROOT / "app/ios/Runner/Assets.xcassets/AppIcon.appiconset"
ANDROID_RES = ROOT / "app/android/app/src/main/res"
ANDROID_SIZES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}


def draw_master(font_path: str) -> Image.Image:
    icon = Image.new("RGB", (MASTER_SIZE, MASTER_SIZE), PLUM)
    draw = ImageDraw.Draw(icon)
    font = ImageFont.truetype(font_path, int(MASTER_SIZE * 0.78))

    # Center the letter's ink, not its text box, since "p" has a descender.
    left, top, right, bottom = draw.textbbox((0, 0), "p", font=font)
    x = (MASTER_SIZE - (right - left)) / 2 - left
    y = (MASTER_SIZE - (bottom - top)) / 2 - top
    draw.text((x, y), "p", font=font, fill=MARIGOLD)
    return icon


def write_ios(master: Image.Image) -> None:
    contents = json.loads((IOS_ICONS / "Contents.json").read_text())
    for image in contents["images"]:
        points = float(image["size"].split("x")[0])
        scale = int(image["scale"].rstrip("x"))
        pixels = round(points * scale)
        master.resize((pixels, pixels), Image.LANCZOS).save(IOS_ICONS / image["filename"])


def write_android(master: Image.Image) -> None:
    for density, pixels in ANDROID_SIZES.items():
        master.resize((pixels, pixels), Image.LANCZOS).save(ANDROID_RES / f"mipmap-{density}/ic_launcher.png")


if __name__ == "__main__":
    master = draw_master(sys.argv[1])
    master.save(ROOT / "design/app_icon_1024.png")
    write_ios(master)
    write_android(master)
    print("Icons written.")
