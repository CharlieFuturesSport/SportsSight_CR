/*
PDC - Move from AMCR to TvTrack: candidate-search optimisation

The "core" logic in 'SS PDC Move from AMCR to TvTrack.sql' loops through every
object/synonym in TvTrack matching %Programme%/%Prog%, and for each candidate,
runs a live cross-server query against Matchroom's Exposure table just to test
whether it's the right join target. If several near-miss candidates exist,
that's several slow linked-server round trips before it finds the real one.

Run on TvTrack. This finds the same answer directly, in one query, without the
loop or any cross-server calls - inspect the result, then hardcode the winning
object name into the INSERT in the main script instead of re-probing every run.
*/

SELECT
    QUOTENAME(s.name) + '.' + QUOTENAME(t.name) AS CandidateObject,
    t.type_desc,
    CASE
        WHEN t.name LIKE '%CMGSQLNODE01\FSE.Matchroom.Programme%' THEN 0
        WHEN t.name LIKE '%Matchroom%Programme%' THEN 1
        WHEN t.name LIKE '%Matchroom%' THEN 2
        WHEN t.name LIKE '%Programme%' THEN 2
        ELSE 5
    END AS Priority
FROM sys.objects t
INNER JOIN sys.schemas s
    ON s.schema_id = t.schema_id
WHERE t.type IN ('U','V')
  AND NOT (s.name = 'dbo' AND t.name = 'Programme')
  AND (
        EXISTS (SELECT 1 FROM sys.columns c WHERE c.object_id = t.object_id AND c.name = 'ProgID')
        OR EXISTS (SELECT 1 FROM sys.columns c WHERE c.object_id = t.object_id AND c.name = 'ProgDetID')
      )
  AND (
        EXISTS (SELECT 1 FROM sys.columns c WHERE c.object_id = t.object_id AND c.name = 'PR_Name')
        OR EXISTS (SELECT 1 FROM sys.columns c WHERE c.object_id = t.object_id AND c.name = 'PRName')
      )

UNION ALL

SELECT
    QUOTENAME(s.name) + '.' + QUOTENAME(sn.name) AS CandidateObject,
    'SYNONYM' AS type_desc,
    CASE
        WHEN sn.name LIKE '%CMGSQLNODE01\FSE.Matchroom.Programme%' THEN 0
        WHEN sn.name LIKE '%Matchroom%Programme%' THEN 1
        WHEN sn.name LIKE '%Matchroom%' THEN 2
        WHEN sn.name LIKE '%Programme%' THEN 3
        ELSE 9
    END AS Priority
FROM sys.synonyms sn
INNER JOIN sys.schemas s
    ON s.schema_id = sn.schema_id
WHERE sn.name LIKE '%Prog%'
   OR sn.name LIKE '%Program%'
   OR sn.base_object_name LIKE '%Matchroom%'
   OR sn.base_object_name LIKE '%Prog%'

ORDER BY Priority, CandidateObject;

/*
Once you've picked the right CandidateObject from the result above, replace the
whole #ProgrammeCandidates / cursor / probe-loop block in
'SS PDC Move from AMCR to TvTrack.sql' (lines ~163-338 at time of writing) with:

    DECLARE @SrcProgrammeObject NVARCHAR(300) = N'<paste chosen object here>';
    DECLARE @SrcJoinExpr NVARCHAR(200) = N'E.ProgrammeID = PSRC.ProgID';   -- or ProgDetID, whichever matched
    DECLARE @SrcNameExpr NVARCHAR(200) = N'PSRC.PR_Name';                 -- or PSRC.PRName, whichever matched

This skips the loop and every cross-server probe entirely - the INSERT that
follows already uses these three variables, so no other changes are needed.
*/
