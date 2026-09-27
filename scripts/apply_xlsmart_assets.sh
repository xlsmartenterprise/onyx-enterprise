#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
if ! command -v python3 >/dev/null 2>&1; then
  echo "Python 3 is required to apply XLSMART assets" >&2
  exit 1
fi

python3 - <<'PY'
import json
import shutil
from pathlib import Path
from urllib.parse import quote

try:
    from PIL import Image
except ImportError as exc:
    raise SystemExit("Pillow is required to apply XLSMART assets") from exc

root = Path.cwd()
source = root / ".assets/xlsmart-logo/FA LOGO (RGB)"
mark = source / "Logogram/72ppi/Logogram XLSMART - Primary Color.png"
white_mark = source / "Logogram/72ppi/Logogram XLSMART - Tertiary Color White.png"
light_lockup = source / "Primary Logo Configuration/72ppi/Logogram XLSMART - Primary.png"
dark_lockup = source / "Primary Logo Configuration/72ppi/Logogram XLSMART - Primary_1.png"
vector = source / "Logogram/SVG/Logogram XLSMART - Primary Color.svg"


def artwork(path: Path, square: bool = False) -> Image.Image:
    with Image.open(path) as original:
        image = original.convert("RGBA")
    bounds = image.getchannel("A").getbbox()
    if bounds is None:
        raise ValueError(f"Empty logo source: {path}")
    left, top, right, bottom = bounds
    pad = round(min(right - left, bottom - top) * 0.06)
    image = image.crop((
        max(0, left - pad),
        max(0, top - pad),
        min(image.width, right + pad),
        min(image.height, bottom + pad),
    ))
    if square:
        side = max(image.size)
        canvas = Image.new("RGBA", (side, side))
        canvas.paste(image, ((side - image.width) // 2, (side - image.height) // 2))
        return canvas
    return image


def png(image: Image.Image, path: str, width: int) -> None:
    target = root / path
    target.parent.mkdir(parents=True, exist_ok=True)
    height = round(image.height * width / image.width)
    image.resize((width, height), Image.Resampling.LANCZOS).save(
        target, format="PNG", optimize=True
    )


color = artwork(mark, square=True)
white = artwork(white_mark, square=True)
light_wordmark = artwork(light_lockup)
dark_wordmark = artwork(dark_lockup)

for path in ("web/public/logo.png", "backend/static/images/logo.png"):
    png(color, path, 256)
png(white, "web/public/logo-dark.png", 256)
for path in ("web/public/logotype.png", "backend/static/images/logotype.png"):
    png(light_wordmark, path, 560)
png(dark_wordmark, "web/public/logotype-dark.png", 560)
png(color, "widget/public/logo.png", 128)
png(color, "extensions/chrome/public/logo.png", 128)
for size in (16, 32, 48, 128):
    png(color, f"extensions/chrome/public/icon{size}.png", size)

icon = color.resize((256, 256), Image.Resampling.LANCZOS)
icon.save(
    root / "web/public/favicon.ico",
    format="ICO",
    sizes=[(size, size) for size in (16, 32, 48, 64, 128, 256)],
)
(root / "web/public/onyx.ico").unlink(missing_ok=True)
shutil.copyfile(vector, root / "web/public/logo.svg")
svg = vector.read_text(encoding="utf-8")
data_url = "data:image/svg+xml," + quote(svg, safe="")
(root / "widget/src/assets/logo.ts").write_text(
    "// Bundled XLSMART logo for widgets without a custom logo.\n"
    f"export const DEFAULT_LOGO = {json.dumps(data_url)};\n",
    encoding="utf-8",
)
PY
