-- ECB upload validation: Men 2nd Test (SS1)

DECLARE @Scope TABLE (
    EventName VARCHAR(200) NOT NULL
);

INSERT INTO @Scope (EventName)
VALUES
('12679_170626_Men_2ndTest_Eng_v_Nzl_Day_1'),
('12679_180626_Men_2ndTest_Eng_v_Nzl_Day_2'),
('12679_190626_Men_2ndTest_Eng_v_Nzl_Day_3'),
('12679_200626_Men_2ndTest_Eng_v_Nzl_Day_4'),
('12679_210626_Men_2ndTest_Eng_v_Nzl_Day_5');

-- 1) Row count per event
SELECT
    CR.Event,
    COUNT(*) AS [RowsPerEvent]
FROM Toolkit_AzureModels_CombinedResults CR
INNER JOIN @Scope S
    ON S.EventName = CR.Event
WHERE CR.Iteration = 'SS1'
GROUP BY CR.Event
ORDER BY CR.Event;

-- 2) Total rows across all 5 events
SELECT
    COUNT(*) AS [TotalRows]
FROM Toolkit_AzureModels_CombinedResults CR
INNER JOIN @Scope S
    ON S.EventName = CR.Event
WHERE CR.Iteration = 'SS1';

-- 3) ModelType split
SELECT
    CR.ModelType,
    COUNT(*) AS [RowsByModelType]
FROM Toolkit_AzureModels_CombinedResults CR
INNER JOIN @Scope S
    ON S.EventName = CR.Event
WHERE CR.Iteration = 'SS1'
GROUP BY CR.ModelType
ORDER BY [RowsByModelType] DESC;

-- 4) Duplicate check: Event + Filename + Brand + Asset + ModelType
SELECT
    CR.Event,
    CR.Filename,
    CR.Brand,
    CR.Asset,
    CR.ModelType,
    COUNT(*) AS [DupCount]
FROM Toolkit_AzureModels_CombinedResults CR
INNER JOIN @Scope S
    ON S.EventName = CR.Event
WHERE CR.Iteration = 'SS1'
GROUP BY
    CR.Event,
    CR.Filename,
    CR.Brand,
    CR.Asset,
    CR.ModelType
HAVING COUNT(*) > 1
ORDER BY [DupCount] DESC, CR.Event;