-- OCR Cleaning

-- Stage 1: Find list of events and make temp table

SELECT
     '(''' + SportsEvent + '''),'
FROM [dbo].[CMGSQLNODE01\FSE.ThemisDevelopment.ComputerVisionProcessingJobsHistory]
WHERE Sport = 'multisport'
AND CREATED >= GETUTCDATE() - 1
-- and SportsEvent like '%BWSL_ASTvLIV_GW3%'
ORDER BY created desc

-- temp table

    drop table if exists #SportEvents
    CREATE TABLE  #SportEvents (
        ID INT IDENTITY(1,1),
        SportsEvent VARCHAR(255)
    )
    INSERT INTO #SportEvents VALUES
   ('20260705_Multisport_EuropeanOpenPoolChamps26_DayAll/')

SELECT
    SportsEvent, COUNT(ID) as Count
FROM Toolkit_Cleaned_OCR_Results
WHERE SportsEvent IN ( SELECT SportsEvent FROM #SportEvents)
AND AccessFlag = 'wsl'
GROUP BY
    SportsEvent

-- INSERT INTO Toolkit_OCR_Cleaning_Rules VALUES ('Human',1,'Roobet','','EuropeanOpenPool26','Roobet',6,0,1,0.705,'')
-- INSERT INTO Toolkit_OCR_Cleaning_Rules VALUES ('Human',1,'World Nineball Tournament','pro','EuropeanOpenPool26','pro',3,0,1,0.7275,'')
-- INSERT INTO Toolkit_OCR_Cleaning_Rules VALUES ('Human',1,'World Nineball Tournament','wnt.tv','EuropeanOpenPool26','wnt.tv',6,0,1,0.705,'')
-- INSERT INTO Toolkit_OCR_Cleaning_Rules VALUES ('Human',1,'World Nineball Tournament','wnt.','EuropeanOpenPool26','wnt.',4,0,1,0.72,'')
-- INSERT INTO Toolkit_OCR_Cleaning_Rules VALUES ('Human',1,'Visit Sarajevo','Visit','EuropeanOpenPool26','Visit',5,0,1,0.7125,'')
-- INSERT INTO Toolkit_OCR_Cleaning_Rules VALUES ('Human',1,'Visit Sarajevo','Sarajevo','EuropeanOpenPool26','Sarajevo',8,0,1,0.69,'')
-- INSERT INTO Toolkit_OCR_Cleaning_Rules VALUES ('Human',1,'CPBA','','EuropeanOpenPool26','CPBA',4,0,1,0.72,'')
-- INSERT INTO Toolkit_OCR_Cleaning_Rules VALUES ('Human',1,'Diamond','','EuropeanOpenPool26','Diamond',7,0,1,0.6975,'')
-- INSERT INTO Toolkit_OCR_Cleaning_Rules VALUES ('Human',1,'Hotel Hills','','EuropeanOpenPool26','Hotel Hills',11,0,1,0.6675,'')
-- INSERT INTO Toolkit_OCR_Cleaning_Rules VALUES ('Human',1,'Cuetec','','EuropeanOpenPool26','Cuetec',6,0,1,0.705,'')



select distinct reported_brand
from Toolkit_OCR_Cleaning_Rules
where accessflag = 'wsl'

-- Stage 2: Check OCR Cleaning Rules Table

select * from Toolkit_OCR_cleaning_rules where AccessFlag = 'EuropeanOpenPool26'
and Row_addition_source = 'human'

-- INSERT INTO STATEMENTS HERE (IF NEW BRAND/CREATIVE)
-- https://interpublic.sharepoint.com/:x:/r/sites/AzureProjects/Shared%20Documents/AWS/2026/1.%20Exposure%20Data/OCR_Cleaning_Terms_2026.xlsx?d=wc6a2fe500fc745e6837f4711a66a9a02&csf=1&web=1&e=aZlc1U

-- INSERT INTO Toolkit_OCR_Cleaning_Rules VALUES ('Human',1,'Shot on iPhone','','WSL','Shot on iPhone',14,0,1,0.645,'')

-- Stage 3: Cleaning

-- 3.1 Insert on own exact matches - Human

DECLARE @specificAccessFlag VARCHAR(100)
SET @specificAccessFlag = 'EuropeanOpenPool26'

--INSERT EXACT MATCHES, HUMAN
INSERT INTO Toolkit_Cleaned_OCR_Results
SELECT --TOP 100
       NEWID() AS id,
       Sport,
       SportsEvent,
       [Filename],
       TEXT AS original_text,
       CASE
           WHEN reported_creative IS NULL
                OR reported_creative = '' THEN
               reported_brand
           ELSE
               reported_creative
       END AS cleaned_text,
       Reported_brand AS brand,
       NULL AS Asset,
       Reported_creative AS creative,
       AccessFlag,
       [BoxTopLeftX],
       [BoxTopLeftY],
       [BoxTopRightX],
       [BoxTopRightY],
       [BoxBottomRightX],
       [BoxBottomRightY],
       [BoxBottomLeftX],
       [BoxBottomLeftY],
       NULL AS [topBrand_Asset_Creative_perFilename],
       ImageWidth,
       ImageHeight,
       OcrLineId,
       Angle
FROM (
            SELECT
               RAW.*
            FROM Toolkit_ComputerVisionOcrResults RAW
               LEFT JOIN Toolkit_Cleaned_OCR_Results CLEAN
                  ON RAW.OcrLineId = CLEAN.OcrLineID
                  AND AccessFlag = @specificAccessFlag
            WHERE RAW.SportsEvent in ( SELECT SportsEvent FROM #SportEvents )
            AND CLEAN.ID IS NULL
    ) RAW
    INNER JOIN Toolkit_OCR_cleaning_rules RULES
        ON (RAW.TEXT = RULES.Primary_search_term)
           AND Row_manually_confirmed = 1
           AND Row_addition_source = 'Human'
           AND Reported_brand <> 'IGNORE'
           AND AccessFlag = @specificAccessFlag
           AND (other_on_screen_text_required = '')
           and Reported_brand not in (
            'Subway', 'EAFC'
           )

-- 3.2 Insert on own exact matches - AUTOMATED

DECLARE @specificAccessFlag VARCHAR(100)
SET @specificAccessFlag = 'wsl'

insert into Toolkit_Cleaned_OCR_Results
SELECT-- TOP 100
    NEWID() AS id,
    Sport,
    SportsEvent,
    [Filename],
    TEXT AS original_text,
    CASE
        WHEN reported_creative IS NULL
             OR reported_creative = '' THEN
            reported_brand
        ELSE
            reported_creative
    END AS cleaned_text,
    Reported_brand AS brand,
    NULL AS Asset,
    Reported_creative AS creative,
    AccessFlag,
    [BoxTopLeftX],
    [BoxTopLeftY],
    [BoxTopRightX],
    [BoxTopRightY],
    [BoxBottomRightX],
    [BoxBottomRightY],
    [BoxBottomLeftX],
    [BoxBottomLeftY],
    NULL AS [topBrand_Asset_Creative_perFilename],
    ImageWidth,
    ImageHeight,
    OcrLineId,
    Angle
FROM (
            SELECT
               RAW.*
            FROM Toolkit_ComputerVisionOcrResults RAW
               LEFT JOIN Toolkit_Cleaned_OCR_Results CLEAN
                  ON RAW.OcrLineId = CLEAN.OcrLineID
                  AND AccessFlag = @specificAccessFlag
            WHERE RAW.SportsEvent in ( SELECT SportsEvent FROM #SportEvents )
            AND CLEAN.ID IS NULL
         ) RAW
    INNER JOIN Toolkit_OCR_cleaning_rules RULES
        ON (RAW.TEXT = RULES.Primary_search_term)
           AND Row_manually_confirmed = 1
           AND Row_addition_source = 'Automated' --'Human'
           AND exact_match_required = 1
           AND substring_search_allowed = 0
           AND Reported_brand <> 'IGNORE'
           AND AccessFlag = @specificAccessFlag
           AND (other_on_screen_text_required = '')
           and Reported_brand not in (
            'Subway', 'EAFC'
           )
WHERE SportsEvent IN
      (
          SELECT SportsEvent FROM #SportEvents
      )

-- 3.3 Identify new terms

-- Copy the below lines to https://interpublic.sharepoint.com/:x:/r/sites/AzureProjects/Shared%20Documents/AWS/2026/1.%20Exposure%20Data/OCR_Cleaning_Terms_2026.xlsx?d=wc6a2fe500fc745e6837f4711a66a9a02&csf=1&web=1&e=aZlc1U
-- Review the results, accpeting or rejecting lines.
-- Only insert those lines that pass.

/* IDENTIFY SEARCH TERMS */
DECLARE @specificAccessFlag VARCHAR(100)
SET @specificAccessFlag = 'EuropeanOpenPool26'

SELECT 
    '' as ID,
    'Automated' as Row_addition_source,
    'NEEDS MANUALLY CHECKING TO A 1-ACCEPTED OR 0-REJECTED' AS Row_Manually_Confirmed,
    Reported_brand,
    Reported_creative,
    AccessFlag,
    Text as Primary_Search_Term,
    LEN(Text) as Len,
    1 as exact_match_required,
    0 AS substring_search_allowed,
    1 as min_levenshtein_value
FROM
(
    SELECT ([dbo].Toolkit_FUNC_LevenshteinDistanceAsPercentage(TEXT, Primary_search_term)) / 100.0 AS PercentDistance,
           *
    FROM 
	(
		SELECT
			OCR.Text,
			OCR.ocrCount--,
			--CurrentOCR.*
		FROM
		(
			SELECT TEXT,
				   COUNT(OCR.OcrLineId) AS ocrCount
			FROM Toolkit_ComputerVisionOcrResults OCR
				LEFT JOIN 
				(
					SELECT OcrLineID 
					FROM Toolkit_Cleaned_OCR_Results 
					WHERE SportsEvent IN (SELECT SportsEvent FROM #SportEvents WHERE AccessFlag = @specificAccessFlag)
					AND AccessFlag = @specificAccessFlag
				) Inserted
				ON OCR.OcrLineId = Inserted.OcrLineId
			WHERE SportsEvent IN
				  (
					  SELECT SportsEvent FROM #SportEvents
				  )
			AND Inserted.OcrLineID IS NULL
			GROUP BY TEXT
		) OCR
		LEFT JOIN
		(
			SELECT DISTINCT ID, Primary_Search_Term FROM [dbo].[Toolkit_OCR_cleaning_rules] WHERE AccessFlag = @specificAccessFlag
		) CurrentOCR
			ON OCR.Text = CurrentOCR.Primary_Search_Term
				AND CurrentOCR.ID IS NULL
	) DistinctOCR,
    (
        SELECT [Primary_search_term],
               [Min_Levenshtein_Value],
               [Reported_brand],
               [Reported_creative],
               accessFlag
        FROM [dbo].[Toolkit_OCR_cleaning_rules] rules
        WHERE [Min_Levenshtein_Value] < 1
              AND reported_brand <> 'IGNORE'
              AND [exact_match_required] <> 1
              AND AccessFlag = @specificAccessFlag
              AND Row_addition_source = 'Human'
              and Reported_brand not in (
            'Subway', 'EAFC'
           )    ) CompBrands
) All_Leven
WHERE PercentDistance >= Min_Levenshtein_Value
ORDER BY Reported_brand, PercentDistance DESC

-- 3.3.1 Insert any new cleaning terms here

-- INSERT INTO Toolkit_OCR_Cleaning_Rules VALUES ('Automated',1,'Barclays WSL','Barclays','WSL','BARCLAYS G',10,1,0,1,'')

-- 3.3.2 Rerun AUTOMATED search matches to add newly inserted cleaning terms

DECLARE @specificAccessFlag VARCHAR(100)
SET @specificAccessFlag = 'EuropeanOpenPool26'

insert into Toolkit_Cleaned_OCR_Results
SELECT-- TOP 100
    NEWID() AS id,
    Sport,
    SportsEvent,
    [Filename],
    TEXT AS original_text,
    CASE
        WHEN reported_creative IS NULL
             OR reported_creative = '' THEN
            reported_brand
        ELSE
            reported_creative
    END AS cleaned_text,
    Reported_brand AS brand,
    NULL AS Asset,
    Reported_creative AS creative,
    AccessFlag,
    [BoxTopLeftX],
    [BoxTopLeftY],
    [BoxTopRightX],
    [BoxTopRightY],
    [BoxBottomRightX],
    [BoxBottomRightY],
    [BoxBottomLeftX],
    [BoxBottomLeftY],
    NULL AS [topBrand_Asset_Creative_perFilename],
    ImageWidth,
    ImageHeight,
    OcrLineId,
    Angle
FROM (
            SELECT
               RAW.*
            FROM Toolkit_ComputerVisionOcrResults RAW
               LEFT JOIN Toolkit_Cleaned_OCR_Results CLEAN
                  ON RAW.OcrLineId = CLEAN.OcrLineID
                  AND AccessFlag = @specificAccessFlag
            WHERE RAW.SportsEvent in ( SELECT SportsEvent FROM #SportEvents )
            AND CLEAN.ID IS NULL
         ) RAW
    INNER JOIN Toolkit_OCR_cleaning_rules RULES
        ON (RAW.TEXT = RULES.Primary_search_term)
           AND Row_manually_confirmed = 1
           AND Row_addition_source = 'Automated' --'Human'
           AND exact_match_required = 1
           AND substring_search_allowed = 0
           AND Reported_brand <> 'IGNORE'
           AND AccessFlag = @specificAccessFlag
           AND (other_on_screen_text_required = '')
           and Reported_brand not in ( 
            'Subway', 'EAFC'
           )
WHERE SportsEvent IN
      (
          SELECT SportsEvent FROM #SportEvents
      )


-- 3.4 Insert substring matches

DECLARE @specificAccessFlag VARCHAR(100)
SET @specificAccessFlag = 'EuropeanOpenPool26'

--MANUAL AS PART OF A STRING
INSERT INTO Toolkit_Cleaned_OCR_Results
    SELECT --TOP 100
        NEWID() as id,
        Sport, SportsEvent, [Filename],
        Text as original_text,
        CASE
           WHEN reported_creative IS NULL
            OR reported_creative = '' THEN
               reported_brand
           ELSE
               reported_creative
       END AS cleaned_text,
        Reported_brand as brand,
        NULL AS Asset,
        Reported_creative as creative,
        AccessFlag,
       (RAW.[BoxTopLeftX]
        + ((RAW.[BoxTopRightX] - RAW.[BoxTopLeftX])
           * ((CHARINDEX(RULES.[Primary_search_term], RAW.TEXT) - 1) / cast(LEN(RAW.TEXT) AS FLOAT))
          )
       ) AS [BoxTopLeftX],
       RAW.[BoxTopLeftY],
       RAW.[BoxTopRightX]
       - ((RAW.[BoxTopRightX] - RAW.[BoxTopLeftX])
          * (1
             - (((LEN(RULES.[Primary_search_term]) + (CHARINDEX(RULES.[Primary_search_term], RAW.TEXT) - 1))
                 / cast(LEN(RAW.TEXT) AS FLOAT)
                )
               )
            )
         ) AS [BoxTopRightX],
       RAW.[BoxTopRightY],
       RAW.[BoxBottomRightX]
       - ((RAW.[BoxBottomRightX] - RAW.[BoxBottomLeftX])
          * (1
             - (((LEN(RULES.[Primary_search_term]) + (CHARINDEX(RULES.[Primary_search_term], RAW.TEXT) - 1))
                 / cast(LEN(RAW.TEXT) AS FLOAT)
                )
               )
            )
         ) AS [BoxBottomRightX],
       RAW.[BoxBottomRightY],
       (RAW.[BoxBottomLeftX]
        + ((RAW.[BoxBottomRightX] - RAW.[BoxBottomLeftX])
           * ((CHARINDEX(RULES.[Primary_search_term], RAW.TEXT) - 1) / cast(LEN(RAW.TEXT) AS FLOAT))
          )
       ) AS [BoxBottomLeftX],
       RAW.[BoxBottomLeftY],
        NULL as [topBrand_Asset_Creative_perFilename],
        ImageWidth,
        ImageHeight,
        OcrLineId,
        Angle
    FROM (
            SELECT
               RAW.*
            FROM Toolkit_ComputerVisionOcrResults RAW
               LEFT JOIN Toolkit_Cleaned_OCR_Results CLEAN
                  ON RAW.OcrLineId = CLEAN.OcrLineID
                  AND AccessFlag = @specificAccessFlag
            WHERE RAW.SportsEvent in ( SELECT SportsEvent FROM #SportEvents )
            AND CLEAN.ID IS NULL
         ) RAW
        INNER JOIN Toolkit_OCR_cleaning_rules RULES
        ON (RAW.Text LIKE '%' + RULES.Primary_search_term + '%')
            AND substring_search_allowed = 1
            AND Row_addition_source = 'Human'
            AND Row_manually_confirmed = 1
            AND Reported_brand <> 'IGNORE'
            AND AccessFlag = @specificAccessFlag
            AND (other_on_screen_text_required = '')
                       and Reported_brand not in (
            'Subway', 'EAFC'
           )
    WHERE SportsEvent IN
      (
          SELECT SportsEvent FROM #SportEvents
      )