/* 
	WST
	Database: TvTrack
	Move from AMCR to TvTrack
	Event: World Championships 
			(update with each new event)

	    3416,           --ClientID
        'snooker',      --Sport
        1,              --OverWriteExisting
        841             --TvTrackProjectID
*/

/*
	You must have already run through Section 1 of Exposure Cleaning and TvTrack Generation before you can start here.

	SECTION 1
*/

--DECLARE Events To Use
	drop table if exists #SportEvents 
	CREATE TABLE  #SportEvents (
		ID INT IDENTITY(1,1),
		SportsEvent VARCHAR(100)
	)
	INSERT INTO #SportEvents VALUES
	('20260528_PDC_PL_Day17Evening/'),


-- Identify AMCR brands missing from PhotoTextTrack.Brands
	SELECT
		'' as '_',
		AMCR.Brand as BrandNameMissingFromBrands
	FROM
	(
		SELECT DISTINCT
			   BRAND
		FROM [CMGSQLNODE01\FSE.Matchroom.Toolkit_AzureModels_CombinedResults]
		WHERE Event + '/' collate Latin1_General_CI_AS IN (SELECT SportsEvent FROM #SportEvents)
	) AS AMCR
		LEFT JOIN
		(
			SELECT DISTINCT
				   BRANDNAME
			FROM dbo.[CMGSQLNODE01\FSE.PhotoTextTrack.Brands]
		) BRANDS
			ON AMCR.Brand = BRANDS.BrandName COLLATE Latin1_General_CI_AS
	WHERE BRANDS.BrandName IS NULL

/*
select * from [CMGSQLNODE01\FSE.PhotoTextTrack.Brands] where brandname like 'star%'
*/

/*
If a table is produced, open a new query, connect to PhotoTextTrack, and run this:
	INSERT INTO BRANDS VALUES
	('__'), ('__')
with the brand output within the brackets.
Then re-run the above query to ensure that there is no table produced.
*/


-- Identify AMCR assets missing from PhotoTextTrack.Touchpoints
	SELECT '' AS '_',
		   AMCR.Asset
	FROM
	(
		SELECT DISTINCT
			   Asset
		FROM [CMGSQLNODE01\FSE.Matchroom.Toolkit_AzureModels_CombinedResults]
		WHERE EVENT + '/' IN (SELECT SportsEvent COLLATE Latin1_General_CI_AS FROM #SportEvents)
	) AS AMCR
		LEFT JOIN
		(
			SELECT DISTINCT
				   TouchpointName,
				   TouchpointID
			FROM dbo.[CMGSQLNODE01\FSE.PhotoTextTrack.touchpoints]
		) Asset
			ON AMCR.Asset COLLATE Latin1_General_CI_AS = Asset.TouchpointName
	WHERE Asset.TouchpointName IS NULL

/*
SELECT * FROM dbo.[CMGSQLNODE01\FSE.PhotoTextTrack.touchpoints] WHERE TouchpointName LIKE '%unassigned%'
*/

/* 
	If a table is produced, open a new query, connect to PhotoTextTrack, and run this:
		insert into Touchpoints values
		('__'), ('__')
	with the contents of the table within the brackets.
	Then re-run the above query to ensure that there is no table produced.
*/

-- Identify missing TP_ClientID matches (before running, make sure that the client ID matches the account)
	DECLARE @clientID INT = 3416
	SELECT '' AS _,
		   MIN(amcr.TouchpointID)   as TouchPointID,
		   @clientID                as ClientID,
		   amcr.TouchpointName      as TouchpointName
	FROM
	(
		SELECT *
		FROM
		(
			SELECT DISTINCT
				   Asset
			FROM [CMGSQLNODE01\FSE.Matchroom.Toolkit_AzureModels_CombinedResults]
			WHERE EVENT + '/' IN (SELECT SportsEvent COLLATE Latin1_General_CI_AS FROM #SportEvents) --AND ModelType = 'Object Detection 1'
		) AS AMCR
			LEFT JOIN
			(
				SELECT DISTINCT
					   TouchpointName,
					   TouchpointID
				FROM dbo.[CMGSQLNODE01\FSE.PhotoTextTrack.touchpoints]
			) Asset
				ON AMCR.Asset COLLATE Latin1_General_CI_AS = Asset.TouchpointName
	) AS AMCR
		LEFT JOIN
		(
			SELECT *
			FROM dbo.[CMGSQLNODE01\FSE.PhotoTextTrack.touchpoints] TP
				INNER JOIN dbo.[CMGSQLNODE01\FSE.PhotoTextTrack.TP_Client] TPC
					ON tp.TouchpointID = Tpc.TP_ID
			WHERE Client_ID = @clientID
		) Client_TP_ID
			ON AMCR.Asset COLLATE Latin1_General_CI_AS = Client_TP_ID.TouchpointName
	WHERE Client_TP_ID.TouchpointID IS NULL
	GROUP BY amcr.TouchpointID, amcr.TouchpointName

/*
select touchpointid, client_id, touchpointname from dbo.[CMGSQLNODE01\FSE.PhotoTextTrack.touchpoints] TP
            INNER JOIN dbo.[CMGSQLNODE01\FSE.PhotoTextTrack.TP_Client] TPC
                ON tp.TouchpointID = Tpc.TP_ID
        WHERE TouchpointName like '%unassigned%'
*/

/* 
	If a table is produced, open a new query, connect to PhotoTextTrack, and run this:
		insert into TP_Client VALUES
		('__'), ('__')
	with the contents of the table within the brackets.
	Then re-run the above query to ensure that there is no table produced.
*/


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
		tvTrackProjectId INT,
	)
	INSERT INTO #variables VALUES
	(
	    3416,           --ClientID
        'snooker',      --Sport
        1,              --OverWriteExisting
        841             --TvTrackProjectID
	)


-- Check whether Programmes have been defined for that Project (Programme in TVTrack = Event in CombinedResults table) 
-- and insert any new programmes for this project
	INSERT INTO Programme 
	SELECT 
		EventName + '.xlsx' AS PR_Name,
		NULL AS StartTime,
		NULL AS EndTime,
		(SELECT tvTrackProjectID FROM #variables)  AS ProjectID,
		0 AS Uploaded
	FROM #tblevents
	WHERE EventName + '.xlsx' NOT IN (SELECT PR_Name FROM programme WHERE projectID = (SELECT tvTrackProjectID FROM #variables))


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
			FROM Programme
			WHERE ProjectID = @tvTrackProjectId
			AND Pr_Name IN (SELECT EventName + '.xlsx' FROM #tblEvents)
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
				DELETE FROM EXPOSURE WHERE ProgrammeID = @progDeleteID AND projectID = @tvTrackProjectId
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
					  SELECT REPLACE(PR_Name, '.xlsx', '')
					  FROM programme
					  WHERE projectID = @tvTrackProjectId
							AND uploaded = 1
				  )
		END


/* 
	Open 'Exposure Cleaning and TvTrack Exposure Generation' and go to the 2nd section
*/
------------------------------------------------------------------------------------------
/*
	SECTION 2
*/

-- GET EXPOSURE DATA FROM Matchroom and move to TvTrack
INSERT INTO Exposure ([BrandID],[TP_ID],[SubTP_ID],[StartTime],[EndTime],[ScreenLocation],[ScreenSize],[Duration],[ProjectID],[ProgrammeID],[ProgDetID],[AvgHits],[TotalHits])
SELECT --top 100
    E.[BrandID],E.[TP_ID],E.[SubTP_ID],E.[StartTime],E.[EndTime],E.[ScreenLocation],E.[ScreenSize],
    E.[Duration],E.[ProjectID],E.[ProgrammeID],E.[ProgDetID],E.[AvgHits],E.[TotalHits]
FROM [dbo].[CMGSQLNODE01\FSE.Matchroom.Exposure] E
    INNER JOIN Programme P
        ON E.ProgrammeID = P.ProgID
WHERE P.PR_Name IN (SELECT REPLACE(SportsEvent,'/','.xlsx') FROM #SportEvents)
-- and tp_id = 23829
order by exposureid

SELECT --top 100
    *
FROM Exposure E
    INNER JOIN Programme P
        ON E.ProgrammeID = P.ProgID
WHERE P.PR_Name IN (SELECT REPLACE(SportsEvent,'/','.xlsx') FROM #SportEvents)
order by exposureid


-- SET UPLOADED TO 1 TO RELEASE TO TvTrack App
UPDATE Programme
SET Uploaded = 1
WHERE ProgID IN (
    SELECT DISTINCT
        ProgID as ProgrammeID
    FROM Programme
    WHERE PR_Name IN (SELECT REPLACE(SportsEvent,'/','.xlsx') FROM #SportEvents)
    AND ProjectID = 841
)


-- UPDATE FIRST AND LAST INTERVAL
DECLARE @TvTrackProjectID INT = (SELECT tvTrackProjectID FROM #variables);
DROP TABLE IF EXISTS #proglist

CREATE TABLE #proglist
(
    ProgID INT
);

INSERT INTO #proglist
SELECT ProgID
FROM Programme p
-- WHERE p.projectID = @TVTrackProjectID
    WHERE PR_Name IN (SELECT REPLACE(SportsEvent,'/','.xlsx') FROM #SportEvents)
    AND ProjectID = 841
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
DECLARE @TvTrackProjectID INT = (SELECT tvTrackProjectID FROM #variables);

SELECT
    PR_Name, ProgrammeID, DATEDIFF(MI,MIN(exp.StartTime), MAX(exp.EndTime)) AS DurationMinutes, SUM(exp.Duration) as ExposureSumSeconds
    ,PRO.StartTime, PRO.EndTime
FROM Exposure EXP
    INNER JOIN Programme PRO
        ON EXP.ProgrammeID = PRO.ProgID
WHERE exp.ProjectID = @TvTrackProjectID
AND PR_Name IN (SELECT EventName + '.xlsx' FROM #tblEvents)
GROUP BY PR_Name, ProgrammeID, PRO.StartTime, PRO.EndTime