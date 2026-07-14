-- Full Nordic Darts Masters exposure comparison, 2025 vs 2026, every brand/touchpoint
-- Pivoted so 2025/2026 sit as side-by-side columns per Brand+Touchpoint
-- Run while connected to Matchroom (same as all other Exposure queries this session)

;WITH Pivoted AS
(
    SELECT
        b.BrandName,
        t.TouchpointName,
        SUM(CASE WHEN p.PR_Name LIKE '%2025%' THEN e.Duration ELSE 0 END) AS ExpSecs_2025,
        SUM(CASE WHEN p.PR_Name LIKE '%2026%' THEN e.Duration ELSE 0 END) AS ExpSecs_2026
    FROM dbo.Exposure e
    INNER JOIN dbo.[CMGSQLNODE01\FSE.TvTrack.Programme] p
        ON p.ProgID = e.ProgrammeID
    INNER JOIN dbo.[CMGSQLNODE01\FSE.PhotoTextTrack.Brands] b
        ON b.BrandID = e.BrandID
    INNER JOIN dbo.[CMGSQLNODE01\FSE.PhotoTextTrack.Touchpoints] t
        ON t.TouchpointID = e.TP_ID
    WHERE p.PR_Name IN (
        '20250606_PDC_NordicDartsMasters_Day1Evening.xlsx',
        '20250607_PDC_NordicDartsMasters_Day2Evening.xlsx',
        '20260605_PDC_NORD_Day1Evening.xlsx',
        '20260606_PDC_NORD_Day2Evening.xlsx'
    )
    GROUP BY b.BrandName, t.TouchpointName
)
SELECT
    BrandName,
    TouchpointName,
    ExpSecs_2025,
    ExpSecs_2026,
    CAST(
        CASE WHEN ExpSecs_2025 = 0 THEN NULL
        ELSE 100.0 * (ExpSecs_2026 - ExpSecs_2025) / ExpSecs_2025
        END AS DECIMAL(6,2)
    ) AS ChangePct
FROM Pivoted
ORDER BY BrandName, TouchpointName;
