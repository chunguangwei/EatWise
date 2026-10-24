#!/usr/bin/env python3
import json
import re
import subprocess
import tempfile
from pathlib import Path

from PIL import Image

APP_DIR = Path(__file__).resolve().parents[1]
ROOT_DIR = APP_DIR.parent
SOURCE = ROOT_DIR / "docs/specs/assets/eatwise-app-icon.svg"
IOS_DIR = APP_DIR / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
RES_DIR = APP_DIR / "android/app/src/main/res"
CHROME = Path("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
RENDER_SIZE = 2048
FOREGROUND_SCALE = 0.76
LEGACY_SIZES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
ADAPTIVE_SIZES = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}


def render_svg(source: Path, output_dir: Path, size: int) -> Image.Image:
    if not CHROME.is_file():
        raise RuntimeError(f"Google Chrome is required to render the SVG: {CHROME}")
    render_source = output_dir / f"{source.stem}-render.svg"
    screenshot = output_dir / f"{source.stem}-render.png"
    svg = source.read_text(encoding="utf-8").replace(
        'width="1024" height="1024"',
        f'width="{RENDER_SIZE}" height="{RENDER_SIZE}"',
        1,
    )
    render_source.write_text(svg, encoding="utf-8")
    subprocess.run(
        [
            str(CHROME),
            "--headless=new",
            "--disable-gpu",
            "--disable-extensions",
            "--disable-background-networking",
            "--no-first-run",
            "--hide-scrollbars",
            "--log-level=3",
            f"--user-data-dir={output_dir / f'{source.stem}-profile'}",
            "--force-device-scale-factor=1",
            f"--window-size={RENDER_SIZE},{RENDER_SIZE}",
            "--default-background-color=00000000",
            f"--screenshot={screenshot}",
            render_source.as_uri(),
        ],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    with Image.open(screenshot) as rendered:
        if rendered.size != (RENDER_SIZE, RENDER_SIZE):
            raise ValueError(f"Unexpected SVG render size: {rendered.size}")
        return rendered.convert("RGBA").resize((size, size), Image.Resampling.LANCZOS)


def validate_safe_circle(image: Image.Image) -> None:
    width, height = image.size
    center_x, center_y = width / 2, height / 2
    radius = width * 66 / 216
    pixels = image.load()
    for y in range(height):
        for x in range(width):
            if pixels[x, y][3] <= 8:
                continue
            if (x + 0.5 - center_x) ** 2 + (y + 0.5 - center_y) ** 2 > radius**2:
                raise ValueError("Visible foreground pixels exceed the 66dp safe circle")


def centered(mark: Image.Image, size: int) -> Image.Image:
    layer = Image.new("RGBA", (size, size))
    mark_size = round(size * FOREGROUND_SCALE)
    resized = mark.resize((mark_size, mark_size), Image.Resampling.LANCZOS)
    offset = (size - mark_size) // 2
    layer.alpha_composite(resized, (offset, offset))
    validate_safe_circle(layer)
    return layer


def save_png(image: Image.Image, destination: Path) -> None:
    temporary = destination.with_suffix(".tmp.png")
    image.save(temporary, format="PNG", optimize=True)
    temporary.replace(destination)


def save_rgb(image: Image.Image, destination: Path) -> None:
    save_png(image.convert("RGB"), destination)


def main() -> None:
    svg = SOURCE.read_text(encoding="utf-8")
    background_svg, background_count = re.subn(
        r'  <g id="mark">.*?</g>\n', "", svg, count=1, flags=re.DOTALL
    )
    mark_svg, mark_count = re.subn(
        r'  <g id="background">.*?</g>\n', "", svg, count=1, flags=re.DOTALL
    )
    if background_count != 1 or mark_count != 1:
        raise ValueError("SVG must contain exactly one background group and one mark group")

    with tempfile.TemporaryDirectory(prefix="eatwise-icons-") as temp:
        temp_dir = Path(temp)
        background_source = temp_dir / "background.svg"
        mark_source = temp_dir / "mark.svg"
        background_source.write_text(background_svg, encoding="utf-8")
        mark_source.write_text(mark_svg, encoding="utf-8")
        full = render_svg(SOURCE, temp_dir, 1024)
        background = render_svg(background_source, temp_dir, 1024)
        mark = render_svg(mark_source, temp_dir, 1024)
        if mark.getpixel((0, 0))[3] != 0:
            raise ValueError("The adaptive foreground must have a transparent background")

        contents = json.loads((IOS_DIR / "Contents.json").read_text(encoding="utf-8"))
        for entry in contents["images"]:
            logical_size = float(entry["size"].split("x")[0])
            scale = int(entry["scale"].removesuffix("x"))
            expected_size = round(logical_size * scale)
            save_rgb(full.resize((expected_size, expected_size), Image.Resampling.LANCZOS), IOS_DIR / entry["filename"])

        for density, size in LEGACY_SIZES.items():
            save_rgb(full.resize((size, size), Image.Resampling.LANCZOS), RES_DIR / f"mipmap-{density}/ic_launcher.png")
        for density, size in ADAPTIVE_SIZES.items():
            directory = RES_DIR / f"mipmap-{density}"
            directory.mkdir(parents=True, exist_ok=True)
            save_rgb(background.resize((size, size), Image.Resampling.LANCZOS), directory / "ic_launcher_background.png")
            save_png(centered(mark, size), directory / "ic_launcher_foreground.png")

    print(f"Generated iOS and Android icons from {SOURCE.relative_to(ROOT_DIR)}")


if __name__ == "__main__":
    main()
