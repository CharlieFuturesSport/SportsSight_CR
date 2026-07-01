# Methodology Spreadsheet Guide
# Sheet: BrandAssetMethodology

Each row = one (Brand, Asset) combination you want to detect.
The columns tell the script which route to use to find it.

---

## The columns

| Column | What it means |
|---|---|
| Brand | Brand name — must match what the model outputs exactly (after "Logo - Brand - " is stripped) |
| Asset | Asset name — must match model class name exactly |
| BrandAssetPairing | 1 = both the brand logo AND the asset zone are detected by the model |
| BrandOnly | 1 = only the brand logo is detected (no asset zone needed) |
| AssetOnly | 1 = only the asset zone is detected (brand is always on that asset, so inferred) |
| OCR | 1 = also cross-reference with OCR text — brand text must appear near the detection |
| OCR_coordinates | 1 = TVGI method — find brand text at consistent screen coordinates across many frames |
| IC | Camera angle(s) required — must match classification model output for that frame e.g. `Bowler Run Up, Delivery Stride` |
| Brand_confidence | Min confidence for brand detection (0–1). Default 0.3 |
| Asset_confidence | Min confidence for asset detection (0–1). Default 0.3 |
| IC_confidence | Min confidence for classification prediction (0–1). Default 0.3 |
| MinSize | Min bounding box size as % of frame (0–1). Leave blank for no size filter |
| Creative | Specific creative text on that board/asset (e.g. `Protecting Pensions`). Used in OCR matching |
| Final_brand | What brand name to output — usually same as Brand. Change if you want to remap |
| Final_asset | What asset name to output — usually same as Asset. Change if you want to remap |

---

## Rules for which flags to set

**Only ever fill one "detection route" per row.** The combinations are:

### Most common — physical logo detected by model + OCR confirms it
```
BrandAssetPairing = 1
OCR = 1
everything else blank
```
Use for: perimeter boards, sightscreens, jerseys, any physical sponsor placement.
This is what every single ECB row currently uses.

### Brand AND asset detected, no OCR needed
```
BrandAssetPairing = 1
everything else blank
```
Use for: when OCR can't reliably read the brand (e.g. logos not text-based).

### Same as above but only in specific camera shots
```
BrandAssetPairing = 1
OCR = 1
IC = Bowler Run Up, Delivery Stride
```
Use for: jersey sponsors only visible in close-up shots.
IC column takes comma-separated camera angle names matching the classification model classes exactly.

### TVGI / on-screen graphic detected by text coordinates
```
OCR_coordinates = 1
everything else blank
```
Use for: scorecard overlays, on-screen sponsor bugs (Rothesay, Sky Sports).
These are NOT physical objects — the model can't see them as brand+asset.
The coordinate method clusters where OCR text appears consistently across frames.

### Asset alone implies the brand (rare)
```
AssetOnly = 1
everything else blank
```
Use for: when one specific asset is always sponsored by one brand with no logo variation.

---

## Multiple rows for the same Brand + Asset

Perfectly fine — and common. Reasons to duplicate:

1. **Different creatives** — same Rothesay Perimeter Board row appears twice if the board shows two different messages. Put the creative text in the `Creative` column on each.

2. **Different detection routes** — one row via BrandAssetPairing, another via OCR_coordinates (e.g. Rothesay physical board + Rothesay TVGI).

3. **Different camera angle requirements** — one row with IC blank (all angles), another with IC filled (specific angle, different confidence threshold).

---

## Confidence thresholds

Default is 0.3 for everything. Adjust if:

- Brand is getting lots of false positives → raise Brand_confidence (e.g. 0.5)
- Brand is getting missed a lot → lower it (e.g. 0.2), but check you're not just picking up noise
- Asset is reliable → can lower Asset_confidence to 0.2 to be more permissive
- Camera angle classification is noisy → raise IC_confidence

The 0.3 default is quite permissive — the model has to be only 30% confident. Works fine for most cases because the brand+asset combination is specific enough.

---

## Creative column

Fill this in when a brand's board has specific advertising copy (not just the logo).

Examples from ECB:
- `Better Never Stops` (Castore)
- `Protecting Pensions` (Rothesay)
- `Trade. Invest. Progress` (IG)
- `ALL NEW ALL ELECTRIC TOYOTA` (Toyota)

This is used by the Missing OCR step (when enabled) to exclude creatives from the "unassigned" fallback — a creative text match is handled separately, not lumped in with unassigned brand detections.

---

## Final_brand / Final_asset

Usually just copy Brand and Asset exactly. Change them only if:
- The model class name is ugly (e.g. `Logo - Brand - Toyota`) and you want the output to say `Toyota`
- You're consolidating multiple model classes into one output name

Note: `normalize_brand_label()` in the script already strips `Logo - Brand - ` prefix automatically, so you don't need to account for that here.

---

## Blank rows at the bottom

Ignore them — the current spreadsheet has some rows with only `OCR=1` and everything else blank. These are artefacts and do nothing useful (method_filter won't pick them up for any real processing step).

---

## Quick checklist before running

- [ ] Every active brand-asset pair has exactly one route set (BrandAssetPairing / BrandOnly / AssetOnly / OCR_coordinates)
- [ ] Brand name matches model output exactly (check Raw_Brands / Raw_BrandAssets in SQL)
- [ ] Asset name matches model output exactly (check Raw_Assets in SQL)
- [ ] Final_brand and Final_asset are filled in (even if same as Brand/Asset)
- [ ] No duplicate rows you didn't intend
- [ ] IC values (if used) match classification model class names exactly
