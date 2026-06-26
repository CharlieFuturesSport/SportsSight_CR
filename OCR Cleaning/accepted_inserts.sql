DECLARE @event VARCHAR(255) = '12729_220526_Mens_Blast_Group_Som_v_Ham';
DECLARE @method_table SYSNAME = 'SportsSight_BrandAssetMethod_20260615';

-- 1) Brands in raw data but not covered by methodology
DECLARE @sql NVARCHAR(MAX) = '
SELECT rb.Brand, COUNT(*) AS Cnt
FROM SportsSight_Raw_Brands rb
LEFT JOIN dbo.' + QUOTENAME(@method_table) + ' m
  ON LTRIM(RTRIM(rb.Brand)) = LTRIM(RTRIM(m.Brand))
WHERE rb.SportsEvent = @event
  AND m.Brand IS NULL
GROUP BY rb.Brand
ORDER BY Cnt DESC;';
EXEC sp_executesql @sql, N'@event VARCHAR(255)', @event;

-- 2) Assets in raw data but not covered by methodology
SET @sql = '
SELECT ra.Asset, COUNT(*) AS Cnt
FROM SportsSight_Raw_Assets ra
LEFT JOIN dbo.' + QUOTENAME(@method_table) + ' m
  ON LTRIM(RTRIM(ra.Asset)) = LTRIM(RTRIM(m.Asset))
WHERE ra.SportsEvent = @event
  AND m.Asset IS NULL
GROUP BY ra.Asset
ORDER BY Cnt DESC;';
EXEC sp_executesql @sql, N'@event VARCHAR(255)', @event;

-- 3) Brand+Asset combos in raw data but not covered by methodology
SET @sql = '
SELECT rba.Brand, rba.Asset, COUNT(*) AS Cnt
FROM SportsSight_Raw_BrandAssets rba
LEFT JOIN dbo.' + QUOTENAME(@method_table) + ' m
  ON LTRIM(RTRIM(rba.Brand)) = LTRIM(RTRIM(m.Brand))
 AND LTRIM(RTRIM(rba.Asset)) = LTRIM(RTRIM(m.Asset))
WHERE rba.SportsEvent = @event
  AND m.Brand IS NULL
GROUP BY rba.Brand, rba.Asset
ORDER BY Cnt DESC;';
EXEC sp_executesql @sql, N'@event VARCHAR(255)', @event;

-- 4) Methodology rows where Asset likely contains creative text
SET @sql = '
SELECT Brand, Asset, Creative, Final_asset
FROM dbo.' + QUOTENAME(@method_table) + '
WHERE Asset LIKE ''% - %''
   OR Asset LIKE ''%/%''
ORDER BY Brand, Asset;';
EXEC sp_executesql @sql;


DECLARE @event VARCHAR(255) = '12729_220526_Mens_Blast_Group_Som_v_Ham';

SELECT DISTINCT
r.Brand,
r.Asset,
LTRIM(RTRIM(
REPLACE(
REPLACE(
REPLACE(
REPLACE(r.Brand, 'Logo - Brand - ', ''),
' - Blast', ''),
' - IT20', ''),
' - Dog', '')
)) AS Suggested_Final_brand,
LTRIM(RTRIM(r.Asset)) AS Suggested_Final_asset
FROM SportsSight_Raw_BrandAssets r
LEFT JOIN dbo.SportsSight_BrandAssetMethod_20260615 m
ON LTRIM(RTRIM(r.Brand)) = LTRIM(RTRIM(m.Brand))
AND LTRIM(RTRIM(r.Asset)) = LTRIM(RTRIM(m.Asset))
WHERE r.SportsEvent = @event
AND m.Brand IS NULL
ORDER BY r.Brand, r.Asset;


