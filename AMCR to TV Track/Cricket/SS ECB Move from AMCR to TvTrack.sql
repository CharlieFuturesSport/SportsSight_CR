/*
	Inserting to the Exposure Table - TvTrack Upload Process
	Database: TvTrack

	Account: ECB

		29,				--ClientID
		'cricket',      --Sport
		1,              --OverWriteExisting
		1042            --TvTrackProjectID -- ECB Midseason 2026
*/

	-- Phase 1 -- Checking for a TvTrack project
-- Is there already a TvTrack project? (You can check the projects table in TvTrack db). If not, follow the following steps. 

/*
 Check for Client ID by running this in a new query in the COSTS db
		SELECT
			*
		FROM Client
		WHERE Client_Name LIKE '%ecb%'
*/

-- Check for project name
	SELECT
    *
	FROM Project
	WHERE ProjectName like '%ecb%'


-- If both above are empty, launch the TvTrack application and create.
-- "Z:\Shared\OCT\LDN\FSE\FSEData\technology team\Azure App Versions\TVTrack2.0\UK\setup.exe"



INSERT INTO dbo.TP_Client (TP_ID, Client_ID)
SELECT 9746, 29
WHERE NOT EXISTS (
    SELECT 1
    FROM dbo.TP_Client
    WHERE TP_ID = 9746
      AND Client_ID = 29
);



	-- Phase 2 -- PhotoTextTrack - Brand/TP/TP_Client Updates

/*
Once all exposure has been generated and inserted to the Toolkit_AzureModel_CombinedResults table it will then be moved to INF database [dbo].[TvTrack].

Before we do this we must ensure all Brands, Assets (Touchpoints) and and Touchpoint - ClientIDs have been created in the INF database [dbo].[PhotoTextTrack].
	
	Raw exposure seconds live in the client INF database - table: Toolkit_AzureModels_CombinedResults.
	This line by line data needs to be transformed and sent to the 'exposure' table in inf database [dbo].[TvTrack].
	TvTrack.exposure table only contains BrandID, TouchpointID. No brand or asset names. The dictionary table is stored in the INF database [dbo].[PhotoTextTrack]. 
		Tables:
			Brands
			Touchpoints
			TP_Client.
What is a Touchpoint - Client ID? All touchpoints need to be assigned to a client ID. So 'LED ECB Arc' belongs to ECB, So a link of TouchpointID 33467 to client ID 29
So, this notebook covers how we check the AMCR for missing brands, touchpoints and Touchpoint clients IDs, and how we insert. 
*/

-- Declare SportsEvents to work with
	drop table if exists #SportEvents
	CREATE TABLE  #SportEvents (
		ID INT IDENTITY(1,1),
		SportsEvent VARCHAR(100)
	)
	INSERT INTO #SportEvents VALUES
	('12729_220526_Mens_Blast_Group_Som_v_Ham')



-- Identify AMCR brands missing from PhotoTextTrack/Brands
	SELECT
		'' as '_',
		AMCR.Brand as BrandNameMissingFromBrands
	FROM
	(
		SELECT DISTINCT
			   BRAND
		FROM [CMGSQLNODE01\FSE.ECB.Toolkit_AzureModels_CombinedResults]
		WHERE Event collate Latin1_General_CI_AS IN (SELECT SportsEvent FROM #SportEvents)
	) AS AMCR
		LEFT JOIN
		(
			SELECT DISTINCT
				   BRANDNAME
			FROM dbo.[CMGSQLNODE01\FSE.PhotoTextTrack.Brands]
		) BRANDS
			ON AMCR.Brand = BRANDS.BrandName COLLATE Latin1_General_CI_AS
	WHERE BRANDS.BrandName IS NULL

/* runs in tvtrack
select * from [CMGSQLNODE01\FSE.PhotoTextTrack.Brands] where brandname like 'star%'
*/

/*
If a table is produced, open a new query, connect to PhotoTextTrack, and run this:
	INSERT INTO BRANDS VALUES
	('__'), ('__')
with the brand output within the brackets.
Then re-run the above query to ensure that there is no table produced.
*/


-- Identifying AMCR assets missing from PhotoTextTrack.Touchpoints
	SELECT '' AS '_',
		   AMCR.Asset,
		   '(''' + AMCR.Asset + '''),'
	FROM
	(
		SELECT DISTINCT
			   Asset
		FROM [CMGSQLNODE01\FSE.ECB.Toolkit_AzureModels_CombinedResults]
		WHERE EVENT IN (SELECT SportsEvent COLLATE Latin1_General_CI_AS FROM #SportEvents)
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

/* runs in tvtrack
SELECT * FROM dbo.[CMGSQLNODE01\FSE.PhotoTextTrack.touchpoints] WHERE TouchpointName = 'jersey - shirt front - sleeve'
*/

/*
If a table is produced, open a new query, connect to PhotoTextTrack, and run this:
	INSERT INTO Touchpoints VALUES
	('__'), ('__')
with the brand output within the brackets.
Then re-run the above query to ensure that there is no table produced.
*/


-- Identifying missing TP_ClientID matches -- you must define the client ID as a paramenter for this code block
	DECLARE @clientID INT = 29
	SELECT '' AS _,
		   MIN(amcr.TouchpointID)   as TouchPointID,
		   @clientID                as ClientID,
		   amcr.TouchpointName      as TouchpointName,
		   '(' + cast(AMCR.TouchpointID as varchar(50)) + ',' + cast(@clientID as varchar(5)) + '),'
	FROM
	(
		SELECT *
		FROM
		(
			SELECT DISTINCT
				   Asset
			FROM [CMGSQLNODE01\FSE.ECB.Toolkit_AzureModels_CombinedResults]
			WHERE EVENT IN (SELECT SportsEvent COLLATE Latin1_General_CI_AS FROM #SportEvents) --AND ModelType = 'Object Detection 1'
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

/* runs in tvtrack
select touchpointid, client_id, touchpointname from dbo.[CMGSQLNODE01\FSE.PhotoTextTrack.touchpoints] TP
            INNER JOIN dbo.[CMGSQLNODE01\FSE.PhotoTextTrack.TP_Client] TPC
                ON tp.TouchpointID = Tpc.TP_ID
        WHERE TouchpointName like '%unassigned%'
*/

/* 
	If a table is produced, open a new query, connect to PhotoTextTrack, and run this:
		insert into TP_Client VALUES
		('__'), ('__')
	with the contents of the last column within the brackets.
	Then re-run the above query to ensure that there is no table produced.
*/



INSERT INTO dbo.Brands (BrandName)
SELECT v.BrandName
FROM (VALUES
    ('Aironix'),
    ('Chaucer'),
    ('Connect it'),
    ('Mitchell Associates'),
    ('Pangea'),
    ('Synertec'),
    ('Thatchers'),
    ('Vitality Blast'),
    ('WPA Health')
) v(BrandName)
WHERE NOT EXISTS (
    SELECT 1
    FROM dbo.Brands b
    WHERE LTRIM(RTRIM(b.BrandName)) = LTRIM(RTRIM(v.BrandName))
);


	-- Phase 3 - Inserting into TvTrack.Exposure

-- Create the temporary table
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
		29,           --ClientID
		'cricket',          --Sport
		1,              --OverWriteExisting
		1042              --TvTrackProjectID
	)


-- Check whether Programmes have been defined for that project (Programme in TvTrack = Event in AMCR)
	INSERT INTO Programme 
	SELECT
		EventName + '.xlsx' AS PR_Name,
		NULL AS StartTime,
		NULL AS EndTime,
		(SELECT tvTrackProjectID FROM #variables)  AS ProjectID,
		0 AS Uploaded
	FROM #tblevents
	WHERE EventName + '.xlsx' NOT IN (SELECT PR_Name FROM programme WHERE projectID = (SELECT tvTrackProjectID FROM #variables))


-- Insert any new programmes for this project
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


-- Frame results
	DROP TABLE IF EXISTS #frame_results

	CREATE TABLE #frame_results (
		id INT IDENTITY(1, 1) PRIMARY KEY,
		[event] VARCHAR(150),
		framenumber INT,
		brand VARCHAR(50),
		touchpoint VARCHAR(100),
		number_hits INT,
		max_area FLOAT,
		location_list VARCHAR(1000),
		Duration_Cluster INT,
		CountA AS LEN(location_list) - LEN(REPLACE(location_list, 'A', '')),
		CountB AS LEN(location_list) - LEN(REPLACE(location_list, 'B', '')),
		CountC AS LEN(location_list) - LEN(REPLACE(location_list, 'C', '')),
		CountD AS LEN(location_list) - LEN(REPLACE(location_list, 'D', '')),
		CountE AS LEN(location_list) - LEN(REPLACE(location_list, 'E', '')),
		starttimetime AS CASE
							 WHEN ISNUMERIC(RIGHT(event, 4)) = 1 THEN
								 CONVERT(DATETIME, SUBSTRING(event, LEN(event) - 3, 2) + ':' + RIGHT(event, 2), 0)
							 ELSE
								 CONVERT(DATETIME, '00:00:01')
						 END
	)


-- CREATE LINE BY LINE FOR FRAME RESULTS (this should not be 0)
	DECLARE @sport VARCHAR(50) = (SELECT sport FROM #variables)

	INSERT INTO #frame_results
		(
			[event],framenumber,brand,touchpoint,number_hits,max_area,location_list,Duration_Cluster
		)
	SELECT --*
		CASE
			WHEN OD.Event IS NULL 
				THEN OCR.Event
			ELSE OD.Event
		END AS Event,
		CASE WHEN OD.[Filename] IS NULL
			THEN OCR.[Filename]
			ELSE OD.[Filename]
		END AS Filename,
		CASE WHEN OD.Brand IS NULL
			THEN OCR.Brand
			ELSE OD.Brand
		END AS Brand,
		CASE WHEN OD.Asset IS NULL
			THEN OCR.Asset
			ELSE OD.Asset
		END AS Asset,
		CASE WHEN (OD.Hits IS NOT NULL AND (OD.Hits >= OCR.Hits OR OCR.Hits IS NULL))
			THEN OD.Hits
			ELSE OCR.Hits
		END AS Hits,
		CASE WHEN (OD.Hits IS NOT NULL AND (OD.Hits >= OCR.Hits OR OCR.Hits IS NULL))
			THEN OD.ScreenSize
			ELSE OCR.ScreenSize
		END AS ScreenSize,
		CASE WHEN (OD.Hits IS NOT NULL AND (OD.Hits >= OCR.Hits OR OCR.Hits IS NULL))
			THEN OD.ScreenLocation
			ELSE OCR.ScreenLocation
		END AS ScreenLocation,
		NULL AS Duration_Cluster
	FROM
	(
		SELECT
			Event,
			cast(LEFT(Filename, CHARINDEX('.',(Filename)) - 1) AS INT) AS Filename,
			Brand,
			Asset,
			COUNT(Event) AS Hits,
			MAX(Screensize) AS ScreenSize,
			STRING_AGG(CAST(screenlocation AS VARCHAR(MAX)), ',')within GROUP(ORDER BY screenlocation ASC) as ScreenLocation
		FROM 
			(
				SELECT Event, [Filename], Brand, Asset, ScreenSize, ScreenLocation
				FROM dbo.[CMGSQLNODE01\FSE.ECB.Toolkit_AzureModels_CombinedResults]
				WHERE [event] COLLATE Latin1_General_CI_AS IN (SELECT SportsEvent FROM #SportEvents)
				AND (Asset IS NOT NULL)
				AND asset <> 'Exclude'
				AND (Sport = @sport)
				AND ModelType like '%Asset%'
			) AS ODresults
		GROUP BY
			Event, [Filename], Brand, Asset
	) OD
		FULL OUTER JOIN
		(
			SELECT
				Event,
				cast(LEFT(Filename, CHARINDEX('.',(Filename)) - 1) AS INT) AS Filename,
				Brand,
				Asset,
				COUNT(Event) AS Hits,
				MAX(Screensize) AS ScreenSize,
				STRING_AGG(CAST(screenlocation AS VARCHAR(MAX)), ',')within GROUP(ORDER BY screenlocation ASC) as ScreenLocation
			FROM 
				(
					SELECT Event, [Filename], Brand, Asset, ScreenSize, ScreenLocation
					FROM dbo.[CMGSQLNODE01\FSE.ECB.Toolkit_AzureModels_CombinedResults]
					WHERE [event] COLLATE Latin1_General_CI_AS IN (SELECT SportsEvent FROM #SportEvents)
					AND (Asset IS NOT NULL)
					AND asset <> 'Exclude'
					AND (Sport = @sport)
					AND ModelType like '%OCR%'
					AND ModelType not like '%Asset%'
				) AS OCRresults
			GROUP BY
				Event, [Filename], Brand, Asset
		) OCR
		ON OD.Event = OCR.Event
		AND OD.[Filename] = OCR.[Filename]
		AND OD.Brand = OCR.Brand
		AND OD.[Asset] = OCR.[Asset]
	ORDER BY Event, brand, asset, filename


-- Update duration cluster -- this is to calculate what group of exposure the lines belond to by reporting the frame number of the first frame
	DECLARE @i INT;
	DECLARE @cap INT
	DECLARE @prevframe INT
	DECLARE @currentframe INT

	SET @i = 2
	SET @cap = (SELECT COUNT(*)FROM #frame_results) + 1

	SET NOCOUNT ON;

			--updates the first row's value
	UPDATE #frame_results
	SET duration_cluster = (SELECT framenumber FROM #frame_results WHERE id = 1) WHERE id = 1

			--loop through each row to calculate the duration cluster
	WHILE @i < @cap
	BEGIN
		SET @currentframe = (SELECT framenumber FROM #frame_results WHERE id = @i)
		SET @prevframe = (SELECT framenumber FROM #frame_results WHERE id = (@i - 1))

		UPDATE #frame_results
		SET duration_cluster = (CASE WHEN @currentframe = @prevframe + 1 THEN ( SELECT duration_cluster FROM #frame_results WHERE id = (@i - 1)) ELSE @currentframe END)
		WHERE id = @i
		SET @i = @i + 1
	END

	SELECT COUNT(1) FROM #frame_results

	SET NOCOUNT OFF;


-- SELECT TOP 100 * FROM #frame_results order by event, framenumber, duration_cluster


-- Group each single exposure row into the frame of first appearance
    DROP TABLE IF EXISTS #duration_grouped
    CREATE TABLE #duration_grouped
    (
        id INT IDENTITY(1, 1) PRIMARY KEY,
        [event] VARCHAR(100),
        brand VARCHAR(50),
        touchpoint VARCHAR(100),
        timeonscreen DATETIME,
        duration INT,
        screensize DECIMAL(10, 4),
        start_frame INT,
        total_hits INT,
        CountA INT,
        CountB INT,
        CountC INT,
        CountD INT,
        CountE INT,
        avg_hits AS cast(Total_hits AS FLOAT) / cast(duration AS FLOAT),
        loc_single AS CASE
                          WHEN CountA >= CountB
                               AND CountA >= CountC
                               AND CountA >= CountD
                               AND CountA >= CountE THEN
                              'A'
                          WHEN CountB >= CountC
                               AND CountB >= CountD
                               AND CountB >= CountE THEN
                              'B'
                          WHEN CountC >= CountD
                               AND CountC >= CountE THEN
                              'C'
                          WHEN CountD >= CountE THEN
                              'D'
                          ELSE
                              'E'
                      END
    )

    INSERT INTO #duration_grouped (
        [event], brand, touchpoint, timeonscreen, duration, 
        screensize, start_frame, total_hits, CountA, CountB, CountC, CountD, CountE
    )
    SELECT /* TOP 1000 */ [event],
           brand,
           touchpoint,
           MIN(DATEADD(ss, duration_cluster, starttimetime)) AS timeonscreen,
           COUNT(*),
           MAX(max_area * 100),
           duration_cluster,
           SUM(number_hits),
           SUM(CountA) AS CountA,
           SUM(CountB) AS CountB,
           SUM(CountC) AS CountC,
           SUM(CountD) AS CountD,
           SUM(CountE) AS CountE
    FROM #frame_results
    GROUP BY [event],
             brand,
             touchpoint,
             duration_cluster
    ORDER BY Event, Brand, touchpoint, timeonscreen, duration_cluster


-- Insert into exposure
	INSERT INTO EXPOSURE
	SELECT 
		BrandID,
		TP_ID,
		NULL AS SubTP_ID,
		TimeOnScreen AS StartTime,
		DATEADD(ss, #duration_grouped.duration, timeonscreen) AS EndTime,
		Loc_Single AS ScreenLocation,
		ScreenSize,
		#duration_grouped.Duration,
		@tvTrackProjectId AS ProjectID,
		ProgID AS ProgrammeID,
		NULL AS ProgDetID,
		Avg_hits,
		Total_Hits
	FROM #duration_grouped
		INNER JOIN
		(
			SELECT
				BrandName,
				MIN(BrandID) AS BrandID
			FROM dbo.[CMGSQLNODE01\FSE.PhotoTextTrack.Brands]
			GROUP BY Brandname
		) AS Brands
			ON Brands.BrandName = #duration_grouped.Brand
		INNER JOIN
		(
			SELECT
				TP_ID,
				touchpointname
			FROM dbo.[CMGSQLNODE01\FSE.PhotoTextTrack.Touchpoints] AS tp
				INNER JOIN dbo.[CMGSQLNODE01\FSE.PhotoTextTrack.TP_Client] AS tpc
					ON tp.TouchpointID = TPc.TP_ID
			WHERE Client_ID = (SELECT clientID FROM #variables)
		) AS Touchpoints
			ON Touchpoints.TouchpointName = #duration_grouped.touchpoint
		INNER JOIN Programme
			ON Programme.PR_Name = #duration_grouped.Event + '.xlsx'
	WHERE Programme.ProjecTID = @tvTrackProjectId
	ORDER BY id


-- Update programme uploaded field to 1
	UPDATE programme
	SET uploaded = 1
	WHERE ProgID IN
		  (
			  SELECT DISTINCT
					 ProgID AS ProgrammeID
			  FROM #duration_grouped
				  INNER JOIN Programme
					  ON Programme.PR_Name = #duration_grouped.Event + '.xlsx'
			  WHERE Programme.ProjecTID = @tvTrackProjectId
		  )


-- Update first and last exposure
	DROP TABLE IF EXISTS #proglist

	CREATE TABLE #proglist
	(
		ProgID INT
	);

	INSERT INTO #proglist
	SELECT ProgID
	FROM Programme p
	WHERE p.projectID = @tvTrackProjectId
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

		-- DROP TABLE #proglist
		-- DROP TABLE #frame_results
		-- DROP TABLE #duration_grouped


-- Phase 4 -- Checking exposure table
DECLARE @phase4ProjectId INT = NULL;
DECLARE @phase4EventName VARCHAR(100) = '12729_220526_Mens_Blast_Group_Som_v_Ham';

IF OBJECT_ID('tempdb..#variables') IS NOT NULL
BEGIN
	SELECT TOP 1 @phase4ProjectId = tvTrackProjectId
	FROM #variables;
END

IF @phase4ProjectId IS NULL
BEGIN
	SET @phase4ProjectId = 1042;
END

SELECT
    PR_Name, ProgrammeID, DATEDIFF(MI,MIN(exp.StartTime), MAX(exp.EndTime)) AS DurationMinutes, SUM(exp.Duration) as ExposureSumSeconds
    ,PRO.StartTime, PRO.EndTime
FROM Exposure EXP
    INNER JOIN Programme PRO
        ON EXP.ProgrammeID = PRO.ProgID
WHERE exp.ProjectID = @phase4ProjectId
AND (
	(
		OBJECT_ID('tempdb..#tblEvents') IS NOT NULL
		AND PR_Name IN (SELECT EventName + '.xlsx' FROM #tblEvents)
	)
	OR
	(
		OBJECT_ID('tempdb..#tblEvents') IS NULL
		AND PR_Name = @phase4EventName + '.xlsx'
	)
)
GROUP BY PR_Name, ProgrammeID, PRO.StartTime, PRO.EndTime


-- Check field for the screen size
SELECT MAX(ScreenSize), MIN(ScreenSize) FROM Exposure WHERE ProjectID = @phase4ProjectId