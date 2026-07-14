-- OCR Cleaning
-- Currently scoped to: Blast (AccessFlag = 'ecb_2026'), all 11 checklist match IDs

-- ============================================================
-- STAGE 1: Build event list for this run
-- ============================================================

DROP TABLE IF EXISTS #BlastMatches;
CREATE TABLE #BlastMatches
(
    MatchID INT PRIMARY KEY,
    MatchLabel VARCHAR(120) NOT NULL
);

INSERT INTO #BlastMatches (MatchID, MatchLabel)
VALUES
(12729, '220526 Mens Blast Group Som v Ham'),
(12730, '220526 Womens Blast Group Som v Ham'),
(12731, '230526 Mens Blast Group Gla v Glo'),
(12732, '240526 Mens Blast Group Mid v Sur'),
(12733, '260526 Mens Blast Group Ham v Ess'),
(12734, '260526 Womens Blast Group Ham v Ess'),
(12735, '270526 Mens Blast Group Lei v Der'),
(12736, '290526 Mens Blast Group Wor v War'),
(12737, '300526 Mens Blast Group Sus v Mid'),
(12738, '310526 Mens Blast Group War v Nor'),
(12739, '030626 Mens Blast Group Sur v Mid');

DROP TABLE IF EXISTS #SportEvents;
CREATE TABLE #SportEvents
(
    ID INT IDENTITY(1,1),
    SportsEvent VARCHAR(255)
);

-- Resolve actual event names from raw OCR data using the match IDs above.
INSERT INTO #SportEvents (SportsEvent)
SELECT DISTINCT
    CASE
        WHEN RIGHT(RAW.SportsEvent, 1) = '/' THEN RAW.SportsEvent
        ELSE RAW.SportsEvent + '/'
    END
FROM #BlastMatches M
JOIN Toolkit_ComputerVisionOcrResults RAW
    ON RAW.SportsEvent LIKE CAST(M.MatchID AS VARCHAR(10)) + '\_%' ESCAPE '\'
WHERE LOWER(RAW.SportsEvent) LIKE '%blast%';

-- Check raw OCR results per resolved event.
SELECT RAW.SportsEvent, COUNT(*) AS Cnt
FROM Toolkit_ComputerVisionOcrResults RAW
JOIN #SportEvents E
    ON RAW.SportsEvent = E.SportsEvent
GROUP BY RAW.SportsEvent
ORDER BY RAW.SportsEvent;

-- Any match IDs that did NOT resolve to an event name - investigate before continuing.
SELECT M.MatchID, M.MatchLabel
FROM #BlastMatches M
WHERE NOT EXISTS
(
    SELECT 1
    FROM #SportEvents E
    WHERE E.SportsEvent LIKE CAST(M.MatchID AS VARCHAR(10)) + '\_%' ESCAPE '\'
)
ORDER BY M.MatchID;

-- ============================================================
-- STAGE 2: Review existing cleaning rules
-- ============================================================

-- Stage 2A: Check existing Human rules for this AccessFlag
SELECT *
FROM Toolkit_OCR_cleaning_rules
WHERE AccessFlag = 'ecb_2026'
  AND Row_addition_source = 'Human'
ORDER BY Reported_brand;

-- Stage 2B: Add new Human rules (edit only VALUES rows)
-- Manual fields per row:
--   1) Reported_brand
--   2) Reported_creative (blank '' allowed)
--   3) AccessFlag
-- Fixed fields:
--   Row_addition_source = 'Human'
--   Row_manually_confirmed = 1
--   exact_match_required = 0
--   substring_search_allowed = 1
--   other_on_screen_text_required = ''
-- Derived fields:
--   Primary_Search_Term = IF(Reported_creative blank, Reported_brand, Reported_creative)
--   SearchTermLen = LEN(Primary_Search_Term)
--   min_levenshtein_value = IF(LEN(Primary_Search_Term)<3,1,0.75-(LEN(Primary_Search_Term)*0.0075))
--
-- NOTE: the full current Blast brand set (55 brands across all 11 matches) is
-- already seeded via OCR Cleaning/Blast_All_Games_OCR_Cleaning.sql, Stage 1B.
-- Use this block only for brands discovered *after* that, e.g. from reviewing
-- Stage 3.3 MANUAL_REVIEW output below. NOT_EXISTS-guarded, safe to re-run.

INSERT INTO Toolkit_OCR_Cleaning_Rules
SELECT
    'Human',
    1,
    I.Reported_brand,
    NULLIF(I.Reported_creative, ''),
    I.AccessFlag,
    X.Primary_Search_Term,
    LEN(X.Primary_Search_Term),
    0,
    1,
    CAST(
        CASE
            WHEN LEN(X.Primary_Search_Term) < 3 THEN 1
            ELSE 0.75 - (LEN(X.Primary_Search_Term) * 0.0075)
        END AS DECIMAL(10,4)
    ),
    ''
FROM
(
    VALUES
        -- Reported_brand, Reported_creative, AccessFlag
        -- Both confirmed missing rules despite appearing in an already-processed
        -- match (12732) - see Blast_Brand_Detection_Check.sql / Blast_All_Current_Rules.sql
        ('IBC', '', 'ecb_2026'),
        ('Ark Build', '', 'ecb_2026'),
        ('London Pride', 'Pride', 'ecb_2026')
        -- Add any further newly-discovered Blast brands here as they come up.
) I (Reported_brand, Reported_creative, AccessFlag)
CROSS APPLY
(
    SELECT
        CASE
            WHEN NULLIF(I.Reported_creative, '') IS NULL THEN I.Reported_brand
            ELSE I.Reported_creative
        END AS Primary_Search_Term
) X
WHERE NOT EXISTS
(
    SELECT 1
    FROM Toolkit_OCR_Cleaning_Rules R
    WHERE R.AccessFlag = I.AccessFlag
    AND R.Primary_Search_Term = X.Primary_Search_Term
);

SELECT
    COUNT(*) AS HumanRuleCount
FROM Toolkit_OCR_Cleaning_Rules
WHERE AccessFlag = 'ecb_2026'
AND Row_addition_source = 'Human';

SELECT
    Reported_brand,
    Primary_search_term,
    Min_Levenshtein_Value
FROM Toolkit_OCR_Cleaning_Rules
WHERE AccessFlag = 'ecb_2026'
AND Row_addition_source = 'Human'
ORDER BY Reported_brand, Primary_search_term;

-- ============================================================
-- STAGE 3: Apply OCR cleaning pipeline
-- ============================================================

DECLARE @specificAccessFlag VARCHAR(100) = 'ecb_2026';
DECLARE @autoAcceptMaxOcrCount INT = 3;

-- ========= RUN KPIs (before/after) =========

-- 1) Scope check
SELECT 'Scope' AS section, SportsEvent
FROM #SportEvents;

-- 2) Raw detections in scope
SELECT
    'Raw detections' AS metric,
    COUNT(*) AS value
FROM Toolkit_ComputerVisionOcrResults RAW
WHERE RAW.SportsEvent IN (SELECT SportsEvent FROM #SportEvents);

-- 3) Cleaned rows already in scope (before run if you execute this first)
SELECT
    'Cleaned rows' AS metric,
    COUNT(*) AS value
FROM Toolkit_Cleaned_OCR_Results C
WHERE C.AccessFlag = @specificAccessFlag
  AND C.SportsEvent IN (SELECT SportsEvent FROM #SportEvents);

-- 4) Remaining unmatched raw rows
SELECT
    'Uncleaned remaining' AS metric,
    COUNT(*) AS value
FROM Toolkit_ComputerVisionOcrResults RAW
LEFT JOIN Toolkit_Cleaned_OCR_Results C
    ON RAW.OcrLineId = C.OcrLineID
   AND C.AccessFlag = @specificAccessFlag
WHERE RAW.SportsEvent IN (SELECT SportsEvent FROM #SportEvents)
  AND C.ID IS NULL;

-- 5) Coverage %
SELECT
    'Coverage %' AS metric,
    CAST(
      100.0 * SUM(CASE WHEN C.ID IS NOT NULL THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0)
      AS DECIMAL(6,2)
    ) AS value
FROM Toolkit_ComputerVisionOcrResults RAW
LEFT JOIN Toolkit_Cleaned_OCR_Results C
    ON RAW.OcrLineId = C.OcrLineID
   AND C.AccessFlag = @specificAccessFlag
WHERE RAW.SportsEvent IN (SELECT SportsEvent FROM #SportEvents);

-- 6) Distinct brands cleaned so far, this scope
SELECT DISTINCT brand FROM Toolkit_Cleaned_OCR_Results C
WHERE C.AccessFlag = @specificAccessFlag
AND C.SportsEvent IN (SELECT SportsEvent FROM #SportEvents)
ORDER BY 1;

-- --------------------
-- STEP 3.1: Insert exact Human matches
-- --------------------

INSERT INTO Toolkit_Cleaned_OCR_Results
SELECT --TOP 100
       NEWID() AS id,
       Sport,
       SportsEvent,
       [Filename],
       TEXT AS original_text,
       CASE
           WHEN reported_creative IS NULL
                OR reported_creative = '' THEN
               reported_brand
           ELSE
               reported_creative
       END AS cleaned_text,
       Reported_brand AS brand,
       NULL AS Asset,
       Reported_creative AS creative,
       AccessFlag,
       [BoxTopLeftX],
       [BoxTopLeftY],
       [BoxTopRightX],
       [BoxTopRightY],
       [BoxBottomRightX],
       [BoxBottomRightY],
       [BoxBottomLeftX],
       [BoxBottomLeftY],
       NULL AS [topBrand_Asset_Creative_perFilename],
       ImageWidth,
       ImageHeight,
       OcrLineId,
       Angle
FROM (
            SELECT
               RAW.*
            FROM Toolkit_ComputerVisionOcrResults RAW
               LEFT JOIN Toolkit_Cleaned_OCR_Results CLEAN
                  ON RAW.OcrLineId = CLEAN.OcrLineID
                  AND CLEAN.AccessFlag = @specificAccessFlag
            WHERE RAW.SportsEvent in ( SELECT SportsEvent FROM #SportEvents )
            AND CLEAN.ID IS NULL
    ) RAW
    INNER JOIN Toolkit_OCR_cleaning_rules RULES
        ON (RAW.TEXT = RULES.Primary_search_term)
           AND Row_manually_confirmed = 1
           AND Row_addition_source = 'Human'
           AND Reported_brand <> 'IGNORE'
           AND AccessFlag = @specificAccessFlag
           AND (other_on_screen_text_required = '');

-- --------------------
-- STEP 3.2: Insert exact Automated matches
-- --------------------

insert into Toolkit_Cleaned_OCR_Results
SELECT --TOP 100
    NEWID() AS id,
    Sport,
    SportsEvent,
    [Filename],
    TEXT AS original_text,
    CASE
        WHEN reported_creative IS NULL
             OR reported_creative = '' THEN
            reported_brand
        ELSE
            reported_creative
    END AS cleaned_text,
    Reported_brand AS brand,
    NULL AS Asset,
    Reported_creative AS creative,
    AccessFlag,
    [BoxTopLeftX],
    [BoxTopLeftY],
    [BoxTopRightX],
    [BoxTopRightY],
    [BoxBottomRightX],
    [BoxBottomRightY],
    [BoxBottomLeftX],
    [BoxBottomLeftY],
    NULL AS [topBrand_Asset_Creative_perFilename],
    ImageWidth,
    ImageHeight,
    OcrLineId,
    Angle
FROM (
            SELECT
               RAW.*
            FROM Toolkit_ComputerVisionOcrResults RAW
               LEFT JOIN Toolkit_Cleaned_OCR_Results CLEAN
                  ON RAW.OcrLineId = CLEAN.OcrLineID
                  AND CLEAN.AccessFlag = @specificAccessFlag
            WHERE RAW.SportsEvent in ( SELECT SportsEvent FROM #SportEvents )
            AND CLEAN.ID IS NULL
         ) RAW
    INNER JOIN Toolkit_OCR_cleaning_rules RULES
        ON (RAW.TEXT = RULES.Primary_search_term)
           AND Row_manually_confirmed = 1
           AND Row_addition_source = 'Automated'
           AND exact_match_required = 1
           AND substring_search_allowed = 0
           AND Reported_brand <> 'IGNORE'
           AND AccessFlag = @specificAccessFlag
           AND (other_on_screen_text_required = '')
WHERE SportsEvent IN
      (
          SELECT SportsEvent FROM #SportEvents
      );

-- --------------------
-- STEP 3.3: Generate, review, and apply new exact-match terms
-- --------------------

-- IDENTIFY SEARCH TERMS
DROP TABLE IF EXISTS #Stage33Candidates;

;WITH PendingOCR AS
(
    SELECT
        OCR.TEXT,
        COUNT(OCR.OcrLineId) AS ocrCount
    FROM Toolkit_ComputerVisionOcrResults OCR
        LEFT JOIN Toolkit_Cleaned_OCR_Results Inserted
            ON OCR.OcrLineId = Inserted.OcrLineId
            AND Inserted.AccessFlag = @specificAccessFlag
    WHERE OCR.SportsEvent IN
          (
              SELECT SportsEvent FROM #SportEvents
          )
          AND Inserted.OcrLineID IS NULL
    GROUP BY OCR.TEXT
),
UnseenOCR AS
(
    SELECT
        PendingOCR.TEXT,
        PendingOCR.ocrCount
    FROM PendingOCR
        LEFT JOIN [dbo].[Toolkit_OCR_cleaning_rules] CurrentOCR
            ON PendingOCR.TEXT = CurrentOCR.Primary_Search_Term
            AND CurrentOCR.AccessFlag = @specificAccessFlag
    WHERE CurrentOCR.ID IS NULL
),
CompBrands AS
(
    SELECT
        [Primary_search_term],
        [Min_Levenshtein_Value],
        [Reported_brand],
        [Reported_creative],
        [AccessFlag]
    FROM [dbo].[Toolkit_OCR_cleaning_rules] rules
    WHERE [Min_Levenshtein_Value] < 1
          AND reported_brand <> 'IGNORE'
          AND [exact_match_required] <> 1
            AND AccessFlag = @specificAccessFlag
          AND Row_addition_source = 'Human'
),
RankedMatches AS
(
    SELECT
        UnseenOCR.TEXT,
        UnseenOCR.ocrCount,
        CompBrands.Reported_brand,
        CompBrands.Reported_creative,
        CompBrands.AccessFlag,
        CAST(([dbo].Toolkit_FUNC_LevenshteinDistanceAsPercentage(UnseenOCR.TEXT, CompBrands.Primary_search_term)) / 100.0 AS DECIMAL(10,4)) AS PercentDistance,
        CompBrands.Min_Levenshtein_Value,
        ROW_NUMBER() OVER
        (
            PARTITION BY UnseenOCR.TEXT
            ORDER BY ([dbo].Toolkit_FUNC_LevenshteinDistanceAsPercentage(UnseenOCR.TEXT, CompBrands.Primary_search_term)) DESC,
                     CompBrands.Min_Levenshtein_Value DESC,
                     CompBrands.Reported_brand
        ) AS MatchRank
    FROM UnseenOCR
        INNER JOIN CompBrands
            ON ([dbo].Toolkit_FUNC_LevenshteinDistanceAsPercentage(UnseenOCR.TEXT, CompBrands.Primary_search_term)) / 100.0 >= CompBrands.Min_Levenshtein_Value
)
SELECT
    Reported_brand,
    Reported_creative,
    AccessFlag,
    TEXT AS Primary_Search_Term,
    LEN(TEXT) AS SearchTermLen,
    1 AS exact_match_required,
    0 AS substring_search_allowed,
    1 AS min_levenshtein_value,
    ocrCount,
    PercentDistance,
    CASE
        WHEN ocrCount <= @autoAcceptMaxOcrCount THEN 'AUTO_ACCEPT'
        ELSE 'MANUAL_REVIEW'
    END AS ReviewAction
INTO #Stage33Candidates
FROM RankedMatches
WHERE MatchRank = 1;

-- 3.3.1 Generate AUTO_ACCEPT rows
DROP TABLE IF EXISTS #Stage33AutoAcceptToInsert;
SELECT
    C.Reported_brand,
    C.Reported_creative,
    C.AccessFlag,
    C.Primary_Search_Term,
    C.SearchTermLen,
    C.exact_match_required,
    C.substring_search_allowed,
    C.min_levenshtein_value,
    C.ocrCount,
    C.PercentDistance,
    C.ReviewAction
INTO #Stage33AutoAcceptToInsert
FROM #Stage33Candidates C
WHERE C.ReviewAction = 'AUTO_ACCEPT'
AND NOT EXISTS
(
    SELECT 1
    FROM Toolkit_OCR_Cleaning_Rules R
    WHERE R.AccessFlag = C.AccessFlag
    AND R.Primary_Search_Term = C.Primary_Search_Term
);

-- Step 3.3.1A: Review AUTO_ACCEPT rows
SELECT
    '' AS ID,
    'Automated' AS Row_addition_source,
    1 AS Row_Manually_Confirmed,
    Reported_brand,
    Reported_creative,
    AccessFlag,
    Primary_Search_Term,
    SearchTermLen,
    exact_match_required,
    substring_search_allowed,
    min_levenshtein_value,
    ocrCount,
    PercentDistance,
    ReviewAction
FROM #Stage33AutoAcceptToInsert
ORDER BY ocrCount DESC, Reported_brand, PercentDistance DESC;

-- Step 3.3.1B: Insert AUTO_ACCEPT rows into Cleaning Rules
INSERT INTO Toolkit_OCR_Cleaning_Rules
SELECT
   'Automated',
   1,
   A.Reported_brand,
   A.Reported_creative,
   A.AccessFlag,
   A.Primary_Search_Term,
    A.SearchTermLen,
   A.exact_match_required,
   A.substring_search_allowed,
   A.min_levenshtein_value,
   ''
FROM #Stage33AutoAcceptToInsert A;

-- 3.3.2 Generate MANUAL_REVIEW rows (> @autoAcceptMaxOcrCount OCR count)
DROP TABLE IF EXISTS #Stage33ManualReviewToInsert;
SELECT
    C.Reported_brand,
    C.Reported_creative,
    C.AccessFlag,
    C.Primary_Search_Term,
    C.SearchTermLen,
    C.exact_match_required,
    C.substring_search_allowed,
    C.min_levenshtein_value,
    C.ocrCount,
    CAST('PENDING' AS VARCHAR(10)) AS Decision
INTO #Stage33ManualReviewToInsert
FROM #Stage33Candidates C
WHERE C.ReviewAction = 'MANUAL_REVIEW'
AND NOT EXISTS
(
    SELECT 1
    FROM Toolkit_OCR_Cleaning_Rules R
    WHERE R.AccessFlag = C.AccessFlag
    AND R.Primary_Search_Term = C.Primary_Search_Term
);

-- Step 3.3.2A: Review pending MANUAL_REVIEW rows (> @autoAcceptMaxOcrCount OCR count)
SELECT
    '' AS ID,
    'Automated' AS Row_addition_source,
    H.Reported_brand,
    H.Reported_creative,
    H.Primary_Search_Term,
    H.ocrCount
FROM #Stage33ManualReviewToInsert H
WHERE H.Decision = 'PENDING'
ORDER BY
    H.Reported_brand,
    H.Reported_creative,
    H.ocrCount DESC,
    H.Primary_Search_Term;


SELECT TOP 15
    SportsEvent,
    Filename,
    'https://sportssight-imagereview-fxgwfpddc4ewdfht.uksouth-01.azurewebsites.net/DatabaseBrandAssets'
    + '?FolderName=cricket&DatabaseName=ECB'
    + '&SportsEvent='
    + REPLACE(SportsEvent, '/', '')
    + '&ImageName='
    + SUBSTRING(
        Filename,
        CHARINDEX('/', Filename) + 1,
        LEN(Filename)
      ) AS ReviewUrl
FROM Toolkit_ComputerVisionOcrResults
WHERE TEXT = 'woodland'
AND SportsEvent LIKE '%Blast%'
ORDER BY NEWID();


-- Step 3.3.2B: Fast manual review ordered by brand/creative
-- 1) Reject specific terms after review.
-- Tip: paste quoted Primary_Search_Term values into the IN list below (one per line).



-- Quick counts by decision

UPDATE #Stage33ManualReviewToInsert
SET Decision = 'REJECT'
WHERE Decision = 'PENDING'
AND Primary_Search_Term IN
(
    'CIBC',
    'LANDSCAPES',
    'nice',
    'MIKE',
    'LIKE',
    'nick',
    'PRICE',
    'PRIME',
    'RIDE',
    'PRIZE',
    'gut health'
);


SELECT Decision, COUNT(*) AS Cnt
FROM #Stage33ManualReviewToInsert
GROUP BY Decision;

-- What's been rejected (should be your 11 terms)
SELECT Reported_brand, Reported_creative, Primary_Search_Term, ocrCount
FROM #Stage33ManualReviewToInsert
WHERE Decision = 'REJECT'
ORDER BY ocrCount DESC;

-- What's still PENDING (about to default to ACCEPT — should be the other 266)
SELECT Reported_brand, Reported_creative, Primary_Search_Term, ocrCount
FROM #Stage33ManualReviewToInsert
WHERE Decision = 'PENDING'
ORDER BY ocrCount DESC;


-- 2) Accept everything else that remains pending.
UPDATE H
SET
    H.Decision = 'ACCEPT'
FROM #Stage33ManualReviewToInsert H
WHERE H.Decision = 'PENDING';

-- Re-run Step 3.3.2A any time before accepting remainder.

-- Step 3.3.3: Insert MANUAL_REVIEW rows that were ACCEPTED
INSERT INTO Toolkit_OCR_Cleaning_Rules
SELECT
    'Automated',
    1,
    H.Reported_brand,
    H.Reported_creative,
    H.AccessFlag,
    H.Primary_Search_Term,
    H.SearchTermLen,
    H.exact_match_required,
    H.substring_search_allowed,
    H.min_levenshtein_value,
    ''
FROM #Stage33ManualReviewToInsert H
WHERE H.Decision = 'ACCEPT';

-- Step 3.3.4: Rerun AUTOMATED exact-match insert after new rules were added
insert into Toolkit_Cleaned_OCR_Results
SELECT-- TOP 100
    NEWID() AS id,
    Sport,
    SportsEvent,
    [Filename],
    TEXT AS original_text,
    CASE
        WHEN reported_creative IS NULL
             OR reported_creative = '' THEN
            reported_brand
        ELSE
            reported_creative
    END AS cleaned_text,
    Reported_brand AS brand,
    NULL AS Asset,
    Reported_creative AS creative,
    AccessFlag,
    [BoxTopLeftX],
    [BoxTopLeftY],
    [BoxTopRightX],
    [BoxTopRightY],
    [BoxBottomRightX],
    [BoxBottomRightY],
    [BoxBottomLeftX],
    [BoxBottomLeftY],
    NULL AS [topBrand_Asset_Creative_perFilename],
    ImageWidth,
    ImageHeight,
    OcrLineId,
    Angle
FROM (
            SELECT
               RAW.*
            FROM Toolkit_ComputerVisionOcrResults RAW
               LEFT JOIN Toolkit_Cleaned_OCR_Results CLEAN
                  ON RAW.OcrLineId = CLEAN.OcrLineID
                        AND CLEAN.AccessFlag = @specificAccessFlag
            WHERE RAW.SportsEvent in ( SELECT SportsEvent FROM #SportEvents )
            AND CLEAN.ID IS NULL
         ) RAW
    INNER JOIN Toolkit_OCR_cleaning_rules RULES
        ON (RAW.TEXT = RULES.Primary_search_term)
           AND Row_manually_confirmed = 1
           AND Row_addition_source = 'Automated'
           AND exact_match_required = 1
           AND substring_search_allowed = 0
           AND Reported_brand <> 'IGNORE'
           AND AccessFlag = @specificAccessFlag
           AND (other_on_screen_text_required = '')
WHERE SportsEvent IN
      (
          SELECT SportsEvent FROM #SportEvents
      );

-- --------------------
-- STEP 3.4: Insert substring matches (Human rules)
-- --------------------

--MANUAL AS PART OF A STRING
INSERT INTO Toolkit_Cleaned_OCR_Results
    SELECT --TOP 100
        NEWID() as id,
        Sport, SportsEvent, [Filename],
        Text as original_text,
        CASE
           WHEN reported_creative IS NULL
            OR reported_creative = '' THEN
               reported_brand
           ELSE
               reported_creative
       END AS cleaned_text,
        Reported_brand as brand,
        NULL AS Asset,
        Reported_creative as creative,
        AccessFlag,
       (RAW.[BoxTopLeftX]
        + ((RAW.[BoxTopRightX] - RAW.[BoxTopLeftX])
           * ((CHARINDEX(RULES.[Primary_search_term], RAW.TEXT) - 1) / cast(LEN(RAW.TEXT) AS FLOAT))
          )
       ) AS [BoxTopLeftX],
       RAW.[BoxTopLeftY],
       RAW.[BoxTopRightX]
       - ((RAW.[BoxTopRightX] - RAW.[BoxTopLeftX])
          * (1
             - (((LEN(RULES.[Primary_search_term]) + (CHARINDEX(RULES.[Primary_search_term], RAW.TEXT) - 1))
                 / cast(LEN(RAW.TEXT) AS FLOAT)
                )
               )
            )
         ) AS [BoxTopRightX],
       RAW.[BoxTopRightY],
       RAW.[BoxBottomRightX]
       - ((RAW.[BoxBottomRightX] - RAW.[BoxBottomLeftX])
          * (1
             - (((LEN(RULES.[Primary_search_term]) + (CHARINDEX(RULES.[Primary_search_term], RAW.TEXT) - 1))
                 / cast(LEN(RAW.TEXT) AS FLOAT)
                )
               )
            )
         ) AS [BoxBottomRightX],
       RAW.[BoxBottomRightY],
       (RAW.[BoxBottomLeftX]
        + ((RAW.[BoxBottomRightX] - RAW.[BoxBottomLeftX])
           * ((CHARINDEX(RULES.[Primary_search_term], RAW.TEXT) - 1) / cast(LEN(RAW.TEXT) AS FLOAT))
          )
       ) AS [BoxBottomLeftX],
       RAW.[BoxBottomLeftY],
        NULL as [topBrand_Asset_Creative_perFilename],
        ImageWidth,
        ImageHeight,
        OcrLineId,
        Angle
    FROM (
            SELECT
               RAW.*
            FROM Toolkit_ComputerVisionOcrResults RAW
               LEFT JOIN Toolkit_Cleaned_OCR_Results CLEAN
                  ON RAW.OcrLineId = CLEAN.OcrLineID
                        AND CLEAN.AccessFlag = @specificAccessFlag
            WHERE RAW.SportsEvent in ( SELECT SportsEvent FROM #SportEvents )
            AND CLEAN.ID IS NULL
         ) RAW
        INNER JOIN Toolkit_OCR_cleaning_rules RULES
        ON (RAW.Text LIKE '%' + RULES.Primary_search_term + '%')
            AND substring_search_allowed = 1
            AND Row_addition_source = 'Human'
            AND Row_manually_confirmed = 1
            AND Reported_brand <> 'IGNORE'
            AND AccessFlag = @specificAccessFlag
            AND (other_on_screen_text_required = '')
    WHERE SportsEvent IN
      (
          SELECT SportsEvent FROM #SportEvents
      );

-- ============================================================
-- STAGE 4: Post-run KPI checks
-- ============================================================

SELECT
    COUNT(*) AS RawRows,
    SUM(CASE WHEN C.ID IS NOT NULL THEN 1 ELSE 0 END) AS CleanedRows,
    SUM(CASE WHEN C.ID IS NULL THEN 1 ELSE 0 END) AS RemainingRows,
    CAST(
        100.0 * SUM(CASE WHEN C.ID IS NOT NULL THEN 1 ELSE 0 END) / NULLIF(COUNT(*),0)
        AS DECIMAL(6,2)
    ) AS CoveragePct
FROM Toolkit_ComputerVisionOcrResults RAW
LEFT JOIN Toolkit_Cleaned_OCR_Results C
    ON RAW.OcrLineId = C.OcrLineID
    AND C.AccessFlag = @specificAccessFlag
WHERE RAW.SportsEvent IN (SELECT SportsEvent FROM #SportEvents);

SELECT SportsEvent, brand, COUNT(*) AS Cnt
FROM Toolkit_Cleaned_OCR_Results
WHERE AccessFlag = @specificAccessFlag
  AND SportsEvent IN (SELECT SportsEvent FROM #SportEvents)
GROUP BY SportsEvent, brand
ORDER BY SportsEvent, brand;
