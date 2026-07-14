-- Check whether every brand on Kishan's Blast asset list has cleaned OCR detections
-- across all 11 Blast matches. LEFT JOIN so zero-detection brands still show as 0.

SELECT
    B.Brand,
    COALESCE(COUNT(C.OcrLineId), 0) AS CleanedRowCount
FROM
(
    VALUES
    ('Aironix'), ('Castore'), ('Chapel Down'), ('Connect it'), ('Dafabet'),
    ('Hendy'), ('Kukri'), ('Pangea'), ('ScS'), ('Trade Nation'), ('Hilton'),
    ('Synertec'), ('Thatchers'), ('WPA Health'), ('Adidas'), ('Bit58'),
    ('Dragonbet'), ('Haier'), ('IG'), ('KP'), ('Masuri'),
    ('Mitchell Associates'), ('Toyota'), ('Ark Build'), ('Barclays'),
    ('CGI'), ('Chaucer'), ('IBC'), ('Kia'), ('London Pride'), ('Peroni'),
    ('Woodland Group'), ('Price Forbes'), ('Surridge Sport'), ('WBS'),
    ('Uptonsteel'), ('Manscaped'), ('Absolube'), ('Chevin'), ('Samurai'),
    ('Stadiacare'), ('Attivo'), ('Alt Group'), ('Stadium Support Services'),
    ('ebc'), ('University of Birmingham'), ('Macron'), ('Nike'),
    ('Remitly'), ('Cinch'), ('CMG'), ('Whole Earth'), ('Vitality'),
    ('Vitality Blast'), ('more')
) B (Brand)
LEFT JOIN Toolkit_Cleaned_OCR_Results C
    ON C.Brand = B.Brand
   AND C.AccessFlag = 'ecb_2026'
   AND C.SportsEvent IN (
        '12729_220526_Mens_Blast_Group_Som_v_Ham/',
        '12730_220526_Womens_Blast_Group_Som_v_Ham/',
        '12731_230526_Mens_Blast_Group_Gla_v_Glo/',
        '12732_240526_Mens_Blast_Group_Mid_v_Sur/',
        '12733_260526_Mens_Blast_Group_Ham_v_Ess/',
        '12734_260526_Womens_Blast_Group_Ham_v_Ess/',
        '12735_270526_Mens_Blast_Group_Lei_v_Der/',
        '12736_290526_Mens_Blast_Group_Wor_v_War/',
        '12737_300526_Mens_Blast_Group_Sus_v_Mid/',
        '12738_310526_Mens_Blast_Group_War_v_Nor/',
        '12739_030626_Mens_Blast_Group_Sur_v_Mid/'
    )
GROUP BY B.Brand
ORDER BY CleanedRowCount ASC;
