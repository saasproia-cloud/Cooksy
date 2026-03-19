#!/usr/bin/env python3

from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parent.parent
ASSETS_ROOT = ROOT / "Cooksy" / "Resources" / "Assets.xcassets"
SOURCE_ARTWORK = ROOT / "Cooksy" / "Resources" / "SourceArtwork"
APP_ICON_SET = ASSETS_ROOT / "AppIcon.appiconset"
HEADER_LOGO_SET = ASSETS_ROOT / "HeaderLogo.imageset"
APP_ICON_SOURCE = SOURCE_ARTWORK / "app-icon-source.png"
HEADER_LOGO_SOURCE = SOURCE_ARTWORK / "header-logo-source.png"
MASTER_SIZE = 1024


def load_rgba(path: Path) -> Image.Image:
    if not path.exists():
        raise FileNotFoundError(f"Missing source artwork: {path}")
    return Image.open(path).convert("RGBA")


def square_zoom(image: Image.Image, zoom: float, shift_x: float = 0.0, shift_y: float = 0.0) -> Image.Image:
    width, height = image.size
    crop_width = width / zoom
    crop_height = height / zoom
    center_x = width / 2 + width * shift_x
    center_y = height / 2 + height * shift_y
    left = max(0.0, min(width - crop_width, center_x - crop_width / 2))
    top = max(0.0, min(height - crop_height, center_y - crop_height / 2))
    box = (
        int(round(left)),
        int(round(top)),
        int(round(left + crop_width)),
        int(round(top + crop_height)),
    )
    return image.crop(box).resize((MASTER_SIZE, MASTER_SIZE), Image.Resampling.LANCZOS)


def alpha_bbox(image: Image.Image, threshold: int = 8):
    alpha = image.getchannel("A").point(lambda value: 255 if value > threshold else 0)
    return alpha.getbbox()


def expand_bbox(bbox, image_size, margin_ratio: float):
    left, top, right, bottom = bbox
    width, height = image_size
    margin = int(max(right - left, bottom - top) * margin_ratio)
    return (
        max(0, left - margin),
        max(0, top - margin),
        min(width, right + margin),
        min(height, bottom + margin),
    )


def crop_visual_logo(image: Image.Image, threshold: int = 42, margin_ratio: float = 0.05) -> Image.Image:
    bbox = alpha_bbox(image, threshold=threshold)
    if bbox is None:
        return image.copy()

    return image.crop(expand_bbox(bbox, image.size, margin_ratio=margin_ratio))


def vertical_gradient(size, top_color, bottom_color) -> Image.Image:
    gradient = Image.new("RGBA", (1, size[1]))
    pixels = []

    for y in range(size[1]):
        progress = y / max(1, size[1] - 1)
        pixels.append(
            tuple(
                int(round(top_color[index] + (bottom_color[index] - top_color[index]) * progress))
                for index in range(4)
            )
        )

    gradient.putdata(pixels)
    return gradient.resize(size, Image.Resampling.BICUBIC)


def add_blurred_ellipse(canvas: Image.Image, box, color, blur_radius: int):
    overlay = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    draw.ellipse(box, fill=color)
    canvas.alpha_composite(overlay.filter(ImageFilter.GaussianBlur(radius=blur_radius)))


def build_app_icon(header_logo_source: Image.Image) -> Image.Image:
    master = vertical_gradient(
        (MASTER_SIZE, MASTER_SIZE),
        top_color=(255, 141, 53, 255),
        bottom_color=(255, 123, 31, 255),
    )

    add_blurred_ellipse(master, (170, 170, 860, 860), (255, 212, 96, 185), 120)
    add_blurred_ellipse(master, (-120, 760, 360, 1180), (255, 102, 41, 170), 120)
    add_blurred_ellipse(master, (660, 760, 1140, 1180), (255, 166, 92, 150), 120)

    logo = crop_visual_logo(header_logo_source, threshold=44, margin_ratio=0.04)
    scale = min(540 / logo.width, 540 / logo.height)
    resized = logo.resize(
        (
            max(1, int(round(logo.width * scale))),
            max(1, int(round(logo.height * scale))),
        ),
        Image.Resampling.LANCZOS,
    )

    shadow = Image.new("RGBA", (MASTER_SIZE, MASTER_SIZE), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.ellipse((310, 705, 714, 785), fill=(178, 73, 17, 135))
    master.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(radius=28)))

    offset = (
        (MASTER_SIZE - resized.width) // 2,
        (MASTER_SIZE - resized.height) // 2 - 8,
    )
    master.alpha_composite(resized, offset)
    return master


def crop_header_logo(image: Image.Image) -> Image.Image:
    cropped = crop_visual_logo(image, threshold=42, margin_ratio=0.04)
    if cropped.width == 0 or cropped.height == 0:
        return Image.new("RGBA", (MASTER_SIZE, MASTER_SIZE), (0, 0, 0, 0))

    canvas = Image.new("RGBA", (MASTER_SIZE, MASTER_SIZE), (0, 0, 0, 0))

    scale = min((MASTER_SIZE * 0.94) / cropped.width, (MASTER_SIZE * 0.94) / cropped.height)
    target_size = (
        max(1, int(round(cropped.width * scale))),
        max(1, int(round(cropped.height * scale))),
    )
    resized = cropped.resize(target_size, Image.Resampling.LANCZOS)
    offset = (
        (MASTER_SIZE - resized.width) // 2,
        (MASTER_SIZE - resized.height) // 2,
    )
    canvas.alpha_composite(resized, offset)
    return canvas


def clear_generated_files(folder: Path):
    for png_path in folder.glob("*.png"):
        png_path.unlink()


def save_app_icons(master: Image.Image):
    specs = [
        ("icon-20@2x.png", 40),
        ("icon-20@3x.png", 60),
        ("icon-29@2x.png", 58),
        ("icon-29@3x.png", 87),
        ("icon-40@2x.png", 80),
        ("icon-40@3x.png", 120),
        ("icon-60@2x.png", 120),
        ("icon-60@3x.png", 180),
        ("icon-1024.png", 1024),
    ]
    for filename, size in specs:
        master.resize((size, size), Image.Resampling.LANCZOS).save(APP_ICON_SET / filename)


def save_header_logo(master: Image.Image):
    specs = [
        ("logo-header.png", 120),
        ("logo-header@2x.png", 240),
        ("logo-header@3x.png", 360),
    ]
    for filename, size in specs:
        master.resize((size, size), Image.Resampling.LANCZOS).save(HEADER_LOGO_SET / filename)


def main():
    APP_ICON_SET.mkdir(parents=True, exist_ok=True)
    HEADER_LOGO_SET.mkdir(parents=True, exist_ok=True)
    clear_generated_files(APP_ICON_SET)
    clear_generated_files(HEADER_LOGO_SET)

    header_logo_source = load_rgba(HEADER_LOGO_SOURCE)

    app_icon_master = build_app_icon(header_logo_source)
    header_logo_master = crop_header_logo(header_logo_source)

    save_app_icons(app_icon_master)
    save_header_logo(header_logo_master)

    print(f"Generated assets from {HEADER_LOGO_SOURCE.name}")


if __name__ == "__main__":
    main()
