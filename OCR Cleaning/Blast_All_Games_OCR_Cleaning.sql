-- Blast all-games OCR cleaning runner
-- Purpose: run OCR cleaning across the full Blast checklist in one batch.
-- Notes:
-- 1) Set @specificAccessFlag before running.
-- 2) Add/update human rules in Toolkit_OCR_Cleaning_Rules first.
-- 3) This script resolves real SportsEvent names from OCR raw data using Blast match IDs.


SELECT r.session_id, r.status, r.command, r.total_elapsed_time, r.wait_type, s.host_name, s.login_time
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
ORDER BY r.total_elapsed_time DESC;


SELECT SportsEvent, COUNT(*) AS CleanedRows
FROM Toolkit_Cleaned_OCR_Results
WHERE AccessFlag = 'ecb_2026' AND SportsEvent LIKE '127%'
GROUP BY SportsEvent
ORDER BY SportsEvent;


SELECT Reported_brand FROM Toolkit_OCR_Cleaning_Rules
WHERE AccessFlag = 'ecb_2026'
  AND Reported_brand IN ('Woodland Group','Price Forbes','Surridge Sport','WBS','Uptonsteel','Manscaped','Absolube','Chevin','Samurai','Stadiacare','Attivo','Alt Group','Stadium Support Services','ebc','University of Birmingham','Macron','Nike','Remitly','Cinch','CMG','Whole Earth');

SET NOCOUNT ON;


DECLARE @specificAccessFlag VARCHAR(100) = 'ecb_2026';
DECLARE @autoAcceptMaxOcrCount INT = 3;
DECLARE @allowRerunDelete BIT = 0; -- set to 1 only if you intentionally want to wipe existing cleaned rows for this run scope

-- ============================================================
-- STAGE 1: Build Blast run scope from checklist match IDs
-- ============================================================

DROP TABLE IF EXISTS #BlastMatches;
CREATE TABLE #BlastMatches
(
    MatchID INT PRIMARY KEY,
    MatchLabel VARCHAR(120) NOT NULL,
    IsAlreadyCleaned BIT NOT NULL
);

INSERT INTO #BlastMatches (MatchID, MatchLabel, IsAlreadyCleaned)
VALUES
(12729, '220526 Mens Blast Group Som v Ham', 1),
(12730, '220526 Womens Blast Group Som v Ham', 1),
(12731, '230526 Mens Blast Group Gla v Glo', 1),
(12732, '240526 Mens Blast Group Mid v Sur', 1),
(12733, '260526 Mens Blast Group Ham v Ess', 0),
(12734, '260526 Womens Blast Group Ham v Ess', 0),
(12735, '270526 Mens Blast Group Lei v Der', 0),
(12736, '290526 Mens Blast Group Wor v War', 0),
(12737, '300526 Mens Blast Group Sus v Mid', 0),
(12738, '310526 Mens Blast Group War v Nor', 0),
(12739, '030626 Mens Blast Group Sur v Mid', 0);

DROP TABLE IF EXISTS #SportEvents;
CREATE TABLE #SportEvents
(
    ID INT IDENTITY(1,1) PRIMARY KEY,
    MatchID INT NOT NULL,
    SportsEvent VARCHAR(255) NOT NULL
);

-- Resolve actual event names from OCR raw table.
INSERT INTO #SportEvents (MatchID, SportsEvent)
SELECT DISTINCT
    M.MatchID,
    CASE
        WHEN RIGHT(RAW.SportsEvent, 1) = '/' THEN RAW.SportsEvent
        ELSE RAW.SportsEvent + '/'
    END AS SportsEvent
FROM #BlastMatches M
JOIN Toolkit_ComputerVisionOcrResults RAW
    ON RAW.SportsEvent LIKE CAST(M.MatchID AS VARCHAR(10)) + '\_%' ESCAPE '\'
WHERE LOWER(RAW.SportsEvent) LIKE '%blast%';

-- Scope visibility.
SELECT
    E.MatchID,
    M.MatchLabel,
    M.IsAlreadyCleaned,
    E.SportsEvent
FROM #SportEvents E
JOIN #BlastMatches M
    ON M.MatchID = E.MatchID
ORDER BY E.MatchID, E.SportsEvent;

-- Any IDs that did not resolve to event names.
SELECT
    M.MatchID,
    M.MatchLabel
FROM #BlastMatches M
LEFT JOIN #SportEvents E
    ON E.MatchID = M.MatchID
WHERE E.ID IS NULL
ORDER BY M.MatchID;

-- Optional: restrict to only currently unchecked rows from checklist.
-- DELETE E
-- FROM #SportEvents E
-- JOIN #BlastMatches M ON M.MatchID = E.MatchID
-- WHERE M.IsAlreadyCleaned = 1;

IF @allowRerunDelete = 1
BEGIN
    DELETE C
    FROM Toolkit_Cleaned_OCR_Results C
    WHERE C.AccessFlag = @specificAccessFlag
      AND C.SportsEvent IN (SELECT SportsEvent FROM #SportEvents);
END;

-- ============================================================
-- STAGE 1B: Seed new Human brand rules from the Kishan asset workbook
-- (Blast 1st set of matches_v1 (1).xlsx) for the 7 matches added since
-- the first 4 games were cleaned. NOT_EXISTS-guarded, safe to re-run.
-- 'more' (12735 Lei v Der sheet, row for Leicestershire) deliberately
-- excluded -- confirm what that brand actually is before adding it.
-- ============================================================

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
        ('Woodland Group', '', @specificAccessFlag),
        ('Price Forbes', '', @specificAccessFlag),
        ('Surridge Sport', '', @specificAccessFlag),
        ('WBS', '', @specificAccessFlag),
        ('Uptonsteel', '', @specificAccessFlag),
        ('Manscaped', '', @specificAccessFlag),
        ('Absolube', '', @specificAccessFlag),
        ('Chevin', '', @specificAccessFlag),
        ('Samurai', '', @specificAccessFlag),
        ('Stadiacare', '', @specificAccessFlag),
        ('Attivo', '', @specificAccessFlag),
        ('Alt Group', '', @specificAccessFlag),
        ('Stadium Support Services', '', @specificAccessFlag),
        ('ebc', '', @specificAccessFlag),
        ('University of Birmingham', '', @specificAccessFlag),
        ('Macron', '', @specificAccessFlag),
        ('Nike', '', @specificAccessFlag),
        ('Remitly', '', @specificAccessFlag),
        ('Cinch', '', @specificAccessFlag),
        ('CMG', '', @specificAccessFlag),
        ('Whole Earth', '', @specificAccessFlag),
        ('IBC', '', @specificAccessFlag),
        ('Ark Build', '', @specificAccessFlag)
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

-- ============================================================
-- STAGE 2: Pre-run KPI checks
-- ============================================================

SELECT 'Scope events' AS metric, COUNT(*) AS value
FROM #SportEvents;

SELECT 'Raw detections' AS metric, COUNT(*) AS value
FROM Toolkit_ComputerVisionOcrResults RAW
WHERE RAW.SportsEvent IN (SELECT SportsEvent FROM #SportEvents);

SELECT 'Already cleaned rows' AS metric, COUNT(*) AS value
FROM Toolkit_Cleaned_OCR_Results C
WHERE C.AccessFlag = @specificAccessFlag
  AND C.SportsEvent IN (SELECT SportsEvent FROM #SportEvents);

SELECT
    'Coverage % pre-run' AS metric,
    CAST(
        100.0 * SUM(CASE WHEN C.ID IS NOT NULL THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0)
        AS DECIMAL(6,2)
    ) AS value
FROM Toolkit_ComputerVisionOcrResults RAW
LEFT JOIN Toolkit_Cleaned_OCR_Results C
    ON RAW.OcrLineId = C.OcrLineID
   AND C.AccessFlag = @specificAccessFlag
WHERE RAW.SportsEvent IN (SELECT SportsEvent FROM #SportEvents);

-- ============================================================
-- STAGE 3: Apply cleaning using existing rules
-- ============================================================

-- 3.1 Exact Human matches.
INSERT INTO Toolkit_Cleaned_OCR_Results
SELECT
       NEWID() AS id,
       Sport,
       SportsEvent,
       [Filename],
       TEXT AS original_text,
       CASE
           WHEN RULES.Reported_creative IS NULL OR RULES.Reported_creative = '' THEN RULES.Reported_brand
           ELSE RULES.Reported_creative
       END AS cleaned_text,
       RULES.Reported_brand AS brand,
       NULL AS Asset,
       RULES.Reported_creative AS creative,
       RULES.AccessFlag,
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
FROM
(
    SELECT RAW.*
    FROM Toolkit_ComputerVisionOcrResults RAW
    LEFT JOIN Toolkit_Cleaned_OCR_Results CLEAN
        ON RAW.OcrLineId = CLEAN.OcrLineID
       AND CLEAN.AccessFlag = @specificAccessFlag
    WHERE RAW.SportsEvent IN (SELECT SportsEvent FROM #SportEvents)
      AND CLEAN.ID IS NULL
) RAW
INNER JOIN Toolkit_OCR_cleaning_rules RULES
    ON RAW.TEXT = RULES.Primary_search_term
   AND RULES.Row_manually_confirmed = 1
   AND RULES.Row_addition_source = 'Human'
   AND RULES.Reported_brand <> 'IGNORE'
   AND RULES.AccessFlag = @specificAccessFlag
   AND RULES.other_on_screen_text_required = '';

-- 3.2 Exact Automated matches.
INSERT INTO Toolkit_Cleaned_OCR_Results
SELECT
    NEWID() AS id,
    Sport,
    SportsEvent,
    [Filename],
    TEXT AS original_text,
    CASE
        WHEN RULES.Reported_creative IS NULL OR RULES.Reported_creative = '' THEN RULES.Reported_brand
        ELSE RULES.Reported_creative
    END AS cleaned_text,
    RULES.Reported_brand AS brand,
    NULL AS Asset,
    RULES.Reported_creative AS creative,
    RULES.AccessFlag,
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
FROM
(
    SELECT RAW.*
    FROM Toolkit_ComputerVisionOcrResults RAW
    LEFT JOIN Toolkit_Cleaned_OCR_Results CLEAN
        ON RAW.OcrLineId = CLEAN.OcrLineID
       AND CLEAN.AccessFlag = @specificAccessFlag
    WHERE RAW.SportsEvent IN (SELECT SportsEvent FROM #SportEvents)
      AND CLEAN.ID IS NULL
) RAW
INNER JOIN Toolkit_OCR_cleaning_rules RULES
    ON RAW.TEXT = RULES.Primary_search_term
   AND RULES.Row_manually_confirmed = 1
   AND RULES.Row_addition_source = 'Automated'
   AND RULES.exact_match_required = 1
   AND RULES.substring_search_allowed = 0
   AND RULES.Reported_brand <> 'IGNORE'
   AND RULES.AccessFlag = @specificAccessFlag
   AND RULES.other_on_screen_text_required = '';

-- 3.3 Substring Human matches.
INSERT INTO Toolkit_Cleaned_OCR_Results
SELECT
    NEWID() AS id,
    Sport,
    SportsEvent,
    [Filename],
    RAW.Text AS original_text,
    CASE
        WHEN RULES.Reported_creative IS NULL OR RULES.Reported_creative = '' THEN RULES.Reported_brand
        ELSE RULES.Reported_creative
    END AS cleaned_text,
    RULES.Reported_brand AS brand,
    NULL AS Asset,
    RULES.Reported_creative AS creative,
    RULES.AccessFlag,
    (RAW.[BoxTopLeftX] + ((RAW.[BoxTopRightX] - RAW.[BoxTopLeftX]) * ((CHARINDEX(RULES.[Primary_search_term], RAW.TEXT) - 1) / CAST(LEN(RAW.TEXT) AS FLOAT)))) AS [BoxTopLeftX],
    RAW.[BoxTopLeftY],
    RAW.[BoxTopRightX] - ((RAW.[BoxTopRightX] - RAW.[BoxTopLeftX]) * (1 - (((LEN(RULES.[Primary_search_term]) + (CHARINDEX(RULES.[Primary_search_term], RAW.TEXT) - 1)) / CAST(LEN(RAW.TEXT) AS FLOAT))))) AS [BoxTopRightX],
    RAW.[BoxTopRightY],
    RAW.[BoxBottomRightX] - ((RAW.[BoxBottomRightX] - RAW.[BoxBottomLeftX]) * (1 - (((LEN(RULES.[Primary_search_term]) + (CHARINDEX(RULES.[Primary_search_term], RAW.TEXT) - 1)) / CAST(LEN(RAW.TEXT) AS FLOAT))))) AS [BoxBottomRightX],
    RAW.[BoxBottomRightY],
    (RAW.[BoxBottomLeftX] + ((RAW.[BoxBottomRightX] - RAW.[BoxBottomLeftX]) * ((CHARINDEX(RULES.[Primary_search_term], RAW.TEXT) - 1) / CAST(LEN(RAW.TEXT) AS FLOAT)))) AS [BoxBottomLeftX],
    RAW.[BoxBottomLeftY],
    NULL AS [topBrand_Asset_Creative_perFilename],
    ImageWidth,
    ImageHeight,
    OcrLineId,
    Angle
FROM
(
    SELECT RAW.*
    FROM Toolkit_ComputerVisionOcrResults RAW
    LEFT JOIN Toolkit_Cleaned_OCR_Results CLEAN
        ON RAW.OcrLineId = CLEAN.OcrLineID
       AND CLEAN.AccessFlag = @specificAccessFlag
    WHERE RAW.SportsEvent IN (SELECT SportsEvent FROM #SportEvents)
      AND CLEAN.ID IS NULL
) RAW
INNER JOIN Toolkit_OCR_cleaning_rules RULES
    ON RAW.Text LIKE '%' + RULES.Primary_search_term + '%'
   AND RULES.substring_search_allowed = 1
   AND RULES.Row_addition_source = 'Human'
   AND RULES.Row_manually_confirmed = 1
   AND RULES.Reported_brand <> 'IGNORE'
   AND RULES.AccessFlag = @specificAccessFlag
   AND RULES.other_on_screen_text_required = '';

-- 3.4 Suggest new exact-match automated terms (manual review gate)
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
    WHERE OCR.SportsEvent IN (SELECT SportsEvent FROM #SportEvents)
      AND Inserted.OcrLineID IS NULL
    GROUP BY OCR.TEXT
),
UnseenOCR AS
(
    SELECT P.TEXT, P.ocrCount
    FROM PendingOCR P
    LEFT JOIN Toolkit_OCR_cleaning_rules R
        ON P.TEXT = R.Primary_Search_Term
       AND R.AccessFlag = @specificAccessFlag
    WHERE R.ID IS NULL
),
CompBrands AS
(
    SELECT
        Primary_search_term,
        Min_Levenshtein_Value,
        Reported_brand,
        Reported_creative,
        AccessFlag
    FROM Toolkit_OCR_cleaning_rules
    WHERE Min_Levenshtein_Value < 1
      AND reported_brand <> 'IGNORE'
      AND exact_match_required <> 1
      AND AccessFlag = @specificAccessFlag
      AND Row_addition_source = 'Human'
),
RankedMatches AS
(
    SELECT
        U.TEXT,
        U.ocrCount,
        C.Reported_brand,
        C.Reported_creative,
        C.AccessFlag,
        CAST((dbo.Toolkit_FUNC_LevenshteinDistanceAsPercentage(U.TEXT, C.Primary_search_term)) / 100.0 AS DECIMAL(10,4)) AS PercentDistance,
        C.Min_Levenshtein_Value,
        ROW_NUMBER() OVER
        (
            PARTITION BY U.TEXT
            ORDER BY dbo.Toolkit_FUNC_LevenshteinDistanceAsPercentage(U.TEXT, C.Primary_search_term) DESC,
                     C.Min_Levenshtein_Value DESC,
                     C.Reported_brand
        ) AS MatchRank
    FROM UnseenOCR U
    INNER JOIN CompBrands C
        ON (dbo.Toolkit_FUNC_LevenshteinDistanceAsPercentage(U.TEXT, C.Primary_search_term)) / 100.0 >= C.Min_Levenshtein_Value
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
    CASE WHEN ocrCount <= @autoAcceptMaxOcrCount THEN 'AUTO_ACCEPT' ELSE 'MANUAL_REVIEW' END AS ReviewAction
INTO #Stage33Candidates
FROM RankedMatches
WHERE MatchRank = 1;

-- Review candidates before insertion.
SELECT *
FROM #Stage33Candidates
ORDER BY ReviewAction, ocrCount DESC, Reported_brand, Primary_Search_Term;

-- Auto-insert low-frequency candidates.
INSERT INTO Toolkit_OCR_Cleaning_Rules
SELECT
   'Automated',
   1,
   C.Reported_brand,
   C.Reported_creative,
   C.AccessFlag,
   C.Primary_Search_Term,
   C.SearchTermLen,
   C.exact_match_required,
   C.substring_search_allowed,
   C.min_levenshtein_value,
   ''
FROM #Stage33Candidates C
WHERE C.ReviewAction = 'AUTO_ACCEPT'
  AND NOT EXISTS
  (
      SELECT 1
      FROM Toolkit_OCR_Cleaning_Rules R
      WHERE R.AccessFlag = C.AccessFlag
        AND R.Primary_Search_Term = C.Primary_Search_Term
  );

-- ============================================================
-- STAGE 4: Post-run KPI checks
-- ============================================================

SELECT
    COUNT(*) AS RawRows,
    SUM(CASE WHEN C.ID IS NOT NULL THEN 1 ELSE 0 END) AS CleanedRows,
    SUM(CASE WHEN C.ID IS NULL THEN 1 ELSE 0 END) AS RemainingRows,
    CAST(
        100.0 * SUM(CASE WHEN C.ID IS NOT NULL THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0)
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
