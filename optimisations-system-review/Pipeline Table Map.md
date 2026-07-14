# SportsSight Pipeline - Table Map and Data Shapes

Verified by reading the actual scripts (not just the process doc). Each stage
lists what it reads/writes AND the actual column shape of the data at that
point, pulled directly from the real `SELECT`/`INSERT` statements in this repo.

## Stage 1: Footage capture + RoboFlow + OCR (Account team / Chris F)

Not something we've touched directly - upstream of everything below.

**Writes (raw model output):**

- `SportsSight_Raw_Assets` (confirmed - read in SportsSight_FinalProcess_PDC.py:239)
- `SportsSight_Raw_Brands` (confirmed - read in SportsSight_FinalProcess_PDC.py:252)
- `SportsSight_Raw_BrandAssets` (confirmed - read in SportsSight_FinalProcess_PDC.py:227)
- `SportsSight_Raw_Classifications` (confirmed - read in SportsSight_FinalProcess_PDC.py:264)
- `Toolkit_ComputerVisionOcrResults` (raw OCR text)

**`Toolkit_ComputerVisionOcrResults` shape** (columns seen used throughout OcrCleaning_SQLScript.sql):

```
Sport, SportsEvent, Filename, TEXT (the raw on-screen text string),
BoxTopLeftX, BoxTopLeftY, BoxTopRightX, BoxTopRightY,
BoxBottomRightX, BoxBottomRightY, BoxBottomLeftX, BoxBottomLeftY,
ImageWidth, ImageHeight, OcrLineId, Angle
```

i.e. one row = one piece of on-screen text detected in one frame, with its
bounding box corners (4 x,y pairs - it's a quadrilateral, not just a rectangle,
so it can represent rotated/skewed text) and the frame's image dimensions.

## Stage 2: OCR Cleaning (Charlie/Becca/US team)

File: `OCR Cleaning/OcrCleaning_SQLScript.sql`

**Reads:**

- `Toolkit_ComputerVisionOcrResults` (shape above)
- `Toolkit_OCR_Cleaning_Rules` - shape:
  ```
  Row_addition_source ('Human'|'Automated'), Row_manually_confirmed (bit),
  Reported_brand, Reported_creative, AccessFlag (event/run scope tag),
  Primary_Search_Term, SearchTermLen, exact_match_required (bit),
  substring_search_allowed (bit), Min_Levenshtein_Value (fuzzy-match threshold),
  other_on_screen_text_required
  ```

  i.e. one row = one rule: "if you see text matching X, it means brand Y
  (optionally creative Z)". `Min_Levenshtein_Value` controls fuzzy matching -
  shorter search terms get a stricter (higher) threshold so short strings
  don't false-match noise.

**Writes:**

- `Toolkit_Cleaned_OCR_Results` - shape (from the INSERT column list):
  ```
  id (NEWID), Sport, SportsEvent, Filename, original_text, cleaned_text,
  brand, Asset (always NULL here - OCR cleaning doesn't assign assets),
  creative, AccessFlag,
  BoxTopLeftX/Y, BoxTopRightX/Y, BoxBottomRightX/Y, BoxBottomLeftX/Y,
  topBrand_Asset_Creative_perFilename (always NULL here),
  ImageWidth, ImageHeight, OcrLineId, Angle
  ```

  Same shape as raw OCR plus the resolved `brand`/`creative` fields tacked on.
  `Asset` is deliberately left NULL - assigning an asset (which board/signage
  position) is Stage 3's job, not OCR cleaning's.
- `Toolkit_OCR_Cleaning_Rules` (adds new `'Automated'` rows as it discovers
  exact/fuzzy matches beyond the manually-entered `'Human'` ones)

**Does NOT touch:** `Toolkit_AzureModels_CombinedResults` (only has a few unrelated
cleanup `DELETE`s against it near the end of the script).

**Key implication:** independent of "new brand annotations" being done - only
needs raw OCR text to exist. Can run ahead of post-processing as prep work.

## Stage 3: Post-Processing (Charlie/Nick)

Files: `SportsSight_FinalProcess_XXX.py` (+ `SportsSight_functions_XXX.py`,
methodology `.xlsx`, `SportsSight_OCR_coordinates.py`)

**Reads:**

- `SportsSight_Raw_Assets` / `_Brands` / `_BrandAssets` / `_Classifications`
  (all filtered `WHERE SportsEvent = '{match}'` - raw model detections, one
  row per detected object/brand/classification per frame, with its own
  confidence score and box coordinates per table)
- `Toolkit_Cleaned_OCR_Results` (shape above - explicit `sys.exit(1)` if empty
  for any OCR-dependent method, so Stage 2 is a hard prerequisite for those)

**Sub-step: TVGI / OCR-coordinate detection** (`SportsSight_OCR_coordinates.py`,
invoked from FinalProcess when `OCR_coordinates=1` in the methodology sheet):
detects fixed broadcast graphics (TVGIs) by clustering OCR hits that recur at
the *same screen position, size, and angle* across many consecutive frames -
a real sponsor logo moves/disappears, a baked-in broadcast graphic doesn't.
Produces a `TVGI_detection_report_{sport}_{dateStamp}.xlsx` for manual review
(a human confirms which clusters are real TVGIs in the `Accepted_clusters`
sheet) before being merged back in.

**Writes:**

- `Toolkit_AzureModels_CombinedResults` via `upload_to_sql()` (identical
  pattern in all 4 account scripts: PDC, WST, WSL, ECB), gated behind an
  interactive `Y/N` confirmation prompt.

**`Toolkit_AzureModels_CombinedResults` shape** (`results_columns` constant,
`SportsSight_OCR_coordinates.py:11` - this is the unified schema every method,
whether OCR-based or model-based, gets reshaped into before upload):

```
ModelType, Guid_ID, Sport, Event, Filename, Brand, Asset,
X1, Y1, X2, Y2, X3, Y3, X4, Y4 (bounding box, 4 corners),
Probability, Iteration, AcceptedExposure, Original_Tag,
Original_BrandMessaging, Original_Asset, ScreenSize, ScreenLocation
```

`ModelType` is the field that tripped us up for Nordic Darts Masters - it's
what tags a row as e.g. `'Asset'`, `'OCR'`, or `'Brand'` depending on which of
the 12 methods (BrandAsset, OCR Only, Asset Only, IC variants, etc.) produced
it. Downstream cleaning/grouping scripts filter on this field, so any method
that emits a `ModelType` value those filters don't expect will get silently
dropped - as happened with Winmau/Smart Water.

## Stage 4: Per-sport Exposure Cleaning (e.g. `SS PDC Exposure Cleaning and TvTrack Generation.sql`)

Runs on the sport's own database (e.g. Matchroom for PDC/WST).

**Reads/writes:**

- `Toolkit_AzureModels_CombinedResults` (shape above - ad-hoc brand-name
  `UPDATE`s for cleanup, then read to build `#frame_results`/`#duration_grouped`)

**`#duration_grouped` shape** (the output of collapsing per-frame rows into
duration-clustered exposure segments - this is the last stop before it looks
like "an exposure" rather than "a detection"):

```
event, brand, touchpoint, timeonscreen (start time), duration (seconds),
screensize, start_frame, total_hits, CountA-E (per-screen-zone hit counts),
avg_hits (computed), loc_single (computed - the dominant screen zone A-E)
```

**Reads (via linked names):**

- `dbo.[CMGSQLNODE01\FSE.PhotoTextTrack.Brands]`, `...Touchpoints`, `...TP_Client`
- `dbo.[CMGSQLNODE01\FSE.TvTrack.Programme]` (linked into TvTrack from the sport DB)

**Writes:**

- `EXPOSURE` (the sport DB's own *local* Exposure table - NOT TvTrack's) - shape:
  ```
  BrandID, TP_ID, SubTP_ID, StartTime, EndTime, ScreenLocation, ScreenSize,
  Duration, ProjectID, ProgrammeID, ProgDetID, AvgHits, TotalHits
  ```

  Note `ProgrammeID` here is already TvTrack's `dbo.Programme.ProgID` value
  (joined in via the linked `TvTrack.Programme` proxy at write time) - this is
  the fact that let us simplify the slow candidate-search in Stage 5.

## Stage 5: AMCR to TvTrack move (e.g. `SS PDC Move from AMCR to TvTrack.sql`)

Runs on TvTrack.

**Reads (via linked name):**

- `dbo.[CMGSQLNODE01\FSE.Matchroom.Exposure]` (Stage 4's output, same shape as above)

**Reads/writes:**

- `dbo.Programme` (TvTrack) - shape: `ProgID, PR_Name, StartTime, EndTime, ProjectID, Uploaded`

**Writes:**

- `dbo.Exposure` (TvTrack) - same shape as the sport DB's local `EXPOSURE` table
  above, minus the linked-name indirection - this is what actually shows up in
  the TvTrack app for client delivery.

## Full chain, end to end

```
SportsSight_Raw_Assets/Brands/BrandAssets/Classifications  ──┐
Toolkit_ComputerVisionOcrResults ──► OcrCleaning_SQLScript.sql ──► Toolkit_Cleaned_OCR_Results
  (raw OCR text + box coords)         (Human/Automated rules)      (+ resolved brand/creative)
                                                                              │
                                                                              ▼
                                    SportsSight_FinalProcess_XXX.py (+ OCR_coordinates.py for TVGI)
                                    reads raw model tables + cleaned OCR, runs 12 classification
                                    methods, reshapes everything into one common schema
                                                                              │
                                                                              ▼ (Y/N confirm)
                                                    Toolkit_AzureModels_CombinedResults
                                                    (ModelType, Brand, Asset, box coords, Probability...)
                                                                              │
                                                                              ▼
                                    SS <Sport> Exposure Cleaning and TvTrack Generation.sql
                                    brand-name fixes, then collapse per-frame rows into
                                    duration-clustered #duration_grouped exposure segments
                                                                              │
                                                                              ▼
                                          <SportDB>.dbo.EXPOSURE (local) - BrandID, TP_ID,
                                          StartTime, EndTime, Duration, ProgrammeID(=TvTrack ProgID)...
                                                                              │
                                                                              ▼ (linked proxy)
                                    SS <Sport> Move from AMCR to TvTrack.sql (on TvTrack)
                                    direct join on ProgrammeID = TvTrack Programme.ProgID
                                                                              │
                                                                              ▼
                                                                   TvTrack.dbo.Exposure (final)
```

## Known gaps / things worth confirming with the team

- `SportsSight Process Overview.docx` describes ECB's OCR cleaning rules as
  approved via `OCR_Cleaning_Terms_YYYY.xlsx` (Human -> Automated tier, with an
  Excel sign-off step). The actual script has the Human/Automated tiering in
  code (`Row_addition_source`), but the Excel approval step itself isn't
  visible in the script - rules get inserted via manual `INSERT` statements
  someone edits directly. Worth confirming whether Excel approval happens
  separately outside the script, or isn't actually used day-to-day.
- The raw `SportsSight_Raw_*` tables (Stage 1 output) are populated by
  RoboFlow - we haven't seen the actual RoboFlow-to-SQL upload code in this
  repo, so we can't confirm their exact column shapes independently, only
  that these four table names are real (confirmed via the Python read calls).
