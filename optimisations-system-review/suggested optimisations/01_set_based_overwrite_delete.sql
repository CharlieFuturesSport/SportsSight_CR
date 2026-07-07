/*
Cricket AMCR -> TvTrack optimisation
Replace overwrite delete loop with one set-based delete.

Drop-in replacement for the block that creates #deleteprogrammes,
loops with @CursorTestID, and deletes one ProgrammeID at a time.
*/

IF (@overWriteExisting = 1)
BEGIN
    ;WITH TargetProgrammes AS
    (
        SELECT p.ProgID
        FROM dbo.Programme p
        WHERE p.ProjectID = @tvTrackProjectId
          AND p.Uploaded = 1
          AND p.PR_Name IN
              (
                  SELECT te.EventName + '.xlsx'
                  FROM #tblEvents te
              )
    )
    DELETE e
    FROM dbo.Exposure e
    INNER JOIN TargetProgrammes tp
        ON tp.ProgID = e.ProgrammeID
    WHERE e.ProjectID = @tvTrackProjectId;
END;

IF (@overWriteExisting = 0)
BEGIN
    DELETE te
    FROM #tblEvents te
    WHERE te.EventName IN
    (
        SELECT REPLACE(p.PR_Name, '.xlsx', '')
        FROM dbo.Programme p
        WHERE p.ProjectID = @tvTrackProjectId
          AND p.Uploaded = 1
    );
END;
