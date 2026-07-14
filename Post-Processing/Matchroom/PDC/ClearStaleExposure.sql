-- Clear stale Exposure rows for Nordic Darts Masters 2026 before regenerating fresh
-- Scoped tightly to just these two events via the Programme join - won't touch anything else

DELETE e
FROM dbo.Exposure e
INNER JOIN dbo.[CMGSQLNODE01\FSE.TvTrack.Programme] p
    ON p.ProgID = e.ProgrammeID
WHERE p.PR_Name IN ('20260605_PDC_NORD_Day1Evening.xlsx', '20260606_PDC_NORD_Day2Evening.xlsx');

-- Verify it's actually empty now
SELECT COUNT(*) AS RemainingRows
FROM dbo.Exposure e
INNER JOIN dbo.[CMGSQLNODE01\FSE.TvTrack.Programme] p
    ON p.ProgID = e.ProgrammeID
WHERE p.PR_Name IN ('20260605_PDC_NORD_Day1Evening.xlsx', '20260606_PDC_NORD_Day2Evening.xlsx');
