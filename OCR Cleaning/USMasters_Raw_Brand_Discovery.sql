-- Raw brand discovery for US Masters - no cleaning rules exist yet for AccessFlag
-- 'USMasters', so this pulls straight from the raw OCR table, grouped and sorted by
-- frequency, to give a starting list of candidate brand text to build Stage 2B from.

DROP TABLE IF EXISTS #SportEvents;
CREATE TABLE #SportEvents
(
    ID INT IDENTITY(1,1),
    SportsEvent VARCHAR(255)
);

INSERT INTO #SportEvents (SportsEvent)
VALUES
('20260626_PDC_USM_Day1Evening/'),
('20260627_PDC_USM_Day2Evening/');

-- Sanity check: confirm raw data exists under these exact event names first.
SELECT RAW.SportsEvent, COUNT(*) AS Cnt
FROM Toolkit_ComputerVisionOcrResults RAW
JOIN #SportEvents E
    ON RAW.SportsEvent = E.SportsEvent
GROUP BY RAW.SportsEvent
ORDER BY RAW.SportsEvent;

-- If the sanity check above returns 0 rows, use this instead to find the actual naming.
SELECT DISTINCT SportsEvent
FROM Toolkit_ComputerVisionOcrResults
WHERE SportsEvent LIKE '%USM%' OR SportsEvent LIKE '%USMasters%'
ORDER BY SportsEvent;

-- Main list: distinct raw OCR text, sorted by how often it was detected (most first).
-- Scan top-down - real sponsor text tends to cluster at the top (highest counts),
-- noise/garbled fragments trail off at the bottom.
SELECT
    RAW.TEXT AS RawText,
    COUNT(*) AS DetectionCount
FROM Toolkit_ComputerVisionOcrResults RAW
JOIN #SportEvents E
    ON RAW.SportsEvent = E.SportsEvent
GROUP BY RAW.TEXT
ORDER BY DetectionCount DESC, RawText;
