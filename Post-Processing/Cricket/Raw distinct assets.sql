-- 1) Raw distinct asset labels in scope
SELECT DISTINCT A.Asset
FROM SportsSight_Raw_Assets A
WHERE A.SportsEvent IN (
    '12678_040626_Men_1stTest_Eng_v_Nzl_Day_1/',
    '12678_050626_Men_1stTest_Eng_v_Nzl_Day_2/',
    '12678_060626_Men_1stTest_Eng_v_Nzl_Day_3/',
    '12678_070626_Men_1stTest_Eng_v_Nzl_Day_4/'
)
ORDER BY 1;



SELECT COUNT_BIG(*) AS TotalRows
FROM Toolkit_AzureModels_CombinedResults
WHERE Iteration = 'SS1'
  AND Event IN (
    '12678_040626_Men_1stTest_Eng_v_Nzl_Day_1',
    '12678_050626_Men_1stTest_Eng_v_Nzl_Day_2',
    '12678_060626_Men_1stTest_Eng_v_Nzl_Day_3',
    '12678_070626_Men_1stTest_Eng_v_Nzl_Day_4'
  );