/*
Run order:
A) Read-only baseline checks
B) Optional SS1 delete from CombinedResults
C) Brand normalization writes (Raw_Brands + Raw_BrandAssets)
D) Read-only post-clean checks
*/


SELECT *
from Daypart_Modelling




DECLARE @Scope TABLE (
    SportsEvent VARCHAR(200) NOT NULL,
    EventNoSlash VARCHAR(200) NOT NULL
);

INSERT INTO @Scope (SportsEvent, EventNoSlash)
VALUES
('12679_170626_Men_2ndTest_Eng_v_Nzl_Day_1/', '12679_170626_Men_2ndTest_Eng_v_Nzl_Day_1'),
('12679_180626_Men_2ndTest_Eng_v_Nzl_Day_2/', '12679_180626_Men_2ndTest_Eng_v_Nzl_Day_2'),
('12679_190626_Men_2ndTest_Eng_v_Nzl_Day_3/', '12679_190626_Men_2ndTest_Eng_v_Nzl_Day_3'),
('12679_200626_Men_2ndTest_Eng_v_Nzl_Day_4/', '12679_200626_Men_2ndTest_Eng_v_Nzl_Day_4'),
('12679_210626_Men_2ndTest_Eng_v_Nzl_Day_5/', '12679_210626_Men_2ndTest_Eng_v_Nzl_Day_5');

-- ================================================================
-- A) READ-ONLY baseline checks
-- ================================================================

SELECT
    RBA.Brand,
    RBA.Asset,
    COUNT_BIG(*) AS PairCount
FROM SportsSight_Raw_BrandAssets RBA
INNER JOIN @Scope S
    ON RBA.SportsEvent = S.SportsEvent
GROUP BY RBA.Brand, RBA.Asset
ORDER BY PairCount DESC, RBA.Brand, RBA.Asset;

SELECT
    RB.Brand,
    COUNT_BIG(*) AS BrandCount
FROM SportsSight_Raw_Brands RB
INNER JOIN @Scope S
    ON RB.SportsEvent = S.SportsEvent
GROUP BY RB.Brand
ORDER BY BrandCount DESC, RB.Brand;

SELECT
    RA.Asset,
    COUNT_BIG(*) AS AssetCount
FROM SportsSight_Raw_Assets RA
INNER JOIN @Scope S
    ON RA.SportsEvent = S.SportsEvent
GROUP BY RA.Asset
ORDER BY AssetCount DESC, RA.Asset;

-- ================================================================
-- B) OPTIONAL: delete SS1 rows for this event scope from CombinedResults
-- ================================================================
-- Run this only when you want to clear prior SS1 output before re-upload.

SELECT CR.Event, CR.Iteration, COUNT_BIG(*) AS Cnt
FROM Toolkit_AzureModels_CombinedResults CR
INNER JOIN @Scope S
    ON CR.Event = S.EventNoSlash
WHERE CR.Iteration = 'SS1'
GROUP BY CR.Event, CR.Iteration
ORDER BY CR.Event;

BEGIN TRANSACTION;

DELETE CR
FROM Toolkit_AzureModels_CombinedResults CR
INNER JOIN @Scope S
    ON CR.Event = S.EventNoSlash
WHERE CR.Iteration = 'SS1';

SELECT @@ROWCOUNT AS CombinedRowsDeleted;

SELECT COUNT_BIG(*) AS RemainingRows
FROM Toolkit_AzureModels_CombinedResults CR
INNER JOIN @Scope S
    ON CR.Event = S.EventNoSlash
WHERE CR.Iteration = 'SS1';

-- COMMIT TRANSACTION;
-- ROLLBACK TRANSACTION;

-- ================================================================
-- C) WRITE: normalize Brand names in both raw tables
-- ================================================================

SELECT
    'SportsSight_Raw_Brands' AS SourceTable,
    B.SportsEvent,
    B.Brand AS OldBrand,
    REPLACE(REPLACE(LTRIM(RTRIM(B.Brand)), 'Logo - Brand - ', ''), 'Tyrrell-s', 'Tyrrells') AS NewBrand
FROM SportsSight_Raw_Brands B
INNER JOIN @Scope S
    ON B.SportsEvent = S.SportsEvent
WHERE B.Brand LIKE 'Logo - Brand - %' OR B.Brand = 'Tyrrell-s'
ORDER BY B.SportsEvent, B.Brand;

SELECT
    'SportsSight_Raw_BrandAssets' AS SourceTable,
    BA.SportsEvent,
    BA.Brand AS OldBrand,
    REPLACE(REPLACE(LTRIM(RTRIM(BA.Brand)), 'Logo - Brand - ', ''), 'Tyrrell-s', 'Tyrrells') AS NewBrand
FROM SportsSight_Raw_BrandAssets BA
INNER JOIN @Scope S
    ON BA.SportsEvent = S.SportsEvent
WHERE BA.Brand LIKE 'Logo - Brand - %' OR BA.Brand = 'Tyrrell-s'
ORDER BY BA.SportsEvent, BA.Brand;

BEGIN TRANSACTION;

UPDATE B
SET B.Brand = REPLACE(REPLACE(LTRIM(RTRIM(B.Brand)), 'Logo - Brand - ', ''), 'Tyrrell-s', 'Tyrrells')
FROM SportsSight_Raw_Brands B
INNER JOIN @Scope S
    ON B.SportsEvent = S.SportsEvent
WHERE B.Brand LIKE 'Logo - Brand - %' OR B.Brand = 'Tyrrell-s';

SELECT @@ROWCOUNT AS RawBrandsRowsUpdated;

UPDATE BA
SET BA.Brand = REPLACE(REPLACE(LTRIM(RTRIM(BA.Brand)), 'Logo - Brand - ', ''), 'Tyrrell-s', 'Tyrrells')
FROM SportsSight_Raw_BrandAssets BA
INNER JOIN @Scope S
    ON BA.SportsEvent = S.SportsEvent
WHERE BA.Brand LIKE 'Logo - Brand - %' OR BA.Brand = 'Tyrrell-s';

SELECT @@ROWCOUNT AS RawBrandAssetsRowsUpdated;

-- COMMIT TRANSACTION;
-- ROLLBACK TRANSACTION;

-- ================================================================
-- D) READ-ONLY post-clean checks
-- ================================================================

SELECT
    RBA.SportsEvent,
    RBA.Brand,
    RBA.Asset,
    COUNT_BIG(*) AS PairCount
FROM SportsSight_Raw_BrandAssets RBA
INNER JOIN @Scope S
    ON RBA.SportsEvent = S.SportsEvent
GROUP BY RBA.SportsEvent, RBA.Brand, RBA.Asset
ORDER BY RBA.SportsEvent, PairCount DESC, RBA.Brand, RBA.Asset;

SELECT
    RBA.SportsEvent,
    RBA.Brand,
    RBA.Asset,
    COUNT_BIG(*) AS Cnt
FROM SportsSight_Raw_BrandAssets RBA
INNER JOIN @Scope S
    ON RBA.SportsEvent = S.SportsEvent
WHERE NULLIF(LTRIM(RTRIM(RBA.Brand)), '') IS NULL
   OR NULLIF(LTRIM(RTRIM(RBA.Asset)), '') IS NULL
GROUP BY RBA.SportsEvent, RBA.Brand, RBA.Asset
ORDER BY Cnt DESC;


select *
from tv

-- ================================================================
-- E) STANDALONE: print all Brand-Asset combinations for Men's 2nd Test
-- This block is fully independent and can be run by itself.
-- ================================================================

DECLARE @Scope_PrintBrandAsset TABLE (
    SportsEvent VARCHAR(200) NOT NULL
);

INSERT INTO @Scope_PrintBrandAsset (SportsEvent)
VALUES
('12679_170626_Men_2ndTest_Eng_v_Nzl_Day_1/'),
('12679_180626_Men_2ndTest_Eng_v_Nzl_Day_2/'),
('12679_190626_Men_2ndTest_Eng_v_Nzl_Day_3/'),
('12679_200626_Men_2ndTest_Eng_v_Nzl_Day_4/'),
('12679_210626_Men_2ndTest_Eng_v_Nzl_Day_5/');

-- 1) All distinct Brand-Asset combinations across Day 1-5 (normalized Brand)
SELECT
    REPLACE(REPLACE(LTRIM(RTRIM(RBA.Brand)), 'Logo - Brand - ', ''), 'Tyrrell-s', 'Tyrrells') AS Brand,
    LTRIM(RTRIM(RBA.Asset)) AS Asset,
    COUNT_BIG(*) AS PairCount
FROM SportsSight_Raw_BrandAssets RBA
INNER JOIN @Scope_PrintBrandAsset S
    ON RBA.SportsEvent = S.SportsEvent
GROUP BY
    REPLACE(REPLACE(LTRIM(RTRIM(RBA.Brand)), 'Logo - Brand - ', ''), 'Tyrrell-s', 'Tyrrells'),
    LTRIM(RTRIM(RBA.Asset))
ORDER BY PairCount DESC, Brand, Asset;

-- 2) Optional: per-event breakdown for each Brand-Asset combination
SELECT
    RBA.SportsEvent,
    REPLACE(REPLACE(LTRIM(RTRIM(RBA.Brand)), 'Logo - Brand - ', ''), 'Tyrrell-s', 'Tyrrells') AS Brand,
    LTRIM(RTRIM(RBA.Asset)) AS Asset,
    COUNT_BIG(*) AS PairCount
FROM SportsSight_Raw_BrandAssets RBA
INNER JOIN @Scope_PrintBrandAsset S
    ON RBA.SportsEvent = S.SportsEvent
GROUP BY
    RBA.SportsEvent,
    REPLACE(REPLACE(LTRIM(RTRIM(RBA.Brand)), 'Logo - Brand - ', ''), 'Tyrrell-s', 'Tyrrells'),
    LTRIM(RTRIM(RBA.Asset))
ORDER BY RBA.SportsEvent, PairCount DESC, Brand, Asset;