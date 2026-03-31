#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import re
import unicodedata
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
ASSET_CATALOG = ROOT / "Cooksy/Resources/Assets.xcassets"
MANIFEST_DATASET = ASSET_CATALOG / "IngredientIconManifest.dataset"
VENDOR_SOURCE = ROOT / "Resources/IngredientIconVendor"


PALETTE = {
    "shadow": (28, 22, 16, 18),
    "outline": (84, 59, 41, 230),
    "cream": (252, 246, 233, 255),
    "white": (255, 255, 255, 255),
    "gold": (238, 187, 88, 255),
    "amber": (228, 145, 66, 255),
    "orange": (224, 111, 63, 255),
    "tomato": (214, 88, 70, 255),
    "red": (184, 70, 70, 255),
    "pink": (221, 144, 160, 255),
    "berry": (160, 64, 96, 255),
    "green": (103, 150, 86, 255),
    "green_dark": (62, 111, 71, 255),
    "mint": (148, 190, 133, 255),
    "avocado": (135, 168, 79, 255),
    "brown": (154, 110, 72, 255),
    "brown_dark": (108, 74, 48, 255),
    "tan": (196, 161, 106, 255),
    "beige": (231, 213, 170, 255),
    "lemon": (244, 205, 91, 255),
    "lime": (163, 201, 88, 255),
    "blue": (124, 167, 202, 255),
    "blue_dark": (86, 125, 163, 255),
    "gray_blue": (150, 170, 195, 255),
    "gray": (189, 184, 175, 255),
    "black": (55, 54, 53, 255),
    "coconut": (121, 88, 70, 255),
}


def rgba(name: str) -> tuple[int, int, int, int]:
    return PALETTE[name]


@dataclass(frozen=True)
class ManifestEntry:
    canonical_key: str
    asset_name: str
    aliases: tuple[str, ...]
    family: str
    priority: int = 100


def draw_shadow(draw: ImageDraw.ImageDraw, box: tuple[float, float, float, float]) -> None:
    draw.ellipse(box, fill=rgba("shadow"))


def ellipse(draw: ImageDraw.ImageDraw, box, fill, outline=None, width: int = 3) -> None:
    draw.ellipse(box, fill=fill, outline=outline, width=width)


def rounded(draw: ImageDraw.ImageDraw, box, fill, outline=None, radius: int = 12, width: int = 3) -> None:
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def leaf(draw: ImageDraw.ImageDraw, center: tuple[float, float], size: tuple[float, float], fill, angle: float = 0) -> None:
    cx, cy = center
    w, h = size
    box = (cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2)
    image = Image.new("RGBA", (192, 192), (0, 0, 0, 0))
    overlay = ImageDraw.Draw(image)
    overlay.polygon(
        [
            (96, 96 - h / 2),
            (96 + w / 2, 96),
            (96, 96 + h / 2),
            (96 - w / 2, 96),
        ],
        fill=fill,
        outline=rgba("outline"),
    )
    if angle:
        image = image.rotate(angle, resample=Image.Resampling.BICUBIC, center=(96, 96))
    draw.bitmap((box[0], box[1]), image.crop((0, 0, 192, 192)), fill=None)


def highlight(draw: ImageDraw.ImageDraw, box, opacity: int = 90) -> None:
    color = (255, 255, 255, opacity)
    draw.ellipse(box, fill=color)


def generate_base_image() -> Image.Image:
    return Image.new("RGBA", (96, 96), (0, 0, 0, 0))


def save_imageset(asset_name: str, painter: Callable[[ImageDraw.ImageDraw], None]) -> None:
    imageset = ASSET_CATALOG / f"{asset_name}.imageset"
    imageset.mkdir(parents=True, exist_ok=True)

    images = []
    for scale, size in (("1x", 32), ("2x", 64), ("3x", 96)):
        image = generate_base_image()
        painter(ImageDraw.Draw(image, "RGBA"))
        if size != 96:
            image = image.resize((size, size), Image.Resampling.LANCZOS)
        filename = f"{asset_name}-{scale}.png"
        image.save(imageset / filename)
        images.append({"idiom": "universal", "filename": filename, "scale": scale})

    contents = {
        "images": images,
        "info": {"author": "xcode", "version": 1},
        "properties": {"template-rendering-intent": "original"},
    }
    (imageset / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n", encoding="utf-8")


def generate_manifest(entries: list[ManifestEntry]) -> None:
    MANIFEST_DATASET.mkdir(parents=True, exist_ok=True)
    dataset_contents = {
        "data": [{"idiom": "universal", "filename": "ingredient-icon-manifest.json"}],
        "info": {"author": "xcode", "version": 1},
    }
    (MANIFEST_DATASET / "Contents.json").write_text(json.dumps(dataset_contents, indent=2) + "\n", encoding="utf-8")

    payload = [
        {
            "canonicalKey": entry.canonical_key,
            "assetName": entry.asset_name,
            "aliases": list(entry.aliases),
            "family": entry.family,
            "priority": entry.priority,
        }
        for entry in entries
    ]
    (MANIFEST_DATASET / "ingredient-icon-manifest.json").write_text(
        json.dumps(payload, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def normalize_text(value: str) -> str:
    folded = unicodedata.normalize("NFD", value.lower())
    folded = "".join(character for character in folded if unicodedata.category(character) != "Mn")
    folded = re.sub(r"\([^)]*\)", " ", folded)
    folded = folded.replace("&", " and ").replace("/", " ").replace("-", " ")
    folded = re.sub(r"[^a-z0-9\s]", " ", folded)
    folded = re.sub(r"\s+", " ", folded).strip()
    return folded


COMMON_STOP_WORDS = {
    "a",
    "au",
    "aux",
    "avec",
    "bio",
    "de",
    "des",
    "du",
    "en",
    "for",
    "la",
    "le",
    "les",
    "or",
    "ou",
    "pour",
    "the",
}


PREP_WORDS = {
    "chopped",
    "diced",
    "fresh",
    "frozen",
    "grated",
    "ground",
    "halved",
    "minced",
    "nature",
    "optional",
    "peeled",
    "rinsed",
    "salted",
    "unsalted",
    "warm",
    "extra",
    "vierge",
    "virgin",
    "fraiche",
    "frais",
    "frais",
    "freshly",
    "fresh",
    "cooked",
    "cuit",
    "cuite",
    "cuites",
    "coupes",
    "coupes",
    "emince",
    "eminces",
    "haché",
    "hache",
    "hachee",
    "hachees",
    "mince",
    "mincee",
    "mincee",
    "mou",
    "moulu",
    "naturel",
    "naturelle",
    "organic",
    "raped",
    "roasted",
    "softened",
    "toasted",
    "tranche",
    "tranches",
}


UNITS = {
    "g",
    "gram",
    "grams",
    "gramme",
    "grammes",
    "kg",
    "cl",
    "dl",
    "l",
    "ml",
    "cup",
    "cups",
    "tbsp",
    "tsp",
    "tablespoon",
    "tablespoons",
    "teaspoon",
    "teaspoons",
    "oz",
    "lb",
    "piece",
    "pieces",
    "pinch",
    "pincée",
    "pincees",
    "sachet",
    "sachets",
    "slice",
    "slices",
    "sprig",
    "sprigs",
}


def tokenize_for_coverage(value: str) -> list[str]:
    normalized = normalize_text(value)
    tokens = []
    for token in normalized.split():
        if token in COMMON_STOP_WORDS or token in PREP_WORDS or token in UNITS:
            continue
        if token.isdigit():
            continue
        if len(token) > 3 and token.endswith("s") and not token.endswith("ss"):
            token = token[:-1]
        tokens.append(token)
    return tokens


def report_coverage(entries: list[ManifestEntry], library_path: Path | None) -> int:
    alias_lookup = {}
    family_lookup = Counter()
    for entry in entries:
        alias_lookup[normalize_text(entry.canonical_key)] = entry.asset_name
        for alias in entry.aliases:
            alias_lookup[normalize_text(alias)] = entry.asset_name
        family_lookup[entry.family] += 1

    ingredients: list[str] = []
    if library_path and library_path.exists():
        payload = json.loads(library_path.read_text(encoding="utf-8"))
        for recipe in payload.get("recipes", []):
            for ingredient in recipe.get("ingredients", []):
                name = ingredient.get("name")
                if name:
                    ingredients.append(name)
    else:
        ingredients = [
            "farine de blé T45",
            "beurre demi-sel",
            "powdered sugar",
            "oeufs",
            "fresh spinach",
            "crème fraîche",
            "soy sauce",
            "tuna steaks",
            "panko breadcrumbs",
            "mystery spice blend",
        ]

    exact = 0
    family = 0
    logo = 0

    family_keywords = {
        "flour": {"flour", "farine"},
        "dairy": {"milk", "lait", "cream", "creme", "yogurt", "yaourt", "butter", "beurre"},
        "cheese": {"cheese", "fromage", "mozzarella", "parmesan", "feta"},
        "protein": {"beef", "boeuf", "pork", "porc", "chicken", "poulet", "fish", "poisson", "shrimp", "crevette", "tofu"},
        "produce": {"tomato", "tomate", "onion", "oignon", "garlic", "ail", "potato", "carrot", "spinach", "broccoli", "pepper", "avocado", "apple", "banana", "berry"},
        "grain": {"rice", "riz", "pasta", "nouille", "bread", "pain", "tortilla", "bean", "lentil", "pois"},
        "sauce": {"oil", "huile", "sauce", "vinegar", "mustard", "ketchup", "mayonnaise", "soy"},
        "sweet": {"sugar", "sucre", "honey", "miel", "chocolate", "cacao"},
    }

    for ingredient in ingredients:
        normalized = normalize_text(ingredient)
        tokens = tokenize_for_coverage(ingredient)
        candidates = [normalized]
        if tokens:
            candidates.append(" ".join(tokens))
        matched = any(candidate in alias_lookup for candidate in candidates if candidate)

        if matched:
            exact += 1
            continue

        if any(set(tokens) & keywords for keywords in family_keywords.values()):
            family += 1
        else:
            logo += 1

    total = max(len(ingredients), 1)
    payload = {
        "ingredientsScanned": total,
        "exactOrAliasMatches": exact,
        "familyFallbacks": family,
        "logoFallbacks": logo,
        "logoFallbackRate": round((logo / total) * 100, 2),
    }
    print(json.dumps(payload, indent=2, ensure_ascii=False))
    return 0


def paint_flour(draw):  # noqa: ANN001
    draw_shadow(draw, (22, 66, 74, 84))
    rounded(draw, (22, 44, 74, 72), rgba("cream"), rgba("outline"), radius=14)
    draw.polygon([(26, 58), (48, 28), (70, 58)], fill=rgba("white"), outline=rgba("outline"))
    highlight(draw, (34, 34, 50, 46), 80)


def paint_butter(draw):  # noqa: ANN001
    draw_shadow(draw, (18, 66, 78, 84))
    draw.polygon([(18, 58), (34, 48), (78, 48), (62, 58)], fill=rgba("beige"), outline=rgba("outline"))
    rounded(draw, (26, 38, 70, 58), rgba("lemon"), rgba("outline"), radius=10)
    draw.line((34, 38, 34, 58), fill=rgba("outline"), width=3)
    draw.line((50, 38, 50, 58), fill=rgba("outline"), width=3)


def paint_sugar(draw):  # noqa: ANN001
    draw_shadow(draw, (22, 66, 74, 84))
    rounded(draw, (22, 48, 74, 72), rgba("cream"), rgba("outline"), radius=12)
    ellipse(draw, (30, 34, 66, 58), rgba("white"), rgba("outline"))
    highlight(draw, (40, 36, 52, 44), 120)


def paint_egg(draw):  # noqa: ANN001
    draw_shadow(draw, (28, 72, 68, 84))
    ellipse(draw, (28, 20, 68, 72), rgba("cream"), rgba("outline"))
    highlight(draw, (36, 28, 48, 42), 110)


def paint_milk(draw):  # noqa: ANN001
    draw_shadow(draw, (26, 68, 70, 84))
    rounded(draw, (32, 18, 64, 72), rgba("gray_blue"), rgba("outline"), radius=14)
    rounded(draw, (38, 12, 58, 28), rgba("white"), rgba("outline"), radius=8)
    rounded(draw, (38, 24, 58, 64), rgba("white"), None, radius=8)
    draw.line((48, 26, 48, 60), fill=rgba("gray_blue"), width=4)


def paint_cream(draw):  # noqa: ANN001
    draw_shadow(draw, (20, 68, 76, 84))
    rounded(draw, (26, 26, 70, 72), rgba("cream"), rgba("outline"), radius=14)
    draw.polygon([(34, 36), (48, 18), (62, 36)], fill=rgba("white"), outline=rgba("outline"))
    draw.line((40, 44, 56, 44), fill=rgba("outline"), width=3)
    draw.line((40, 52, 56, 52), fill=rgba("outline"), width=3)


def paint_yogurt(draw):  # noqa: ANN001
    draw_shadow(draw, (22, 68, 74, 84))
    rounded(draw, (24, 32, 72, 72), rgba("pink"), rgba("outline"), radius=14)
    rounded(draw, (22, 26, 74, 40), rgba("white"), rgba("outline"), radius=14)
    ellipse(draw, (32, 40, 64, 64), rgba("cream"), None)


def paint_cheese(draw):  # noqa: ANN001
    draw_shadow(draw, (16, 66, 80, 84))
    draw.polygon([(20, 66), (76, 54), (34, 26)], fill=rgba("gold"), outline=rgba("outline"))
    ellipse(draw, (42, 46, 52, 56), rgba("amber"), None)
    ellipse(draw, (54, 42, 64, 52), rgba("amber"), None)
    ellipse(draw, (48, 30, 58, 40), rgba("amber"), None)


def paint_cheese_white(draw):  # noqa: ANN001
    draw_shadow(draw, (20, 68, 76, 84))
    rounded(draw, (24, 30, 72, 72), rgba("cream"), rgba("outline"), radius=14)
    draw.polygon([(28, 44), (42, 34), (68, 44), (56, 60), (34, 60)], fill=rgba("white"), outline=rgba("outline"))
    leaf(draw, (64, 30), (12, 8), rgba("green"), 20)


def paint_baking_powder(draw):  # noqa: ANN001
    draw_shadow(draw, (24, 68, 72, 84))
    rounded(draw, (28, 20, 68, 74), rgba("amber"), rgba("outline"), radius=12)
    draw.polygon([(36, 30), (48, 18), (60, 30)], fill=rgba("white"), outline=rgba("outline"))
    draw.line((40, 44, 56, 44), fill=rgba("white"), width=4)
    draw.line((40, 52, 56, 52), fill=rgba("white"), width=4)


def paint_yeast(draw):  # noqa: ANN001
    draw_shadow(draw, (24, 68, 72, 84))
    rounded(draw, (28, 22, 68, 74), rgba("tan"), rgba("outline"), radius=12)
    ellipse(draw, (40, 34, 50, 44), rgba("cream"), None)
    ellipse(draw, (52, 42, 62, 52), rgba("cream"), None)
    ellipse(draw, (38, 50, 48, 60), rgba("cream"), None)


def paint_salt(draw):  # noqa: ANN001
    draw_shadow(draw, (26, 68, 70, 84))
    rounded(draw, (32, 18, 64, 72), rgba("gray"), rgba("outline"), radius=12)
    rounded(draw, (36, 12, 60, 24), rgba("white"), rgba("outline"), radius=8)
    for point in ((42, 42), (48, 50), (54, 40)):
        ellipse(draw, (point[0], point[1], point[0] + 4, point[1] + 4), rgba("white"), None)


def paint_spice(draw):  # noqa: ANN001
    draw_shadow(draw, (24, 70, 72, 84))
    draw.polygon([(46, 18), (62, 32), (54, 72), (38, 70), (34, 38)], fill=rgba("red"), outline=rgba("outline"))
    leaf(draw, (58, 26), (12, 8), rgba("green"), 35)


def paint_herbs(draw):  # noqa: ANN001
    draw_shadow(draw, (18, 70, 78, 84))
    draw.line((34, 72, 40, 34), fill=rgba("green_dark"), width=4)
    draw.line((48, 74, 50, 28), fill=rgba("green_dark"), width=4)
    draw.line((62, 72, 56, 34), fill=rgba("green_dark"), width=4)
    leaf(draw, (34, 44), (20, 14), rgba("green"), -20)
    leaf(draw, (48, 36), (22, 16), rgba("mint"), 0)
    leaf(draw, (60, 46), (20, 14), rgba("green"), 20)


def paint_oil(draw):  # noqa: ANN001
    draw_shadow(draw, (24, 68, 72, 84))
    rounded(draw, (34, 14, 62, 74), rgba("amber"), rgba("outline"), radius=12)
    rounded(draw, (40, 8, 56, 20), rgba("green_dark"), rgba("outline"), radius=6)
    ellipse(draw, (40, 30, 56, 56), rgba("gold"), None)


def paint_honey(draw):  # noqa: ANN001
    draw_shadow(draw, (20, 68, 76, 84))
    rounded(draw, (28, 24, 68, 72), rgba("gold"), rgba("outline"), radius=12)
    rounded(draw, (32, 16, 64, 30), rgba("brown"), rgba("outline"), radius=8)
    draw.polygon([(48, 48), (54, 58), (48, 70), (42, 58)], fill=rgba("amber"), outline=rgba("outline"))


def paint_chocolate(draw):  # noqa: ANN001
    draw_shadow(draw, (18, 68, 78, 84))
    rounded(draw, (20, 24, 76, 72), rgba("brown_dark"), rgba("outline"), radius=12)
    for offset in (0, 18, 36):
        rounded(draw, (24 + offset, 28, 40 + offset, 48), rgba("brown"), None, radius=6)
        rounded(draw, (24 + offset, 50, 40 + offset, 68), rgba("brown"), None, radius=6)


def paint_vanilla(draw):  # noqa: ANN001
    draw_shadow(draw, (20, 70, 76, 84))
    draw.line((34, 70, 56, 30), fill=rgba("brown_dark"), width=6)
    draw.line((46, 72, 64, 36), fill=rgba("brown"), width=6)
    ellipse(draw, (58, 14, 78, 34), rgba("cream"), rgba("outline"))
    ellipse(draw, (64, 20, 72, 28), rgba("gold"), None)


def paint_water(draw):  # noqa: ANN001
    draw_shadow(draw, (28, 72, 68, 84))
    draw.polygon([(48, 18), (62, 44), (60, 62), (48, 76), (36, 62), (34, 44)], fill=rgba("blue"), outline=rgba("outline"))
    highlight(draw, (44, 28, 52, 40), 90)


def paint_stock(draw):  # noqa: ANN001
    draw_shadow(draw, (18, 68, 78, 84))
    rounded(draw, (22, 42, 74, 72), rgba("brown"), rgba("outline"), radius=14)
    ellipse(draw, (26, 34, 70, 56), rgba("amber"), rgba("outline"))
    draw.line((24, 54, 18, 54), fill=rgba("outline"), width=4)
    draw.line((74, 54, 80, 54), fill=rgba("outline"), width=4)


def paint_rice(draw):  # noqa: ANN001
    draw_shadow(draw, (18, 68, 78, 84))
    rounded(draw, (24, 48, 72, 72), rgba("blue_dark"), rgba("outline"), radius=14)
    ellipse(draw, (28, 30, 68, 56), rgba("white"), rgba("outline"))


def paint_pasta(draw):  # noqa: ANN001
    draw_shadow(draw, (16, 70, 80, 84))
    for box in ((18, 26, 46, 54), (32, 38, 60, 66), (46, 22, 74, 50)):
        draw.arc(box, start=20, end=300, fill=rgba("gold"), width=7)


def paint_bread(draw):  # noqa: ANN001
    draw_shadow(draw, (18, 68, 78, 84))
    rounded(draw, (20, 28, 76, 72), rgba("tan"), rgba("outline"), radius=20)
    draw.arc((28, 36, 44, 56), start=240, end=60, fill=rgba("outline"), width=3)
    draw.arc((42, 32, 58, 54), start=240, end=60, fill=rgba("outline"), width=3)
    draw.arc((56, 36, 72, 56), start=240, end=60, fill=rgba("outline"), width=3)


def paint_tortilla(draw):  # noqa: ANN001
    draw_shadow(draw, (18, 68, 78, 84))
    ellipse(draw, (18, 24, 78, 76), rgba("beige"), rgba("outline"))
    draw.arc((24, 30, 72, 72), start=210, end=330, fill=rgba("tan"), width=4)
    draw.arc((28, 34, 68, 68), start=210, end=330, fill=rgba("tan"), width=4)


def paint_beans(draw):  # noqa: ANN001
    draw_shadow(draw, (20, 70, 76, 84))
    for box in ((24, 26, 48, 58), (40, 34, 64, 66), (50, 22, 72, 52)):
        ellipse(draw, box, rgba("red"), rgba("outline"))


def paint_nuts(draw):  # noqa: ANN001
    draw_shadow(draw, (20, 70, 76, 84))
    ellipse(draw, (24, 24, 48, 66), rgba("tan"), rgba("outline"))
    draw.pieslice((44, 28, 72, 66), start=220, end=40, fill=rgba("brown"), outline=rgba("outline"))
    highlight(draw, (28, 30, 36, 40), 70)


def paint_tofu(draw):  # noqa: ANN001
    draw_shadow(draw, (20, 68, 76, 84))
    rounded(draw, (24, 24, 72, 72), rgba("cream"), rgba("outline"), radius=14)
    draw.line((34, 34, 62, 62), fill=rgba("gray"), width=3)
    draw.line((62, 34, 34, 62), fill=rgba("gray"), width=3)


def paint_chicken(draw):  # noqa: ANN001
    draw_shadow(draw, (16, 70, 80, 84))
    ellipse(draw, (22, 26, 70, 68), rgba("amber"), rgba("outline"))
    ellipse(draw, (56, 20, 76, 40), rgba("cream"), rgba("outline"))
    ellipse(draw, (62, 18, 72, 28), rgba("white"), rgba("outline"))


def paint_beef(draw):  # noqa: ANN001
    draw_shadow(draw, (16, 70, 80, 84))
    draw.polygon([(20, 34), (44, 18), (72, 30), (76, 58), (54, 76), (24, 64)], fill=rgba("red"), outline=rgba("outline"))
    ellipse(draw, (34, 34, 56, 54), rgba("pink"), None)


def paint_pork(draw):  # noqa: ANN001
    draw_shadow(draw, (16, 70, 80, 84))
    draw.polygon([(20, 60), (30, 30), (44, 36), (56, 24), (74, 30), (64, 66)], fill=rgba("pink"), outline=rgba("outline"))
    draw.line((30, 34, 62, 66), fill=rgba("white"), width=5)
    draw.line((38, 28, 70, 60), fill=rgba("white"), width=5)


def paint_fish(draw):  # noqa: ANN001
    draw_shadow(draw, (16, 68, 80, 84))
    ellipse(draw, (20, 30, 68, 64), rgba("blue"), rgba("outline"))
    draw.polygon([(68, 46), (82, 30), (82, 62)], fill=rgba("blue_dark"), outline=rgba("outline"))
    ellipse(draw, (34, 40, 40, 46), rgba("white"), None)


def paint_shrimp(draw):  # noqa: ANN001
    draw_shadow(draw, (16, 70, 80, 84))
    draw.arc((18, 22, 78, 78), start=240, end=30, fill=rgba("orange"), width=10)
    draw.arc((30, 34, 66, 70), start=240, end=30, fill=rgba("cream"), width=4)
    draw.line((70, 32, 82, 20), fill=rgba("outline"), width=3)


def paint_tomato(draw):  # noqa: ANN001
    draw_shadow(draw, (20, 70, 76, 84))
    ellipse(draw, (20, 24, 76, 76), rgba("tomato"), rgba("outline"))
    draw.polygon([(48, 20), (56, 34), (70, 34), (58, 42), (64, 56), (48, 48), (32, 56), (38, 42), (26, 34), (40, 34)], fill=rgba("green"), outline=rgba("outline"))


def paint_onion(draw):  # noqa: ANN001
    draw_shadow(draw, (24, 70, 72, 84))
    draw.polygon([(48, 16), (66, 38), (62, 66), (48, 78), (34, 66), (30, 38)], fill=rgba("tan"), outline=rgba("outline"))
    draw.line((48, 26, 48, 70), fill=rgba("outline"), width=3)
    draw.line((40, 30, 44, 68), fill=rgba("outline"), width=2)
    draw.line((56, 30, 52, 68), fill=rgba("outline"), width=2)


def paint_garlic(draw):  # noqa: ANN001
    draw_shadow(draw, (24, 70, 72, 84))
    ellipse(draw, (26, 28, 54, 72), rgba("cream"), rgba("outline"))
    ellipse(draw, (42, 24, 70, 72), rgba("cream"), rgba("outline"))
    leaf(draw, (52, 20), (16, 10), rgba("green"), 10)


def paint_potato(draw):  # noqa: ANN001
    draw_shadow(draw, (18, 70, 78, 84))
    draw.polygon([(22, 38), (38, 22), (66, 26), (78, 52), (60, 76), (28, 68)], fill=rgba("brown"), outline=rgba("outline"))
    for dot in ((38, 40), (54, 48), (48, 60)):
        ellipse(draw, (dot[0], dot[1], dot[0] + 4, dot[1] + 4), rgba("brown_dark"), None)


def paint_carrot(draw):  # noqa: ANN001
    draw_shadow(draw, (20, 72, 76, 84))
    draw.polygon([(24, 24), (72, 42), (34, 78)], fill=rgba("orange"), outline=rgba("outline"))
    leaf(draw, (24, 20), (18, 10), rgba("green"), -20)
    leaf(draw, (30, 16), (18, 10), rgba("green"), 20)


def paint_mushroom(draw):  # noqa: ANN001
    draw_shadow(draw, (20, 70, 76, 84))
    ellipse(draw, (20, 22, 76, 54), rgba("brown"), rgba("outline"))
    rounded(draw, (38, 42, 58, 78), rgba("cream"), rgba("outline"), radius=10)


def paint_leafy_green(draw):  # noqa: ANN001
    draw_shadow(draw, (16, 72, 80, 84))
    leaf(draw, (48, 48), (52, 62), rgba("green"), 0)
    draw.line((48, 28, 48, 74), fill=rgba("green_dark"), width=4)


def paint_broccoli(draw):  # noqa: ANN001
    draw_shadow(draw, (18, 72, 78, 84))
    rounded(draw, (42, 46, 54, 78), rgba("green_dark"), rgba("outline"), radius=8)
    for box in ((20, 26, 44, 50), (36, 18, 60, 48), (52, 24, 76, 50)):
        ellipse(draw, box, rgba("green"), rgba("outline"))


def paint_pepper(draw):  # noqa: ANN001
    draw_shadow(draw, (22, 70, 74, 84))
    draw.polygon([(36, 18), (60, 18), (72, 34), (68, 66), (50, 78), (28, 66), (24, 34)], fill=rgba("red"), outline=rgba("outline"))
    leaf(draw, (50, 16), (16, 10), rgba("green"), 18)


def paint_cucumber(draw):  # noqa: ANN001
    draw_shadow(draw, (16, 70, 80, 84))
    rounded(draw, (18, 34, 78, 62), rgba("green"), rgba("outline"), radius=16)
    highlight(draw, (26, 38, 46, 48), 70)


def paint_zucchini(draw):  # noqa: ANN001
    draw_shadow(draw, (14, 70, 82, 84))
    rounded(draw, (16, 34, 80, 60), rgba("green_dark"), rgba("outline"), radius=16)
    leaf(draw, (78, 32), (12, 8), rgba("green"), 40)


def paint_corn(draw):  # noqa: ANN001
    draw_shadow(draw, (20, 70, 76, 84))
    rounded(draw, (34, 18, 62, 74), rgba("gold"), rgba("outline"), radius=14)
    for x in (40, 48, 56):
        for y in (28, 38, 48, 58):
            ellipse(draw, (x, y, x + 5, y + 5), rgba("lemon"), None)
    draw.polygon([(32, 56), (16, 74), (28, 30)], fill=rgba("green"), outline=rgba("outline"))
    draw.polygon([(64, 56), (80, 74), (68, 30)], fill=rgba("green"), outline=rgba("outline"))


def paint_avocado(draw):  # noqa: ANN001
    draw_shadow(draw, (20, 70, 76, 84))
    ellipse(draw, (20, 20, 76, 78), rgba("green_dark"), rgba("outline"))
    ellipse(draw, (28, 28, 68, 70), rgba("mint"), None)
    ellipse(draw, (40, 40, 56, 58), rgba("brown"), rgba("outline"))


def paint_lemon(draw):  # noqa: ANN001
    draw_shadow(draw, (20, 70, 76, 84))
    ellipse(draw, (20, 24, 76, 76), rgba("lemon"), rgba("outline"))
    for angle in (0, 45, 90, 135):
        draw.line((48, 50, 48 + 18 * (1 if angle < 90 else -1), 50 - 18 * (1 if angle in (45, 90) else -1)), fill=rgba("white"), width=3)


def paint_lime(draw):  # noqa: ANN001
    draw_shadow(draw, (20, 70, 76, 84))
    ellipse(draw, (20, 24, 76, 76), rgba("lime"), rgba("outline"))
    for segment in ((48, 30, 64, 48), (48, 30, 32, 48), (48, 30, 48, 62)):
        draw.line(segment, fill=rgba("white"), width=3)


def paint_orange(draw):  # noqa: ANN001
    draw_shadow(draw, (20, 70, 76, 84))
    ellipse(draw, (20, 24, 76, 76), rgba("orange"), rgba("outline"))
    leaf(draw, (60, 20), (14, 10), rgba("green"), 25)
    highlight(draw, (30, 34, 42, 46), 80)


def paint_apple(draw):  # noqa: ANN001
    draw_shadow(draw, (18, 70, 78, 84))
    ellipse(draw, (20, 24, 54, 74), rgba("red"), rgba("outline"))
    ellipse(draw, (42, 24, 76, 74), rgba("red"), rgba("outline"))
    draw.line((48, 16, 50, 30), fill=rgba("brown_dark"), width=4)
    leaf(draw, (60, 18), (16, 10), rgba("green"), 30)


def paint_berry(draw):  # noqa: ANN001
    draw_shadow(draw, (18, 70, 78, 84))
    for box in ((24, 34, 44, 54), (40, 28, 60, 48), (56, 36, 76, 56), (34, 46, 54, 66), (50, 50, 70, 70)):
        ellipse(draw, box, rgba("berry"), rgba("outline"))
    leaf(draw, (48, 22), (16, 10), rgba("green"), 0)


def paint_banana(draw):  # noqa: ANN001
    draw_shadow(draw, (14, 72, 82, 84))
    draw.arc((18, 20, 82, 82), start=210, end=340, fill=rgba("lemon"), width=12)
    draw.arc((26, 28, 74, 74), start=210, end=340, fill=rgba("cream"), width=4)


def paint_coconut(draw):  # noqa: ANN001
    draw_shadow(draw, (18, 70, 78, 84))
    ellipse(draw, (18, 24, 54, 74), rgba("coconut"), rgba("outline"))
    draw.pieslice((42, 24, 78, 74), start=300, end=120, fill=rgba("cream"), outline=rgba("outline"))


def paint_sauce(draw):  # noqa: ANN001
    draw_shadow(draw, (24, 68, 72, 84))
    rounded(draw, (34, 14, 62, 74), rgba("tomato"), rgba("outline"), radius=12)
    rounded(draw, (40, 8, 56, 20), rgba("green_dark"), rgba("outline"), radius=6)
    rounded(draw, (38, 30, 58, 54), rgba("cream"), None, radius=10)


PAINTERS = {
    "IngredientIconFlour": paint_flour,
    "IngredientIconButter": paint_butter,
    "IngredientIconSugar": paint_sugar,
    "IngredientIconEgg": paint_egg,
    "IngredientIconMilk": paint_milk,
    "IngredientIconCream": paint_cream,
    "IngredientIconYogurt": paint_yogurt,
    "IngredientIconCheese": paint_cheese,
    "IngredientIconWhiteCheese": paint_cheese_white,
    "IngredientIconBakingPowder": paint_baking_powder,
    "IngredientIconYeast": paint_yeast,
    "IngredientIconSalt": paint_salt,
    "IngredientIconSpice": paint_spice,
    "IngredientIconHerbs": paint_herbs,
    "IngredientIconOil": paint_oil,
    "IngredientIconHoney": paint_honey,
    "IngredientIconChocolate": paint_chocolate,
    "IngredientIconVanilla": paint_vanilla,
    "IngredientIconWater": paint_water,
    "IngredientIconStock": paint_stock,
    "IngredientIconRice": paint_rice,
    "IngredientIconPasta": paint_pasta,
    "IngredientIconBread": paint_bread,
    "IngredientIconTortilla": paint_tortilla,
    "IngredientIconBeans": paint_beans,
    "IngredientIconNuts": paint_nuts,
    "IngredientIconTofu": paint_tofu,
    "IngredientIconChicken": paint_chicken,
    "IngredientIconBeef": paint_beef,
    "IngredientIconPork": paint_pork,
    "IngredientIconFish": paint_fish,
    "IngredientIconShrimp": paint_shrimp,
    "IngredientIconTomato": paint_tomato,
    "IngredientIconOnion": paint_onion,
    "IngredientIconGarlic": paint_garlic,
    "IngredientIconPotato": paint_potato,
    "IngredientIconCarrot": paint_carrot,
    "IngredientIconMushroom": paint_mushroom,
    "IngredientIconLeafyGreen": paint_leafy_green,
    "IngredientIconBroccoli": paint_broccoli,
    "IngredientIconPepper": paint_pepper,
    "IngredientIconCucumber": paint_cucumber,
    "IngredientIconZucchini": paint_zucchini,
    "IngredientIconCorn": paint_corn,
    "IngredientIconAvocado": paint_avocado,
    "IngredientIconLemon": paint_lemon,
    "IngredientIconLime": paint_lime,
    "IngredientIconOrange": paint_orange,
    "IngredientIconApple": paint_apple,
    "IngredientIconBerry": paint_berry,
    "IngredientIconBanana": paint_banana,
    "IngredientIconCoconut": paint_coconut,
    "IngredientIconSauce": paint_sauce,
}


ENTRIES = [
    ManifestEntry("flour", "IngredientIconFlour", ("farine", "farine de ble", "wheat flour", "all purpose flour", "plain flour", "bread flour", "cake flour", "self rising flour", "self raising flour", "t45 flour", "t55 flour", "t65 flour", "tipo 00", "00 flour", "almond flour"), "flour"),
    ManifestEntry("butter", "IngredientIconButter", ("beurre", "beurre doux", "beurre demi sel", "unsalted butter", "salted butter", "melted butter"), "butter"),
    ManifestEntry("sugar", "IngredientIconSugar", ("sucre", "granulated sugar", "white sugar", "caster sugar", "brown sugar", "cassonade", "vergeoise", "powdered sugar", "icing sugar", "sucre glace", "confectioners sugar"), "sugar"),
    ManifestEntry("egg", "IngredientIconEgg", ("oeuf", "oeufs", "œuf", "œufs", "egg", "eggs", "egg yolk", "egg white", "jaune d oeuf", "blanc d oeuf"), "egg"),
    ManifestEntry("milk", "IngredientIconMilk", ("lait", "milk", "whole milk", "skim milk", "semi skimmed milk", "lait entier", "lait demi ecreme", "lait ecreme"), "milk"),
    ManifestEntry("cream", "IngredientIconCream", ("creme", "crème", "heavy cream", "double cream", "whipping cream", "sour cream", "creme fraiche", "crème fraîche"), "cream"),
    ManifestEntry("yogurt", "IngredientIconYogurt", ("yaourt", "yogurt", "yoghurt", "greek yogurt", "greek yoghurt", "yaourt grec"), "yogurt"),
    ManifestEntry("cheese", "IngredientIconCheese", ("cheese", "fromage", "cheddar", "parmesan", "gruyere", "gruyère", "emmental", "pecorino", "mozzarella", "comte", "comté"), "cheese"),
    ManifestEntry("white cheese", "IngredientIconWhiteCheese", ("feta", "ricotta", "mascarpone", "cottage cheese", "goat cheese", "cream cheese", "fromage blanc", "chèvre", "chevre"), "white cheese", 110),
    ManifestEntry("baking powder", "IngredientIconBakingPowder", ("baking powder", "levure chimique"), "baking powder"),
    ManifestEntry("yeast", "IngredientIconYeast", ("yeast", "dry yeast", "instant yeast", "fresh yeast", "levure", "levure boulangere", "levure boulangère"), "yeast"),
    ManifestEntry("salt", "IngredientIconSalt", ("salt", "sea salt", "kosher salt", "sel", "fleur de sel"), "salt"),
    ManifestEntry("spice", "IngredientIconSpice", ("paprika", "curry", "cumin", "ginger", "gingembre", "turmeric", "curcuma", "chili", "chilli", "piment", "harissa", "garam masala"), "spice"),
    ManifestEntry("herbs", "IngredientIconHerbs", ("herbs", "herbes", "basil", "basilic", "parsley", "persil", "cilantro", "coriander", "coriandre", "mint", "menthe", "thyme", "thym", "rosemary", "romarin", "chives", "ciboulette", "dill", "aneth"), "herbs"),
    ManifestEntry("oil", "IngredientIconOil", ("oil", "olive oil", "vegetable oil", "sesame oil", "huile", "huile d olive", "huile de sesame", "huile végétale", "huile végétale"), "oil"),
    ManifestEntry("honey", "IngredientIconHoney", ("honey", "miel", "maple syrup", "sirop d erable", "sirop d'érable", "agave", "molasses"), "honey"),
    ManifestEntry("chocolate", "IngredientIconChocolate", ("chocolate", "dark chocolate", "milk chocolate", "chocolat", "cocoa", "cacao", "cocoa powder", "pépites de chocolat", "pepites de chocolat"), "chocolate"),
    ManifestEntry("vanilla", "IngredientIconVanilla", ("vanilla", "vanille", "vanilla extract", "vanilla bean", "extrait de vanille"), "vanilla"),
    ManifestEntry("water", "IngredientIconWater", ("water", "eau", "sparkling water"), "water"),
    ManifestEntry("stock", "IngredientIconStock", ("stock", "broth", "bouillon", "chicken stock", "vegetable stock", "beef stock", "fish stock", "court bouillon"), "stock"),
    ManifestEntry("rice", "IngredientIconRice", ("rice", "riz", "basmati", "jasmine rice", "arborio rice", "risotto rice"), "rice"),
    ManifestEntry("pasta", "IngredientIconPasta", ("pasta", "pâtes", "pates", "spaghetti", "penne", "fusilli", "linguine", "ramen noodles", "noodles", "nouilles", "udon"), "pasta"),
    ManifestEntry("bread", "IngredientIconBread", ("bread", "pain", "baguette", "toast", "brioche", "bun", "burger bun", "breadcrumbs", "panko"), "bread"),
    ManifestEntry("tortilla", "IngredientIconTortilla", ("tortilla", "wrap", "naan", "pita", "flatbread"), "tortilla"),
    ManifestEntry("beans", "IngredientIconBeans", ("beans", "black beans", "kidney beans", "haricots", "haricots noirs", "haricots rouges", "lentils", "lentilles", "chickpeas", "pois chiches", "peas", "petits pois"), "beans"),
    ManifestEntry("nuts", "IngredientIconNuts", ("almond", "amandes", "amande", "walnut", "noix", "pecan", "cashew", "cacahuete", "cacahuètes", "peanut", "sesame", "graines de sesame", "seed mix", "sunflower seeds"), "nuts"),
    ManifestEntry("tofu", "IngredientIconTofu", ("tofu", "tempeh"), "tofu"),
    ManifestEntry("chicken", "IngredientIconChicken", ("chicken", "poulet", "chicken breast", "chicken thigh"), "chicken"),
    ManifestEntry("beef", "IngredientIconBeef", ("beef", "boeuf", "bœuf", "steak", "ground beef", "minced beef", "viande hachee", "viande hachée"), "beef"),
    ManifestEntry("pork", "IngredientIconPork", ("pork", "porc", "bacon", "ham", "lardons", "sausage", "saucisse", "prosciutto"), "pork"),
    ManifestEntry("fish", "IngredientIconFish", ("fish", "poisson", "salmon", "saumon", "tuna", "thon", "cod", "cabillaud", "tilapia", "trout", "sea bass"), "fish"),
    ManifestEntry("shrimp", "IngredientIconShrimp", ("shrimp", "prawn", "crevette", "crevettes", "crab", "lobster", "langoustine"), "shrimp"),
    ManifestEntry("tomato", "IngredientIconTomato", ("tomato", "tomates", "tomate", "cherry tomato", "passata", "tomato sauce", "tomato paste", "concentré de tomate", "sauce tomate"), "tomato"),
    ManifestEntry("onion", "IngredientIconOnion", ("onion", "oignon", "red onion", "yellow onion", "shallot", "echalote", "échalote", "spring onion", "scallion", "green onion"), "onion"),
    ManifestEntry("garlic", "IngredientIconGarlic", ("garlic", "ail", "garlic cloves", "ail en poudre"), "garlic"),
    ManifestEntry("potato", "IngredientIconPotato", ("potato", "potatoes", "pomme de terre", "pommes de terre", "sweet potato", "patate douce"), "potato"),
    ManifestEntry("carrot", "IngredientIconCarrot", ("carrot", "carotte", "carottes"), "carrot"),
    ManifestEntry("mushroom", "IngredientIconMushroom", ("mushroom", "champignon", "champignons", "shiitake", "portobello"), "mushroom"),
    ManifestEntry("leafy green", "IngredientIconLeafyGreen", ("spinach", "epinard", "épinard", "lettuce", "laitue", "salade", "rocket", "roquette", "kale", "chou kale", "bok choy"), "leafy green"),
    ManifestEntry("broccoli", "IngredientIconBroccoli", ("broccoli", "brocoli", "cauliflower", "chou fleur"), "broccoli"),
    ManifestEntry("pepper", "IngredientIconPepper", ("pepper", "bell pepper", "poivron", "poivrons", "jalapeno", "jalapeño"), "pepper"),
    ManifestEntry("cucumber", "IngredientIconCucumber", ("cucumber", "concombre", "pickle", "cornichon"), "cucumber"),
    ManifestEntry("zucchini", "IngredientIconZucchini", ("zucchini", "courgette", "eggplant", "aubergine"), "zucchini"),
    ManifestEntry("corn", "IngredientIconCorn", ("corn", "maïs", "mais"), "corn"),
    ManifestEntry("avocado", "IngredientIconAvocado", ("avocado", "avocat"), "avocado"),
    ManifestEntry("lemon", "IngredientIconLemon", ("lemon", "citron", "lemon juice", "jus de citron"), "lemon"),
    ManifestEntry("lime", "IngredientIconLime", ("lime", "citron vert", "lime juice"), "lime"),
    ManifestEntry("orange", "IngredientIconOrange", ("orange", "orange juice", "jus d orange"), "orange"),
    ManifestEntry("apple", "IngredientIconApple", ("apple", "pomme", "pear", "poire"), "apple"),
    ManifestEntry("berry", "IngredientIconBerry", ("berries", "berry", "strawberry", "fraise", "blueberry", "myrtille", "raspberry", "framboise", "cranberry"), "berry"),
    ManifestEntry("banana", "IngredientIconBanana", ("banana", "banane"), "banana"),
    ManifestEntry("coconut", "IngredientIconCoconut", ("coconut", "noix de coco", "coconut milk", "coconut cream"), "coconut"),
    ManifestEntry("sauce", "IngredientIconSauce", ("soy sauce", "sauce soja", "vinaigre", "vinegar", "mustard", "moutarde", "ketchup", "mayonnaise", "mayo", "hot sauce", "sauce piquante"), "sauce"),
]


def ensure_vendor_placeholder() -> None:
    VENDOR_SOURCE.mkdir(parents=True, exist_ok=True)
    readme = VENDOR_SOURCE / "README.md"
    if not readme.exists():
        readme.write_text(
            "# Ingredient icon vendor source\n\n"
            "Drop licensed vendor packs here before running a future ingestion step.\n"
            "This folder is intentionally outside the app target.\n",
            encoding="utf-8",
        )


def generate() -> int:
    ensure_vendor_placeholder()
    for asset_name, painter in PAINTERS.items():
        save_imageset(asset_name, painter)
    generate_manifest(ENTRIES)
    print(f"Generated {len(PAINTERS)} ingredient icon assets and {len(ENTRIES)} manifest entries.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate local ingredient icon assets and coverage reports.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("generate", help="Generate icon assets and the manifest dataset.")

    report_parser = subparsers.add_parser("coverage", help="Report manifest coverage against a local library snapshot.")
    report_parser.add_argument("--library", type=Path, default=None, help="Path to a Cooksy library.json snapshot.")

    args = parser.parse_args()

    if args.command == "generate":
        return generate()

    if args.command == "coverage":
        return report_coverage(ENTRIES, args.library)

    parser.error("Unknown command")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
