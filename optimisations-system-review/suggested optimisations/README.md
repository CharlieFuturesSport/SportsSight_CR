# Suggested Optimisations (Cricket AMCR -> TvTrack)

These scripts are drop-in replacements for the ECB move flow in:

- `AMCR to TV Track/Cricket/SS ECB Move from AMCR to TvTrack.sql`

They target the two procedural hotspots identified:

1. Row-by-row overwrite delete loop -> set-based delete
2. FirstInterval cursor -> deduplicated candidate list before execution

## Files

- `01_set_based_overwrite_delete.sql`
  - Replaces the `#deleteprogrammes` + `WHILE` delete loop.

- `02_firstinterval_deduped_queue.sql`
  - Replaces the `#proglist` cursor build block.

## Notes

- Keep existing variable names (`@tvTrackProjectId`, `@TVTrackProjectID`) consistent with your active script section.
- The `FirstInterval` execution still runs per programme because the stored procedure takes one `ProgID` at a time. The optimisation here reduces avoidable calls by tightening the input set.
