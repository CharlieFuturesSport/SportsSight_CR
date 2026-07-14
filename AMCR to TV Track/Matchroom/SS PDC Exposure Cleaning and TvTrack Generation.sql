/* 
PDC
Exposure Cleaning and TvTrack Exposure Generation
Event: Nordic Darts Masters


    3411,           --ClientID
    'darts',        --Sport
    1,              --OverWriteExisting
    835             --TvTrackProjectID
*/
	

/*
	SECTION 1
*/

/* ============================================================================
   CONNECTION MAP FOR THIS FILE
   This ENTIRE file (Section 1 and Section 2) runs on DB: MATCHROOM.
   There is no connection switch inside this file - it never needs TvTrack
   directly (it reaches TvTrack.Programme only via the linked name
   dbo.[CMGSQLNODE01\FSE.TvTrack.Programme] at the bottom of Section 2).

   FULL WORKFLOW ORDER (across both files - the "open X" comments below jump
   back and forth, so follow this order rather than the file order):
     1. THIS FILE, Section 1            -> MATCHROOM (clean brands/assets, build
                                            #frame_results / #duration_grouped)
     2. 'Move from AMCR to TvTrack.sql'
        first section (dictionary checks
        + Programme insert)             -> MATCHROOM, then switch to TVTRACK
                                            partway through (see that file's own
                                            connection map at its top)
     3. THIS FILE, Section 2            -> MATCHROOM (asset renames + INSERT INTO
                                            EXPOSURE - requires the TvTrack
                                            Programme rows created in step 2 to
                                            already exist, since it joins to them
                                            via the linked name)
     4. 'Move from AMCR to TvTrack.sql'
        Section 2                       -> TVTRACK (moves data from Matchroom's
                                            linked Exposure table into TvTrack's
                                            dbo.Exposure/dbo.Programme)
   ============================================================================ */


	--	Asset and brand cleaning 


-- CREATE TABLE OF EVENTS (if it doesn't seem to be working, check if there is a / at the end of each event name)
	drop table if exists #SportEvents
	CREATE TABLE  #SportEvents (
		ID INT IDENTITY(1,1),
		SportsEvent VARCHAR(100)
	)
	INSERT INTO #SportEvents VALUES
	('20260605_PDC_NORD_Day1Evening/'),
	('20260606_PDC_NORD_Day2Evening/')



-- FIND BRAND AND ASSETS
	SELECT
		Brand, Asset, COUNT(distinct Filename)
	FROM Toolkit_AzureModels_CombinedResults
	WHERE Event + '/' IN (SELECT SportsEvent FROM #SportEvents)
	GROUP BY Brand, Asset
	order by brand, asset


-- CLEAN TERMS (copy and change as necessary)
	UPDATE Toolkit_AzureModels_CombinedResults
	SET 
		Brand = 'Strachan'
	WHERE EVENT + '/' in (select sportsevent from #SportEvents)
	-- AND Brand = 'Strachan'
	AND Brand IN (
					'Strachan - 6811','Strachan - Static Signage'
	)



	--	Generating TvTrack Exposure in Matchroom


-- DECLARE VARIABLES TO USE (check that the values below match the account: Sport, ClientID, and TvTrackProjectID)
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
		3411,           --ClientID
		'darts',        --Sport
		1,              --OverWriteExisting
		835             --TvTrackProjectID
	)


-- CREATE Frame Results Temp Table
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


-- CREATE LINE BY LINE FOR FRAME RESULTS -- this is a second by second table
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
				FROM Toolkit_AzureModels_CombinedResults
				WHERE [event] + '/' COLLATE Latin1_General_CI_AS IN (SELECT SportsEvent FROM #SportEvents)
				AND (Asset IS NOT NULL)
				AND asset <> 'Exclude'
				AND (Sport = @sport)
				AND (ModelType like '%Asset%' OR ModelType = 'Brand')
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
					FROM Toolkit_AzureModels_CombinedResults
					WHERE [event] + '/' COLLATE Latin1_General_CI_AS IN (SELECT SportsEvent FROM #SportEvents)
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


-- Update the duration cluster -- this is to calculate what group of exposure the lines belong to by reporting the frame number of the first frame
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


--	SELECT TOP 100 * FROM #frame_results ORDER BY EVENT, FRAMENUMBER, duration_cluster


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
        [event], brand, touchpoint, timeonscreen, duration ,
        screensize, start_frame, total_hits, CountA, CountB, CountC, CountD, CountE
    )
    SELECT /* TOP 1000 */ [event],
           brand,
           touchpoint,
           MIN(DATEADD(ss, duration_cluster, starttimetime)) as timeonscreen,
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


/*
	Open 'Move from AMCR to TvTrack' and go to the first section
*/
--------------------------------------------------------------------
/*
	SECTION 2
	Restored from the clean WST original template (CR-ORIGIONAL-SS WST
	Exposure Cleaning and TvTrack Generation.sql) - this section was missing
	from this file. Uses the same #variables values already built in Section 1
	above (ClientID 3411, TvTrackProjectID 835), so no values need editing here.
*/

-- Insert into exposure
	DECLARE @TvTrackProjectID INT = (SELECT tvTrackProjectID FROM #variables);
	DECLARE @clientID INT = (SELECT clientID FROM #variables);

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
		@TVTrackProjectID AS ProjectID,
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
			ON Brands.BrandName COLLATE SQL_Latin1_General_CP1_CI_AS = #duration_grouped.Brand
		INNER JOIN
		(
			SELECT
				TP_ID,
				touchpointname
			FROM dbo.[CMGSQLNODE01\FSE.PhotoTextTrack.Touchpoints] AS tp
				INNER JOIN dbo.[CMGSQLNODE01\FSE.PhotoTextTrack.TP_Client] AS tpc
					ON tp.TouchpointID = TPc.TP_ID
			WHERE Client_ID = @clientID
		) AS Touchpoints
			ON Touchpoints.TouchpointName COLLATE SQL_Latin1_General_CP1_CI_AS = #duration_grouped.touchpoint
		INNER JOIN dbo.[CMGSQLNODE01\FSE.TvTrack.Programme] Programme
			ON Programme.PR_Name COLLATE SQL_Latin1_General_CP1_CI_AS = #duration_grouped.Event + '.xlsx'
	WHERE Programme.ProjecTID = @TVTrackProjectID
	ORDER BY id

/*
	Open 'Move from AMCR to TvTrack'
*/
----------------------------------------
