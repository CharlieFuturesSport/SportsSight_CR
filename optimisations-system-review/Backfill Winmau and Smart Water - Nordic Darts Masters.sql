/*
PDC - Nordic Darts Masters - ONE-OFF BACKFILL
Event: Nordic Darts Masters (20260605_PDC_NORD_Day1Evening, 20260606_PDC_NORD_Day2Evening)

WHY THIS EXISTS:
The original run of 'SS PDC Exposure Cleaning and TvTrack Generation.sql' silently
dropped two brands - Winmau (Dart Board) and Smart Water (Water Bottle) - because
their raw detections are tagged ModelType = 'Brand', which the #frame_results build
only matched on '%Asset%' or '%OCR%'. That filter has been fixed in the main script
for future events. This script backfills JUST those two brands for THIS event,
without touching or duplicating the 10,430 rows already correctly loaded for
Mr Vegas / Fireball / Falken Tyres / Werner Ladders.

Winmau BrandID:      22407
Smart Water BrandID: 22765

RUN ORDER:
  PART 1 below -> MATCHROOM
  PART 2 below -> TVTRACK (separate connection/session - rebuild nothing extra,
                  it only needs #SportEvents which PART 1 already built, but
                  since Azure SQL DB drops temp tables on every db switch, if
                  #SportEvents doesn't exist when you get to PART 2, just rebuild
                  it there too - the INSERT VALUES block is included again below
                  for convenience).
*/


/* ============================================================================
   PART 1 - MATCHROOM
   ============================================================================ */

drop table if exists #SportEvents
CREATE TABLE  #SportEvents (
	ID INT IDENTITY(1,1),
	SportsEvent VARCHAR(100)
)
INSERT INTO #SportEvents VALUES
('20260605_PDC_NORD_Day1Evening/'),
('20260606_PDC_NORD_Day2Evening/')

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

-- Same #frame_results build as the main script, but scoped to just these 2 brands
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

DECLARE @sport VARCHAR(50) = (SELECT sport FROM #variables)

INSERT INTO #frame_results
	(
		[event],framenumber,brand,touchpoint,number_hits,max_area,location_list,Duration_Cluster
	)
SELECT
	CASE WHEN OD.Event IS NULL THEN OCR.Event ELSE OD.Event END AS Event,
	CASE WHEN OD.[Filename] IS NULL THEN OCR.[Filename] ELSE OD.[Filename] END AS Filename,
	CASE WHEN OD.Brand IS NULL THEN OCR.Brand ELSE OD.Brand END AS Brand,
	CASE WHEN OD.Asset IS NULL THEN OCR.Asset ELSE OD.Asset END AS Asset,
	CASE WHEN (OD.Hits IS NOT NULL AND (OD.Hits >= OCR.Hits OR OCR.Hits IS NULL)) THEN OD.Hits ELSE OCR.Hits END AS Hits,
	CASE WHEN (OD.Hits IS NOT NULL AND (OD.Hits >= OCR.Hits OR OCR.Hits IS NULL)) THEN OD.ScreenSize ELSE OCR.ScreenSize END AS ScreenSize,
	CASE WHEN (OD.Hits IS NOT NULL AND (OD.Hits >= OCR.Hits OR OCR.Hits IS NULL)) THEN OD.ScreenLocation ELSE OCR.ScreenLocation END AS ScreenLocation,
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
		STRING_AGG(CAST(screenlocation AS VARCHAR(MAX)), ',') within GROUP(ORDER BY screenlocation ASC) as ScreenLocation
	FROM
		(
			SELECT Event, [Filename], Brand, Asset, ScreenSize, ScreenLocation
			FROM Toolkit_AzureModels_CombinedResults
			WHERE [event] + '/' COLLATE Latin1_General_CI_AS IN (SELECT SportsEvent FROM #SportEvents)
			AND (Asset IS NOT NULL)
			AND asset <> 'Exclude'
			AND (Sport = @sport)
			AND (ModelType like '%Asset%' OR ModelType = 'Brand')
			AND Brand IN ('Winmau', 'Smart Water')   -- <<< backfill scope
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
			STRING_AGG(CAST(screenlocation AS VARCHAR(MAX)), ',') within GROUP(ORDER BY screenlocation ASC) as ScreenLocation
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
				AND Brand IN ('Winmau', 'Smart Water')   -- <<< backfill scope
			) AS OCRresults
		GROUP BY
			Event, [Filename], Brand, Asset
	) OCR
	ON OD.Event = OCR.Event
	AND OD.[Filename] = OCR.[Filename]
	AND OD.Brand = OCR.Brand
	AND OD.[Asset] = OCR.[Asset]
ORDER BY Event, brand, asset, filename

-- Duration cluster pass (identical to main script)
DECLARE @i INT;
DECLARE @cap INT
DECLARE @prevframe INT
DECLARE @currentframe INT

SET @i = 2
SET @cap = (SELECT COUNT(*) FROM #frame_results) + 1

SET NOCOUNT ON;

UPDATE #frame_results
SET duration_cluster = (SELECT framenumber FROM #frame_results WHERE id = 1) WHERE id = 1

WHILE @i < @cap
BEGIN
	SET @currentframe = (SELECT framenumber FROM #frame_results WHERE id = @i)
	SET @prevframe = (SELECT framenumber FROM #frame_results WHERE id = (@i - 1))

	UPDATE #frame_results
	SET duration_cluster = (CASE WHEN @currentframe = @prevframe + 1 THEN (SELECT duration_cluster FROM #frame_results WHERE id = (@i - 1)) ELSE @currentframe END)
	WHERE id = @i
	SET @i = @i + 1
END

SELECT COUNT(1) AS FrameResultRows_ShouldBeWinmauSmartWaterOnly FROM #frame_results

SET NOCOUNT OFF;

-- Group into exposure segments (identical to main script)
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
					  WHEN CountA >= CountB AND CountA >= CountC AND CountA >= CountD AND CountA >= CountE THEN 'A'
					  WHEN CountB >= CountC AND CountB >= CountD AND CountB >= CountE THEN 'B'
					  WHEN CountC >= CountD AND CountC >= CountE THEN 'C'
					  WHEN CountD >= CountE THEN 'D'
					  ELSE 'E'
				  END
)

INSERT INTO #duration_grouped (
	[event], brand, touchpoint, timeonscreen, duration ,
	screensize, start_frame, total_hits, CountA, CountB, CountC, CountD, CountE
)
SELECT [event],
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

-- Insert into Matchroom's local Exposure table (identical to main script Section 2)
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
WHERE Programme.ProjectID = @TVTrackProjectID
ORDER BY id

SELECT @@ROWCOUNT AS RowsInsertedIntoMatchroomExposure_ShouldBeWinmauSmartWaterOnly

-- >>> STOP HERE. Do not select/run past this GO in one go. <<<
-- Switch your connection to TvTrack now, THEN select from below this line
-- to the end of the file and run it as its own, separate execution.
GO

/* ============================================================================
   PART 2 - TVTRACK
   Switch your connection to TvTrack before running this part.
   ============================================================================ */

drop table if exists #SportEvents
CREATE TABLE  #SportEvents (
	ID INT IDENTITY(1,1),
	SportsEvent VARCHAR(100)
)
INSERT INTO #SportEvents VALUES
('20260605_PDC_NORD_Day1Evening/'),
('20260606_PDC_NORD_Day2Evening/')

DECLARE @tvTrackProjectId INT = 835;

-- Scoped to ONLY the two backfilled brands (BrandID filter) so this cannot
-- duplicate the 10,430 rows already correctly moved for the other 4 brands.
INSERT INTO dbo.Exposure ([BrandID],[TP_ID],[SubTP_ID],[StartTime],[EndTime],[ScreenLocation],[ScreenSize],[Duration],[ProjectID],[ProgrammeID],[ProgDetID],[AvgHits],[TotalHits])
SELECT
	E.[BrandID],E.[TP_ID],E.[SubTP_ID],E.[StartTime],E.[EndTime],E.[ScreenLocation],E.[ScreenSize],
	E.[Duration],@tvTrackProjectId,PTV.[ProgID],E.[ProgDetID],E.[AvgHits],E.[TotalHits]
FROM [dbo].[CMGSQLNODE01\FSE.Matchroom.Exposure] E
INNER JOIN dbo.Programme PTV
	ON PTV.ProgID = E.ProgrammeID
   AND PTV.ProjectID = @tvTrackProjectId
WHERE PTV.PR_Name IN (SELECT REPLACE(SportsEvent,'/','.xlsx') COLLATE SQL_Latin1_General_CP1_CI_AS FROM #SportEvents)
AND E.BrandID IN (22407, 22765);   -- Winmau, Smart Water only

SELECT @@ROWCOUNT AS RowsInsertedIntoTvTrackExposure_ShouldBeWinmauSmartWaterOnly

-- Final check: confirm both brands now show up
SELECT
    P.PR_Name,
    B.BrandName,
    COUNT(*) AS ExposureRows,
    SUM(E.Duration) AS TotalDurationSeconds
FROM dbo.Exposure E
INNER JOIN dbo.Programme P ON E.ProgrammeID = P.ProgID
INNER JOIN [CMGSQLNODE01\FSE.PhotoTextTrack.Brands] B ON B.BrandID = E.BrandID
WHERE E.ProjectID = 835
AND P.PR_Name IN ('20260605_PDC_NORD_Day1Evening.xlsx','20260606_PDC_NORD_Day2Evening.xlsx')
GROUP BY P.PR_Name, B.BrandName
ORDER BY P.PR_Name, TotalDurationSeconds DESC;
