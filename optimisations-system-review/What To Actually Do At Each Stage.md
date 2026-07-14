# What To Actually Do At Each Stage

Same structure as `SportsSight Process Overview.docx` (Responsibility / Action /
Files), but bolstered with what the data actually looks like at each point and
- most importantly - exactly what fills the methodology file, since that's
the real bottleneck most of the time, not the SQL.

---

## 1. Record footage
**Who:** Account team. Nothing to do here on the technical side.

## 2. RoboFlow processing
**Who:** Chris F.
**Produces:** `SportsSight_Raw_Assets`, `SportsSight_Raw_Brands`,
`SportsSight_Raw_BrandAssets`, `SportsSight_Raw_Classifications` - one row per
detected object/brand/classification per frame, each with its own box
coordinates and confidence score. Nothing to fill in manually here.

## 3. Send footage to OCR
**Who:** Account team. Produces `Toolkit_ComputerVisionOcrResults` - one row
per piece of on-screen text detected per frame.

## 4. OCR Cleaning
**Who:** Charlie / Becca / US team.
**File:** `OCR Cleaning/OcrCleaning_SQLScript.sql`

**What to actually do:**
1. Scope the script to the event(s) you're running (`#SportEvents`).
2. Look at the raw brand/asset list for the event (Stage 2A in the script).
3. For each brand/creative that needs recognising from on-screen text, add a
   row to the `Toolkit_OCR_Cleaning_Rules` insert block: `(Reported_brand,
   Reported_creative, AccessFlag)`. Leave `Reported_creative` blank if you just
   want brand-name matching; fill it in for a specific creative variant (we
   did this for "Werner Ladders" needing both "WERNER" and "LADDERS" to match).
4. Run Stage 3 of the script to apply the rules and check the coverage % at
   the end - anything still uncleaned needs either a new rule or is genuinely
   not a brand mention.

**Can run before annotations are done or new brand assets exist** - it only
needs raw OCR text, which doesn't depend on the visual recognition model
being retrained. Good use of time while waiting on Stage 6 below.

## 5. Post-Processing - THIS IS THE ONE THAT ACTUALLY MATTERS MOST
**Who:** Charlie / Nick.
**Main file to fill in:** `SportSight - Brand Asset Methodology - XXX.xlsx`,
sheet `BrandAssetMethodology`.

**What this file actually is:** one row per Brand+Asset combination (or Brand
alone, or Asset alone) that can appear in this event's footage. Seven flag
columns - `BrandAssetPairing`, `OCR`, `OCR_coordinates`, `IC`, `BrandOnly`,
`AssetOnly`, `Creative` - and the *exact combination* of which ones you set to
`1` (leave the rest blank) decides which of the 12 processing methods handles
that row. This routing is hardcoded in `SportsSight_FinalProcess_PDC.py`
(confirmed by reading it directly), so getting these flags right is the
actual job:

| Set these to 1 (rest blank) | Method that runs | When to use it |
|---|---|---|
| `BrandAssetPairing` | BrandAsset | Brand normally seen together with a specific asset (e.g. perimeter board) |
| `BrandAssetPairing` + `OCR` | BrandAsset OCR | Same, but the brand is recognised via on-screen text, not a logo image |
| `BrandAssetPairing` + `OCR` + `IC` | IC BrandAsset OCR | Same again, but only valid from a specific camera angle |
| `AssetOnly` | Asset Only | This asset always means the same brand regardless of detection (e.g. corner flag = sponsor X) |
| `AssetOnly` + `IC` | IC Asset | Asset-only, but angle-specific |
| `BrandOnly` | Brand Only | Rare - brand found with no asset context at all |
| `BrandOnly` + `IC` | IC Brand | Rare - brand only valid from a specific angle |
| `OCR` + `Creative` | Creative OCR | On-screen text identifies a specific creative, not just the brand |
| `OCR` + `IC` + `Creative` | IC Creative OCR | Creative OCR, angle-specific |
| `OCR` only (no `Creative`, no `IC`) | OCR Only | On-screen brand text, no creative distinction |
| `OCR` + `IC` (no `Creative`) | IC OCR | OCR Only, angle-specific |
| `OCR_coordinates` only (everything else blank) | TVGI detection | Fixed broadcast graphic - position/size/angle repeats across many frames, not a real sponsor asset |

**Before you can fill this in with confidence, you need:**
- The raw brand/asset list for this event (from RoboFlow output or Kishan's
  detected-assets Excel) so you know what actually appears in the footage
- Stage 4 (OCR Cleaning) already run, if any row uses `OCR`/`Creative` -
  the script reads `Toolkit_Cleaned_OCR_Results` directly and will
  hard-crash (`sys.exit(1)`) if that table's empty for this event

**Other things to check in `SportsSight_FinalProcess_PDC.py` before running,
per event:**
- `listOfEvents` - the actual event names for this run
- `valid_assets_list` - restrict to the real asset vocabulary for this venue
  (we found this was still carrying over Premier League asset names for
  Nordic Darts Masters that didn't apply - Trophy, Venue Barrier, etc. Verify
  against this event's actual assets, not the last event's list)
- `unassigned_brand_asset_map` / `unassigned_ic_asset_map` - only fill these
  in *after* reviewing real Missing_OCR output for this event. Don't carry
  over a previous event's fallback guesses (we removed BetMGM/Cinch/Fosters
  mappings that were specific to a different event and didn't apply here)
- `tvgi_candidate_brands` - only matters if any row uses `OCR_coordinates`

**Output:** `Toolkit_AzureModels_CombinedResults`, uploaded via an interactive
`Y/N` prompt at the end - it will NOT upload automatically, someone has to
run the script through to completion and confirm.

## 6. If needed: annotate model, rerun Stage 2 & 5
**Who:** Charlie / Nick, sending findings to Becca/Nick for re-annotation,
Chris F reruns RoboFlow if there's time.

**What to actually do:** after a run, check the `Missing_OCR` / unassigned
output from Stage 5. Anything substantial and recurring (a brand that never
matched, an asset that's misclassified) goes back to annotation, not into a
one-off fallback map in the methodology script - that just papers over it for
one event and creates exactly the kind of stale assumption that broke things
for Nordic Darts Masters.

---

## After post-processing: getting it into TvTrack (this isn't in the doc, but is real work)

Two more scripts per sport, e.g. for Matchroom/PDC:

**`SS PDC Exposure Cleaning and TvTrack Generation.sql`** (runs on Matchroom):
brand-name cleanup directly on `Toolkit_AzureModels_CombinedResults`, then
builds duration-clustered exposure segments and writes them to the sport DB's
own local `EXPOSURE` table.

**`SS PDC Move from AMCR to TvTrack.sql`** (runs on TvTrack): copies that local
Exposure data into `TvTrack.dbo.Exposure` - the actual thing the TvTrack app
reads for client delivery.

Watch for, based on real bugs we found and fixed this week:
- `ModelType` values need to match what the cleaning script's filters expect
  (`%Asset%`, `%OCR%`) - a method producing a different tag (e.g. `'Brand'`)
  gets silently dropped with no error. Worth a quick per-brand check after
  every run: does every brand in the raw data also show up in the final
  Exposure table?
- This is Azure SQL Database - `USE` statements to switch databases don't
  work at all, and temp tables don't survive a database switch. You need a
  genuinely separate connection for the sport DB vs TvTrack, and anything
  built in one (like `#SportEvents`) needs rebuilding in the other.
