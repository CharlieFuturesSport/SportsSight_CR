-- Genuine spatial-overlap check: Mr Vegas OCR text vs Chest Branding asset boxes
-- Nordic Darts Masters 2026, both days
-- IoU threshold matches the 0.1 used elsewhere in the pipeline (find_ba_ocr_overlaps)

;WITH OcrBoxes AS (
    SELECT
        RIGHT(Filename, 10) AS FrameKey,
        BoxTopLeftX AS OX1, BoxTopLeftY AS OY1,
        BoxBottomRightX AS OX2, BoxBottomRightY AS OY2
    FROM dbo.Toolkit_Cleaned_OCR_Results
    WHERE SportsEvent IN ('20260605_PDC_NORD_Day1Evening/', '20260606_PDC_NORD_Day2Evening/')
      AND Brand = 'Mr Vegas'
),
AssetBoxes AS (
    SELECT
        RIGHT(Image, 10) AS FrameKey,
        TopLeftX AS AX1, TopLeftY AS AY1,
        BottomRightX AS AX2, BottomRightY AS AY2
    FROM dbo.SportsSight_Raw_Assets
    WHERE SportsEvent IN ('20260605_PDC_NORD_Day1Evening', '20260606_PDC_NORD_Day2Evening')
      AND Asset LIKE 'Chest Branding%'
),
Pairs AS (
    SELECT
        O.FrameKey,
        CASE WHEN
            (CASE WHEN O.OX2 < A.AX2 THEN O.OX2 ELSE A.AX2 END) - (CASE WHEN O.OX1 > A.AX1 THEN O.OX1 ELSE A.AX1 END) > 0
        AND (CASE WHEN O.OY2 < A.AY2 THEN O.OY2 ELSE A.AY2 END) - (CASE WHEN O.OY1 > A.AY1 THEN O.OY1 ELSE A.AY1 END) > 0
        THEN
            ((CASE WHEN O.OX2 < A.AX2 THEN O.OX2 ELSE A.AX2 END) - (CASE WHEN O.OX1 > A.AX1 THEN O.OX1 ELSE A.AX1 END))
          * ((CASE WHEN O.OY2 < A.AY2 THEN O.OY2 ELSE A.AY2 END) - (CASE WHEN O.OY1 > A.AY1 THEN O.OY1 ELSE A.AY1 END))
        ELSE 0 END AS IntersectionArea,
        ABS(O.OX2 - O.OX1) * ABS(O.OY2 - O.OY1) AS OcrArea,
        ABS(A.AX2 - A.AX1) * ABS(A.AY2 - A.AY1) AS AssetArea
    FROM OcrBoxes O
    INNER JOIN AssetBoxes A ON O.FrameKey = A.FrameKey
),
Scored AS (
    SELECT *,
        CASE WHEN (OcrArea + AssetArea - IntersectionArea) > 0
             THEN CAST(IntersectionArea AS FLOAT) / (OcrArea + AssetArea - IntersectionArea)
             ELSE 0 END AS IoU
    FROM Pairs
)
SELECT
    COUNT(DISTINCT FrameKey) AS DistinctFrames_GenuineOverlap,
    COUNT(*) AS TotalOverlappingPairs
FROM Scored
WHERE IoU > 0.1;
