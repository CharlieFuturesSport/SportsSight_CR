-- OCR Cleaning

-- Stage 1: Find list of events and make temp table

SELECT
     '(''' + SportsEvent + '''),'
FROM [dbo].[CMGSQLNODE01\FSE.ThemisDevelopment.ComputerVisionProcessingJobsHistory]
WHERE Sport = 'darts'
AND CREATED >= GETUTCDATE() - 60
and SportsEvent like '%wcod%'
ORDER BY created desc

-- temp table

drop table if exists #SportEvents
CREATE TABLE  #SportEvents (
    ID INT IDENTITY(1,1),
    SportsEvent VARCHAR(255)
)

INSERT INTO #SportEvents VALUES
('20260611_PDC_WCOD_Day1Evening/'),
('20260614_PDC_WCOD_Day4Afternoon/'),
('20260614_PDC_WCOD_Day4Evening/'),
('20260612_PDC_WCOD_Day2Afternoon/'),
('20260613_PDC_WCOD_Day3Evening/'),
('20260612_PDC_WCOD_Day2Afternoon/'),
('20260614_PDC_WCOD_Day4Evening/')

-- Stage 2: Check OCR Cleaning Rules Table

select * from Toolkit_OCR_cleaning_rules where AccessFlag = 'WCOD'
and Row_addition_source = 'human'

-- INSERT INTO STATEMENTS HERE

--INSERT INTO Toolkit_OCR_Cleaning_Rules VALUES ('Human',1,'Chapel Down','','ecb_2026','Chapel Down',11,0,1,0.6675,'')

-- Stage 3: Cleaning

-- 3.1 Insert on own exact matches - Human

DECLARE @specificAccessFlag VARCHAR(100)
SET @specificAccessFlag = 'ecb_2026'

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

-- 3.2 Insert on own exact matches - AUTOMATED

DECLARE @specificAccessFlag VARCHAR(100)
SET @specificAccessFlag = 'ecb_2026'

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
SET @specificAccessFlag = 'ecb_2026'

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
                ) CompBrands
) All_Leven
WHERE PercentDistance >= Min_Levenshtein_Value
ORDER BY Reported_brand, PercentDistance DESC

-- 3.3.1 Insert any new cleaning terms here

-- INSERT INTO Toolkit_OCR_Cleaning_Rules VALUES ('Automated',1,'Barclays WSL','Barclays','WSL','BARCLAYS G',10,1,0,1,'')

-- 3.3.2 Rerun AUTOMATED search matches to add newly inserted cleaning terms

DECLARE @specificAccessFlag VARCHAR(100)
SET @specificAccessFlag = 'ecb_2026'

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
WHERE SportsEvent IN
      (
          SELECT SportsEvent FROM #SportEvents
      )


-- 3.4 Insert substring matches

DECLARE @specificAccessFlag VARCHAR(100)
SET @specificAccessFlag = 'ecb_2026'

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
    WHERE SportsEvent IN
      (
          SELECT SportsEvent FROM #SportEvents
      )