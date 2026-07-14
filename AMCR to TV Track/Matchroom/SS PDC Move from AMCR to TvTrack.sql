
SELECT PR_Name, ProgID, Uploaded, StartTime, EndTime
FROM dbo.Programme
WHERE ProjectID = 835
AND PR_Name IN (
'20260605_PDC_NORD_Day1Evening.xlsx',
'20260606_PDC_NORD_Day2Evening.xlsx'
)
ORDER BY PR_Name;

SELECT p.PR_Name, COUNT(*) AS ExposureRows
FROM dbo.Exposure e
JOIN dbo.Programme p ON p.ProgID = e.ProgrammeID
WHERE e.ProjectID = 835
AND p.PR_Name IN (
'20260605_PDC_NORD_Day1Evening.xlsx',
'20260606_PDC_NORD_Day2Evening.xlsx'
)
GROUP BY p.PR_Name;


/*
PDC
Move from AMCR to TvTrack
Event: Nordic Darts Masters


    3411,           --ClientID
    'darts',        --Sport
    1,              --OverWriteExisting
    835             --TvTrackProjectID
*/


/*
	You must have already run through Section 1 of Exposure Cleaning and TvTrack Generation before you can start here.

	SECTION 1
*/

/* ============================================================================
   CONNECTION MAP FOR THIS FILE  (updated - the dictionary-check block that
   used to live at the top of this file has been removed; it no longer exists
   here. This ENTIRE file is now DB: TVTRACK, start to finish.)

   1) Lines ~43-135  -> DB: TVTRACK  (build #tblEvents/#variables, insert
                         dbo.Programme, delete-existing-Exposure-if-overwrite logic)
                         NOTE: no "USE TvTrack" statement covers this block -
                         make sure your connection is already TvTrack before
                         you start running from the top of this file.
   2) Lines ~150 to end -> DB: TVTRACK (explicit "USE TvTrack;" statements
                         throughout confirm this - the dynamic Exposure-move
                         logic, and the diagnostic blocks near the bottom)

   This file still depends on #SportEvents, which is built in
   'Exposure Cleaning and TvTrack Generation.sql' on MATCHROOM. Run that
   file's setup first, then switch this SAME query window/connection to
   TvTrack before running anything in this file - #SportEvents/#tblEvents
   are session-scoped temp tables, so a new query tab won't have them.
   ============================================================================ */



-- >>> SWITCH CONNECTION NOW: MATCHROOM -> TVTRACK <<<
-- (no USE statement does this for you here - change the DB dropdown/connection
--  on this SAME query window so #SportEvents carries over)

drop table if exists #SportEvents
CREATE TABLE  #SportEvents (
    ID INT IDENTITY(1,1),
    SportsEvent VARCHAR(100)
)
INSERT INTO #SportEvents VALUES
('20260605_PDC_NORD_Day1Evening/'),
('20260606_PDC_NORD_Day2Evening/')

-- Inserting into TvTrack.Exposure -- creating a temporary table to hold the events
	DROP TABLE IF EXISTS #tblEvents
	CREATE TABLE #tblEvents (
		EventName VARCHAR(500)
	)
	INSERT INTO #tblEvents --VALUES
	SELECT REPLACE(SportsEvent,'/','') FROM #SportEvents

	DROP TABLE IF EXISTS #variables
	CREATE TABLE #variables (
		clientID INT,
		sport VARCHAR(50),
		overwriteexisting BIT,
		tvTrackProjectId INT
	)
	INSERT INTO #variables VALUES
	(
		3411,           --ClientID
		'darts',        --Sport
		1,              --OverWriteExisting
		835             --TvTrackProjectID
	)


-- Check whether Programmes have been defined for that Project (Programme in TVTrack = Event in CombinedResults table)
-- and insert any new programmes for this project
	INSERT INTO dbo.Programme (PR_Name, StartTime, EndTime, ProjectID, Uploaded)
	SELECT
		(EventName + '.xlsx') COLLATE SQL_Latin1_General_CP1_CI_AS AS PR_Name,
		NULL AS StartTime,
		NULL AS EndTime,
		(SELECT tvTrackProjectID FROM #variables)  AS ProjectID,
		0 AS Uploaded
	FROM #tblevents
	WHERE (EventName + '.xlsx') COLLATE SQL_Latin1_General_CP1_CI_AS NOT IN (
		SELECT PR_Name
		FROM dbo.Programme
		WHERE projectID = (SELECT tvTrackProjectID FROM #variables)
	)


--
	DECLARE @overWriteExisting INT = (SELECT overwriteexisting FROM #variables)
	DECLARE @tvTrackProjectId INT =  (SELECT tvTrackProjectID FROM #variables)

	IF (@overWriteExisting = 1)
		BEGIN
			DROP TABLE IF EXISTS #deleteprogrammes
			CREATE TABLE #deleteprogrammes (
				id INT IDENTITY(1, 1) PRIMARY KEY,
				[ProgID] INT
			)
			INSERT INTO #deleteprogrammes
			SELECT
				DISTINCT ProgID
			FROM dbo.Programme
			WHERE ProjectID = @tvTrackProjectId
			AND Pr_Name IN (SELECT (EventName + '.xlsx') COLLATE SQL_Latin1_General_CP1_CI_AS FROM #tblEvents)
			AND uploaded = 1

			DECLARE @CursorTestID INT = 1;
			DECLARE @ProgDeleteID INT = 0;
			DECLARE @RowCnt BIGINT = 0;

			-- get a count of total rows to process
			SELECT @RowCnt = COUNT(0)
			FROM #deleteprogrammes;

			WHILE @CursorTestID <= @RowCnt
			BEGIN
				SET @progDeleteID = (SELECT progID FROM #deleteprogrammes WHERE ID = @CursorTestID)
				DELETE FROM dbo.Exposure WHERE ProgrammeID = @progDeleteID AND projectID = @tvTrackProjectId
				SET @CursorTestID = @CursorTestID + 1
			END
			DROP TABLE #deleteprogrammes
		END

		IF (@overWriteExisting = 0)
		BEGIN
			--remove any events for which we do not want to overwrite results
			DELETE FROM #tblevents
			WHERE EventName IN
				  (
					  SELECT REPLACE(PR_Name, '.xlsx', '') COLLATE Latin1_General_CI_AS
					  FROM dbo.Programme
					  WHERE projectID = @tvTrackProjectId
							AND uploaded = 1
				  )
		END


/*
	Open 'Exposure Cleaning and TvTrack Exposure Generation' and go to the 2nd section
	(that file's Section 2, NOT this file's Section 2 below)
*/
------------------------------------------------------------------------------------------
/*
	SECTION 2 (of THIS file)
	Still DB: TVTRACK - confirmed/enforced by the "USE TvTrack;" right below.
	Everything from here to the end of the file runs on TvTrack.
*/

-- This is Azure SQL Database - USE cannot switch databases (Msg 40508) even as
-- a formality. Your CONNECTION must already be pointed at TvTrack before this
-- line - there is no T-SQL command that will do it for you.

-- Re-declare here so this section works standalone, even if Section 1 above
-- wasn't run in this same batch (only #variables, a temp table, is guaranteed
-- to still exist from Section 1 - local variables like @tvTrackProjectId do NOT
-- carry over between separate batch executions).
DECLARE @tvTrackProjectId INT = (SELECT tvTrackProjectID FROM #variables);
DECLARE @clientID INT = (SELECT clientID FROM #variables);

-- Optional: set to 1 only when you need full detail diagnostics.
DECLARE @RunHeavyDiagnostics BIT = 0;

-- GET EXPOSURE DATA FROM Matchroom and move to TvTrack
-- Simplified: the Matchroom-side INSERT (Exposure Cleaning file, Section 2)
-- already wrote TvTrack's own ProgID values directly into Matchroom's
-- Exposure.ProgrammeID column (see "ProgID AS ProgrammeID" in that file,
-- sourced from the linked TvTrack.Programme object). So ProgrammeID here is
-- ALREADY the TvTrack ProgID - no separate Matchroom Programme-mapping table
-- needs to be found or probed for. Direct join, no dynamic SQL required.
INSERT INTO dbo.Exposure ([BrandID],[TP_ID],[SubTP_ID],[StartTime],[EndTime],[ScreenLocation],[ScreenSize],[Duration],[ProjectID],[ProgrammeID],[ProgDetID],[AvgHits],[TotalHits])
SELECT
	E.[BrandID],E.[TP_ID],E.[SubTP_ID],E.[StartTime],E.[EndTime],E.[ScreenLocation],E.[ScreenSize],
	E.[Duration],@tvTrackProjectId,PTV.[ProgID],E.[ProgDetID],E.[AvgHits],E.[TotalHits]
FROM [dbo].[CMGSQLNODE01\FSE.Matchroom.Exposure] E
INNER JOIN dbo.Programme PTV
	ON PTV.ProgID = E.ProgrammeID
   AND PTV.ProjectID = @tvTrackProjectId
WHERE PTV.PR_Name IN (SELECT REPLACE(SportsEvent,'/','.xlsx') COLLATE SQL_Latin1_General_CP1_CI_AS FROM #SportEvents);

SELECT @@ROWCOUNT AS InsertedExposureRows;

SELECT --top 100
    *
FROM dbo.Exposure E
	INNER JOIN dbo.Programme P
        ON E.ProgrammeID = P.ProgID
WHERE E.ProjectID = @tvTrackProjectId
AND P.PR_Name IN (SELECT REPLACE(SportsEvent,'/','.xlsx') COLLATE SQL_Latin1_General_CP1_CI_AS FROM #SportEvents)
order by exposureid


-- SET UPLOADED TO 1 TO RELEASE TO TvTrack App
UPDATE dbo.Programme
SET Uploaded = 1
WHERE ProgID IN (
    SELECT DISTINCT
        ProgID as ProgrammeID
	FROM dbo.Programme
	WHERE PR_Name IN (SELECT REPLACE(SportsEvent,'/','.xlsx') COLLATE SQL_Latin1_General_CP1_CI_AS FROM #SportEvents)
	AND ProjectID = @tvTrackProjectId
)


-- UPDATE FIRST AND LAST INTERVAL
DROP TABLE IF EXISTS #proglist

CREATE TABLE #proglist
(
    ProgID INT
);

INSERT INTO #proglist
SELECT ProgID
FROM dbo.Programme p
-- WHERE p.projectID = @TVTrackProjectID
	WHERE PR_Name IN (SELECT REPLACE(SportsEvent,'/','.xlsx') COLLATE SQL_Latin1_General_CP1_CI_AS FROM #SportEvents)
	AND ProjectID = @tvTrackProjectId
    AND uploaded = 1
    AND starttime IS NULL


DECLARE @progID INT

DECLARE cur CURSOR FOR SELECT PROGID FROM #proglist
OPEN cur

FETCH NEXT FROM cur
INTO @progID

WHILE @@FETCH_STATUS = 0
BEGIN
    --INSERT FIRST AND LAST EXPOSURE TIME FOR UPLOADED FILES.  THIS IS BASED ON THE DATA AS FOUND IN THE UPLOADED FILE.
    EXEC FirstInterval @progID
    FETCH NEXT FROM cur
    INTO @progID
END
CLOSE cur
DEALLOCATE cur

DROP TABLE #proglist


-- Checking exposure table -- these values should all be >0 or something has gone wrong
SELECT
    PR_Name, ProgrammeID, DATEDIFF(MI,MIN(exp.StartTime), MAX(exp.EndTime)) AS DurationMinutes, SUM(exp.Duration) as ExposureSumSeconds
    ,PRO.StartTime, PRO.EndTime
FROM dbo.Exposure EXP
	INNER JOIN dbo.Programme PRO
        ON EXP.ProgrammeID = PRO.ProgID
WHERE exp.ProjectID = @TvTrackProjectID
AND PR_Name IN (SELECT (EventName + '.xlsx') COLLATE SQL_Latin1_General_CP1_CI_AS FROM #tblEvents)
GROUP BY PR_Name, ProgrammeID, PRO.StartTime, PRO.EndTime

-- Check field for the screen size
SELECT MAX(ScreenSize), MIN(ScreenSize)
FROM dbo.Exposure
WHERE ProjectID = @tvTrackProjectId;




--CR Check ScreenSize > 0 for all assets
IF (@RunHeavyDiagnostics = 1)
BEGIN
	SELECT E.*, P.PR_Name, B.BrandName, T.TouchpointName
	FROM dbo.Exposure E
	INNER JOIN dbo.Programme P
	ON E.ProgrammeID = P.ProgID
	INNER JOIN [CMGSQLNODE01\FSE.PhotoTextTrack.Brands] B
	ON B.BrandID = E.BrandID
	INNER JOIN [CMGSQLNODE01\FSE.PhotoTextTrack.touchpoints] T
	ON T.TouchpointID = E.TP_ID
	WHERE E.ProjectID = @tvTrackProjectId
	AND P.PR_Name IN (SELECT (EventName + '.xlsx') COLLATE SQL_Latin1_General_CP1_CI_AS FROM #tblEvents)
	ORDER BY E.ScreenSize ASC;
END

-- >>> CORE SECTION 2 LOGIC ENDS HERE. The Exposure move is done. <<<
GO

/* ============================================================================
   EVERYTHING BELOW IS OPTIONAL - manual ad-hoc verification queries left over
   from earlier troubleshooting. Not required to move the data. Each block below
   declares its own variables (separated by GO) so they don't collide with each
   other or with the core logic above - run them individually if you want to
   spot-check counts, not as one continuous block.
   ============================================================================ */

-- USE TvTrack; -- Azure SQL DB: not supported, connection must already be TvTrack

SELECT PR_Name, ProgID, Uploaded, StartTime, EndTime
FROM dbo.Programme
WHERE ProjectID = 835
AND PR_Name IN (
'20260605_PDC_NORD_Day1Evening.xlsx',
'20260606_PDC_NORD_Day2Evening.xlsx'
);

SELECT p.PR_Name,
       COUNT(*) AS ExposureRows,
       MIN(e.StartTime) AS MinStart,
       MAX(e.EndTime) AS MaxEnd,
       SUM(e.Duration) AS SumDurationSec
FROM dbo.Exposure e
JOIN dbo.Programme p
  ON p.ProgID = e.ProgrammeID
WHERE e.ProjectID = 835
AND p.PR_Name IN (
'20260605_PDC_NORD_Day1Evening.xlsx',
'20260606_PDC_NORD_Day2Evening.xlsx'
)
GROUP BY p.PR_Name;
GO



-- USE TvTrack; -- Azure SQL DB: not supported, connection must already be TvTrack
SELECT COUNT(*) AS ExposureForTheseProgrammes
FROM dbo.Exposure
WHERE ProjectID = 835
AND ProgrammeID IN (213114, 213115);

SELECT TOP 20 ProjectID, ProgrammeID, COUNT(*) AS Cnt
FROM dbo.Exposure
GROUP BY ProjectID, ProgrammeID
ORDER BY Cnt DESC;
GO
