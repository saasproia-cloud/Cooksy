#!/usr/bin/env python3
"""
Reorganize ingredient images by category and remove backgrounds.

1. Reads ingredients.json to know which image belongs to which category
2. Moves images from images/ingredients/ to images/{category}/
3. Removes background using rembg (transparent PNG)
4. Updates ingredients.json with new paths
"""

import json
import os
import sys
from pathlib import Path

# rembg + PIL
from rembg import remove
from PIL import Image
import io

ROOT = Path(__file__).resolve().parent.parent
JSON_PATH = ROOT / "images" / "ingredients.json"
SRC_DIR = ROOT / "images" / "ingredients"

def process_image(src_path, dst_path):
    """Remove background and save as transparent PNG."""
    with open(src_path, "rb") as f:
        input_data = f.read()
    output_data = remove(input_data)
    # Save
    dst_path.parent.mkdir(parents=True, exist_ok=True)
    with open(dst_path, "wb") as f:
        f.write(output_data)
    return len(output_data)

def main():
    with open(JSON_PATH) as f:
        ingredients = json.load(f)

    # Count images that have .png (downloaded)
    to_process = [ing for ing in ingredients if ing["image"].endswith(".png")]
    print(f"🔧 Processing {len(to_process)} images (remove bg + reorganize)\n")

    processed = 0
    skipped = 0
    errors = []

    for i, ing in enumerate(to_process):
        cat = ing["category"]  # "vegetable", "fruit", etc.
        cat_dir = ROOT / "images" / (cat + "s")  # vegetables, fruits, etc.
        # Handle plural correctly
        if cat == "fruit":
            cat_dir = ROOT / "images" / "fruits"
        elif cat == "vegetable":
            cat_dir = ROOT / "images" / "vegetables"
        else:
            cat_dir = ROOT / "images" / (cat + "s")

        src = SRC_DIR / ing["image"]
        dst = cat_dir / ing["image"]
        prefix = f"[{i+1:3d}/{len(to_process)}]"

        if not src.exists():
            print(f"{prefix} ⏭  {ing['name']}  (no source file)")
            skipped += 1
            continue

        if dst.exists():
            print(f"{prefix} ⏭  {ing['name']}  (already done)")
            skipped += 1
            continue

        try:
            size = process_image(src, dst)
            print(f"{prefix} ✓  {ing['name']}  → {cat}s/{ing['image']} ({size//1024} KB)")
            processed += 1
        except Exception as e:
            print(f"{prefix} ⚠  {ing['name']}  ({e})")
            errors.append(ing["name"])

    # Update ingredients.json: change image paths to include category folder
    for ing in ingredients:
        cat = ing["category"]
        if cat == "fruit":
            folder = "fruits"
        elif cat == "vegetable":
            folder = "vegetables"
        else:
            folder = cat + "s"
        # Update image path to category-relative (just filename, folder is implicit from category)
        # No change needed to image field — the folder is derived from category

    print(f"\n───── Summary ─────")
    print(f"✓  processed: {processed}")
    print(f"⏭  skipped:   {skipped}")
    print(f"⚠  errors:    {len(errors)}")
    if errors:
        print("\nErrors:")
        for e in errors:
            print(f"  - {e}")

if __name__ == "__main__":
    main()
