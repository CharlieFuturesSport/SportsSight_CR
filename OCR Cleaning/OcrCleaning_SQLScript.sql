-- OCR Cleaning

-- ============================================================
-- STAGE 1: Build event list for this run
-- ============================================================

-- Stage 1A: Find events that have recently been processed
SELECT
     '(''' + SportsEvent + '''),'
FROM [dbo].[CMGSQLNODE01\FSE.ThemisDevelopment.ComputerVisionProcessingJobsHistory]
WHERE Sport = 'darts'
AND CREATED >= GETUTCDATE() - 60
and SportsEvent like '%nord%'
ORDER BY created desc

-- Stage 1B: Create and populate #SportEvents
drop table if exists #SportEvents
CREATE TABLE  #SportEvents (
    ID INT IDENTITY(1,1),
    SportsEvent VARCHAR(255)
)

INSERT INTO #SportEvents VALUES
('20260606_PDC_NORD_Day2Evening/'),
('20260605_PDC_NORD_Day1Evening/')

-- ============================================================
-- STAGE 2: Review existing cleaning rules
-- ============================================================

-- Stage 2A: Check existing Human rules for this AccessFlag
select * from Toolkit_OCR_cleaning_rules where AccessFlag = 'nordic'
and Row_addition_source = 'human'

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
        ('Chapel Down', '', 'Nordic')
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
)

-- ============================================================
-- STAGE 3: Apply OCR cleaning pipeline
-- ============================================================

-- --------------------
-- STEP 3.1: Insert exact Human matches
-- --------------------

DECLARE @specificAccessFlag VARCHAR(100)
SET @specificAccessFlag = 'Nordic'

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
                  AND AccessFlag = @specificAccessFlag
            WHERE RAW.SportsEvent in ( SELECT SportsEvent FROM #SportEvents )
            AND CLEAN.ID IS NULL
    ) RAW
    INNER JOIN Toolkit_OCR_cleaning_rules RULES
        ON (RAW.TEXT = RULES.Primary_search_term)
           AND Row_manually_confirmed = 1
           AND Row_addition_source = 'Human'
           AND Reported_brand <> 'IGNORE'
           AND AccessFlag = @specificAccessFlag
           AND (other_on_screen_text_required = '')

-- --------------------
-- STEP 3.2: Insert exact Automated matches
-- --------------------

DECLARE @specificAccessFlag VARCHAR(100)
SET @specificAccessFlag = 'Nordic'

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
                  AND AccessFlag = @specificAccessFlag
            WHERE RAW.SportsEvent in ( SELECT SportsEvent FROM #SportEvents )
            AND CLEAN.ID IS NULL
         ) RAW
    INNER JOIN Toolkit_OCR_cleaning_rules RULES
        ON (RAW.TEXT = RULES.Primary_search_term)
           AND Row_manually_confirmed = 1
           AND Row_addition_source = 'Automated' --'Human'
           AND exact_match_required = 1
           AND substring_search_allowed = 0
           AND Reported_brand <> 'IGNORE'
           AND AccessFlag = @specificAccessFlag
           AND (other_on_screen_text_required = '')
WHERE SportsEvent IN
      (
          SELECT SportsEvent FROM #SportEvents
      )

-- --------------------
-- STEP 3.3: Generate, review, and apply new exact-match terms
-- --------------------

-- IDENTIFY SEARCH TERMS
DECLARE @specificAccessFlag VARCHAR(100)
SET @specificAccessFlag = 'Nordic'
DECLARE @autoAcceptMaxOcrCount INT
SET @autoAcceptMaxOcrCount = 3

DROP TABLE IF EXISTS #Stage33Candidates

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
WHERE MatchRank = 1

-- 3.3.1 Generate AUTO_ACCEPT rows
DROP TABLE IF EXISTS #Stage33AutoAcceptToInsert
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
)

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
ORDER BY ocrCount DESC, Reported_brand, PercentDistance DESC

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
FROM #Stage33AutoAcceptToInsert A

-- 3.3.2 Generate MANUAL_REVIEW rows (> @autoAcceptMaxOcrCount OCR count)
DROP TABLE IF EXISTS #Stage33ManualReviewToInsert
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
)

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
    H.Primary_Search_Term

-- Step 3.3.2B: Fast manual review ordered by brand/creative
-- 1) Reject specific terms after review.
-- Tip: paste quoted Primary_Search_Term values into the IN list below (one per line).
UPDATE #Stage33ManualReviewToInsert
SET Decision = 'REJECT'
WHERE Decision = 'PENDING'
AND Primary_Search_Term IN
(
    'ADDERS',
    'TermB'
)

-- 2) Accept everything else that remains pending.
UPDATE H
SET
    H.Decision = 'ACCEPT'
FROM #Stage33ManualReviewToInsert H
WHERE H.Decision = 'PENDING'

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
WHERE H.Decision = 'ACCEPT'

-- Step 3.3.4: Rerun AUTOMATED exact-match insert after new rules were added
DECLARE @specificAccessFlag VARCHAR(100)
SET @specificAccessFlag = 'Nordic'

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
                  AND AccessFlag = @specificAccessFlag
            WHERE RAW.SportsEvent in ( SELECT SportsEvent FROM #SportEvents )
            AND CLEAN.ID IS NULL
         ) RAW
    INNER JOIN Toolkit_OCR_cleaning_rules RULES
        ON (RAW.TEXT = RULES.Primary_search_term)
           AND Row_manually_confirmed = 1
           AND Row_addition_source = 'Automated' --'Human'
           AND exact_match_required = 1
           AND substring_search_allowed = 0
           AND Reported_brand <> 'IGNORE'
           AND AccessFlag = @specificAccessFlag
           AND (other_on_screen_text_required = '')
WHERE SportsEvent IN
      (
          SELECT SportsEvent FROM #SportEvents
      )


-- --------------------
-- STEP 3.4: Insert substring matches (Human rules)
-- --------------------

DECLARE @specificAccessFlag VARCHAR(100)
SET @specificAccessFlag = 'Nordic'

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
                  AND AccessFlag = @specificAccessFlag
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
      )