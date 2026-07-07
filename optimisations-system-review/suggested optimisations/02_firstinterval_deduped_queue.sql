/*
Cricket AMCR -> TvTrack optimisation
Reduce unnecessary FirstInterval executions by tightening the queue.

Drop-in replacement for the #proglist build + cursor section.
This keeps behaviour but limits to:
- current project
- uploaded rows
- null starttime
- events in this run's #tblEvents list
*/

DROP TABLE IF EXISTS #proglist;

CREATE TABLE #proglist
(
    ProgID INT PRIMARY KEY
);

INSERT INTO #proglist (ProgID)
SELECT DISTINCT p.ProgID
FROM dbo.Programme p
WHERE p.ProjectID = @TVTrackProjectID
  AND p.Uploaded = 1
  AND p.StartTime IS NULL
  AND p.PR_Name IN
      (
          SELECT te.EventName + '.xlsx'
          FROM #tblEvents te
      );

DECLARE @progID INT;

DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
SELECT pl.ProgID
FROM #proglist pl
ORDER BY pl.ProgID;

OPEN cur;

FETCH NEXT FROM cur INTO @progID;

WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC FirstInterval @progID;
    FETCH NEXT FROM cur INTO @progID;
END;

CLOSE cur;
DEALLOCATE cur;
