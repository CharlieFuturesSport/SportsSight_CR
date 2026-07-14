-- Human-added OCR cleaning rules only, for ecb_2026 (Blast), full detail
SELECT
    Row_addition_source,
    Row_manually_confirmed,
    Reported_brand,
    Reported_creative,
    Primary_search_term,
    exact_match_required,
    substring_search_allowed,
    Min_Levenshtein_Value
FROM Toolkit_OCR_Cleaning_Rules
WHERE AccessFlag = 'ecb_2026'
  AND Row_addition_source = 'Human'
ORDER BY Reported_brand, Primary_search_term;
