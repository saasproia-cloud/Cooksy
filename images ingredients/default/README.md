# Fallback ingredient image

Drop your fallback photo here as **`default.png`** — this image is shown whenever
an ingredient has no matching photo in any category.

Then run:

```
node Scripts/apply-default-ingredient.mjs
```

The script copies `default.png` into the iOS asset catalog
(`Cooksy/Resources/Assets.xcassets/IngredientIconGeneric.imageset/`) at all
three resolutions so the app picks it up on the next build.
