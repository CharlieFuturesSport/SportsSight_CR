-- Detection counts (not exposure seconds) per Brand+Asset, 2025 vs 2026, with % diff.
-- Uses Toolkit_AzureModels_CombinedResults - the one table that still has both years'
-- data, since the truly raw SportsSight_Raw_* tables were purged for 2025.

;WITH Pivoted AS
(
    SELECT
        Brand,
        Asset,
        SUM(CASE WHEN Event LIKE '%2025%' THEN 1 ELSE 0 END) AS Detections_2025,
        SUM(CASE WHEN Event LIKE '%2026%' THEN 1 ELSE 0 END) AS Detections_2026
    FROM Toolkit_AzureModels_CombinedResults
    WHERE Event IN (
        '20250606_PDC_NordicDartsMasters_Day1Evening',
        '20250607_PDC_NordicDartsMasters_Day2Evening',
        '20260605_PDC_NORD_Day1Evening',
        '20260606_PDC_NORD_Day2Evening'
    )
    GROUP BY Brand, Asset
)
SELECT
    Brand,
    Asset,
    Detections_2025,
    Detections_2026,
    CAST(
        CASE WHEN Detections_2025 = 0 THEN NULL
        ELSE 100.0 * (Detections_2026 - Detections_2025) / Detections_2025
        END AS DECIMAL(6,2)
    ) AS ChangePct
FROM Pivoted
ORDER BY Brand, Asset;
