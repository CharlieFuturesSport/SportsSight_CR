INSERT INTO dbo.Brands (BrandName)
SELECT v.BrandName
FROM (VALUES
    ('Dragonbet'),
    ('IGLU')
) v(BrandName)
WHERE NOT EXISTS (
    SELECT 1
    FROM dbo.Brands b
    WHERE LTRIM(RTRIM(b.BrandName)) = LTRIM(RTRIM(v.BrandName))
);