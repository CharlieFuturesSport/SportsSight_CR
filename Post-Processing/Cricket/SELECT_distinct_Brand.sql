-- 1) Check what will be deleted
SELECT Event, Iteration, COUNT_BIG(*) AS Cnt
FROM Toolkit_AzureModels_CombinedResults
WHERE Iteration = 'SS1'
  AND Event IN (
    '12678_040626_Men_1stTest_Eng_v_Nzl_Day_1',
    '12678_050626_Men_1stTest_Eng_v_Nzl_Day_2',
    '12678_060626_Men_1stTest_Eng_v_Nzl_Day_3',
    '12678_070626_Men_1stTest_Eng_v_Nzl_Day_4'
  )
GROUP BY Event, Iteration
ORDER BY Event;

-- 2) Delete (wrapped in transaction so you can rollback if needed)
BEGIN TRANSACTION;

DELETE FROM Toolkit_AzureModels_CombinedResults
WHERE Iteration = 'SS1'
  AND Event IN (
    '12678_040626_Men_1stTest_Eng_v_Nzl_Day_1',
    '12678_050626_Men_1stTest_Eng_v_Nzl_Day_2',
    '12678_060626_Men_1stTest_Eng_v_Nzl_Day_3',
    '12678_070626_Men_1stTest_Eng_v_Nzl_Day_4'
  );

-- 3) Verify zero rows remain
SELECT COUNT_BIG(*) AS RemainingRows
FROM Toolkit_AzureModels_CombinedResults
WHERE Iteration = 'SS1'
  AND Event IN (
    '12678_040626_Men_1stTest_Eng_v_Nzl_Day_1',
    '12678_050626_Men_1stTest_Eng_v_Nzl_Day_2',
    '12678_060626_Men_1stTest_Eng_v_Nzl_Day_3',
    '12678_070626_Men_1stTest_Eng_v_Nzl_Day_4'
  );

-- 4) If happy:
COMMIT TRANSACTION;
-- If not:
-- ROLLBACK TRANSACTION;



-- ================================================
-- PREVIEW rows that will be changed (no write)
-- ================================================
SELECT
    B.SportsEvent,
    B.Brand AS OldBrand,
    LTRIM(SUBSTRING(B.Brand, LEN('Logo - Brand - ') + 1, 8000)) AS NewBrand
FROM SportsSight_Raw_Brands B
WHERE B.SportsEvent IN (
    '12678_040626_Men_1stTest_Eng_v_Nzl_Day_1/',
    '12678_050626_Men_1stTest_Eng_v_Nzl_Day_2/',
    '12678_060626_Men_1stTest_Eng_v_Nzl_Day_3/',
    '12678_070626_Men_1stTest_Eng_v_Nzl_Day_4/'
)
AND B.Brand LIKE 'Logo - Brand - %'
ORDER BY B.SportsEvent, B.Brand;

-- ================================================
-- APPLY UPDATE (writes to table)
-- ================================================
BEGIN TRAN;

UPDATE B
SET B.Brand = CASE
    WHEN LTRIM(SUBSTRING(B.Brand, LEN('Logo - Brand - ') + 1, 8000)) = 'Tyrrell-s' THEN 'Tyrrells'
    ELSE LTRIM(SUBSTRING(B.Brand, LEN('Logo - Brand - ') + 1, 8000))
END
FROM SportsSight_Raw_Brands B
WHERE B.SportsEvent IN (
    '12678_040626_Men_1stTest_Eng_v_Nzl_Day_1/',
    '12678_050626_Men_1stTest_Eng_v_Nzl_Day_2/',
    '12678_060626_Men_1stTest_Eng_v_Nzl_Day_3/',
    '12678_070626_Men_1stTest_Eng_v_Nzl_Day_4/'
)
AND (
    B.Brand LIKE 'Logo - Brand - %'
    OR B.Brand = 'Tyrrell-s'
);

SELECT @@ROWCOUNT AS RowsUpdated;

COMMIT TRAN;

-- ================================================
-- VERIFY final distinct brand values
-- ================================================
SELECT DISTINCT B.Brand
FROM SportsSight_Raw_Brands B
WHERE B.SportsEvent IN (
    '12678_040626_Men_1stTest_Eng_v_Nzl_Day_1/',
    '12678_050626_Men_1stTest_Eng_v_Nzl_Day_2/',
    '12678_060626_Men_1stTest_Eng_v_Nzl_Day_3/',
    '12678_070626_Men_1stTest_Eng_v_Nzl_Day_4/'
)
ORDER BY 1;


UPDATE B
SET B.Brand = 'Tyrrells'
FROM SportsSight_Raw_Brands B
WHERE B.SportsEvent IN (
    '12678_040626_Men_1stTest_Eng_v_Nzl_Day_1/',
    '12678_050626_Men_1stTest_Eng_v_Nzl_Day_2/',
    '12678_060626_Men_1stTest_Eng_v_Nzl_Day_3/',
    '12678_070626_Men_1stTest_Eng_v_Nzl_Day_4/'
)
AND (B.Brand = '' OR B.Brand IS NULL);


SELECT DISTINCT BA.Brand, BA.Asset
FROM SportsSight_Raw_BrandAssets BA
WHERE BA.SportsEvent IN (
    '12678_040626_Men_1stTest_Eng_v_Nzl_Day_1/',
    '12678_050626_Men_1stTest_Eng_v_Nzl_Day_2/',
    '12678_060626_Men_1stTest_Eng_v_Nzl_Day_3/',
    '12678_070626_Men_1stTest_Eng_v_Nzl_Day_4/'
)
ORDER BY BA.Brand, BA.Asset;