# Mr Vegas Chest Branding - Detection Ceiling Investigation

Nordic Darts Masters 2026. Worked example of a real investigation this week -
kept here because the distinction between "theoretical ceiling" and "what the
methodology can actually credit" comes up any time a brand/asset pairing looks
badly down on last year, not just this one.

## The problem

Client-facing report showed Mr Vegas + Chest Branding at 3 ExpSecs for 2026 vs
8,246 for 2025 - a near-total collapse. Benchmark for this asset type
(irrespective of brand) is ~600 ExpSecs/hour; this event runs 8 hours, so the
target is ~4,800 ExpSecs.

## Four real bugs found and fixed (all in `SportsSight_FinalProcess_PDC.py` /
`SportsSight_functions_v4.py`)

1. `valid_assets_list` (hardcoded in the main script) was missing "Chest
   Branding - Cheerleader" - silently excluded from Missing_OCR recovery even
   when genuine overlap existed.
2. `brand_asset_ocr_proc` crashed (`KeyError: 'OCR_Text'`) whenever an event
   had zero BA/OCR overlaps at all - a pre-existing edge case that had never
   been exercised before.
3. **The big one**: `assetResults` (raw `SportsSight_Raw_Assets` data) was
   only ever fetched from SQL if some methodology row used `AssetOnly=1`.
   None do for this event. Missing_OCR needs this data and runs
   unconditionally whenever `missingOCRStep = True` - so it had been silently
   starved of data for every run of this event, regardless of anything else
   in the methodology sheet. Fixed by also fetching whenever
   `missingOCRStep` is enabled.
4. Self-inflicted mid-fix: the methodology sheet's `BrandAssetPairing` flag
   got accidentally cleared on 8 Mr Vegas rows. This routed them through the
   "OCR Only" method (`ocr_proc`), which merges purely on Brand with no
   spatial check at all - every Mr Vegas OCR hit got stamped onto all 8
   assets simultaneously (one frame showed 184 duplicate rows cycling
   through the same 8 assets 23 times). Caught via the CSV output and
   reverted.

## The diagnostic ceiling vs. what the pipeline actually credits

After the fixes, real output looked like a big win: Chest Branding - Player
went from ~8 raw joint-model detections to 1,082 final rows. But before
reporting that as "close to solved," worth checking against the actual
theoretical ceiling - not the output of any processing method, a direct SQL
check of genuine spatial overlap (IoU > 0.1) between raw Mr Vegas OCR boxes
and raw Chest Branding asset boxes, frame by frame, independent of any
methodology logic:

```sql
-- see ChestBranding_IoU_Check.sql in Post-Processing/Matchroom/PDC
-- joins Toolkit_Cleaned_OCR_Results (Brand='Mr Vegas') against
-- SportsSight_Raw_Assets (Asset LIKE 'Chest Branding%'), computes real IoU
```

Result: **1,611 distinct frames** genuinely overlap (2,553 total overlapping
pairs, since some frames have more than one). Since footage samples 1 frame =
1 second (confirmed via the Stage 4 clustering SQL treating frame number
directly as elapsed seconds), that's a hard ceiling of 1,611 seconds - no
methodology change can exceed this, because it's genuinely all the evidence
that exists in this year's footage.

**Why the production output (~700, after full duration-clustering) lands
below the 1,611 ceiling, and why that's correct, not a bug:** the ceiling
query only checks "does any overlap exist," with no arbitration. The real
matching logic (`Missing_OCR` / `match_missing_to_assets`) has to pick the
*single best* asset per frame, weighing confidence + distance + IoU together,
competing against every other asset also visible in that frame (Stage Table,
Back Wall, etc). If Mr Vegas is more confidently matched to Stage Table in a
wide shot that also happens to show a chest-branding region, that frame's
overlap is real but correctly loses to the stronger match elsewhere - it does
not get double-counted onto both.

**Do not "fix" this gap by loosening the methodology to accept any overlap
above the diagnostic threshold.** That would credit Chest Branding with
frames that are more legitimately Stage Table or Back Wall in the same shot -
inflating one number by quietly stealing from another. Not a defensible
exposure claim, same trap as blindly redistributing OCR volume across assets.

## Root cause confirmed: detection-model regression, not a processing gap

- Raw joint-model detections, Mr Vegas + Chest Branding: 2025 = 6,245
  (processed figure, true raw likely higher), 2026 = 108. ~58x collapse.
- Same asset, same event, other brands: BetVictor 612, BetMGM 334, Winmau
  185 raw detections - proves the model detects chest branding fine, just
  not Mr Vegas specifically.
- Mr Vegas + Stage Board also dropped, 10,530 -> ~1,007, ~10x - smaller but
  real, same category of issue.
- Rebecca confirmed independently (model inspection): none of the Mr Vegas
  chest-branding training annotations are in the training split, only
  validate/test. The model was never actually trained on this pairing.

## Status / next steps

- Current live pipeline output (`Toolkit_AzureModels_CombinedResults`, then
  `Matchroom.Exposure` after rerunning Exposure Cleaning Section 1+2 - see
  below) should land close to the 1,611 ceiling, not the original 3 seconds.
- `SS PDC Exposure Cleaning and TvTrack Generation.sql` was missing its own
  Section 2 (the actual `INSERT INTO EXPOSURE`) in this repo - restored from
  the clean `CR-ORIGIONAL-SS WST Exposure Cleaning and TvTrack Generation.sql`
  template, substituting nothing (same `#variables` values already built in
  Section 1: ClientID 3411, TvTrackProjectID 835).
- Reviewing with Charlie whether there's any other reasonable way to recover
  more within the 1,611 ceiling.
- Becca's asset detection model is currently retraining with better Mr Vegas
  chest-branding annotations - expect the *ceiling itself* to move up on a
  rerun once that's done, which is the only thing that actually closes the
  gap to the ~4,800 benchmark.
