# Pact 6 Reporting Handoff

Worker: 6

Scope: aggregation, ICER, and reporting layer.

## Delivered

- Added `R/reporting.R` with:
  - `summarise_costs()` for deterministic cost totals by common reporting
    groups.
  - `compare_costs()` for `intervention - BAU` incremental cost summaries.
  - `calculate_icers()` for ICER calculation only when incremental costs and
    incremental HALYs are already present.
- Extended `summarise_pmslt_results()` so lifetable-style outputs that already
  carry cost columns include those costs in deterministic summaries.
- Extended comparison validation so cost columns must be present in both BAU
  and intervention outputs before cost differences are calculated.
- Preserved exact integer `age` as the internal state and used `age_band` only
  as a reporting grouping through `pmslt_spec()` age definitions.
- Updated workflow guidance and README examples for deterministic reporting,
  cost deltas, and ICER calculation.

## Reporting Conventions

- Incremental summaries use `intervention - BAU`.
- Cost columns are detected as `cost`, `costs`, `total_cost`, or columns ending
  in `_cost` or `_costs`.
- ICER inputs must include one incremental cost column and one incremental HALY
  column in the same data frame.
- ICERs are numeric only when incremental HALYs are positive.
- Zero and negative incremental HALYs are labelled with `icer_status` and have
  `NA` ICER values.

## Boundaries Kept

- No probabilistic intervals.
- No policy thresholds or decision rules.
- No discounting or age weighting.
- No changes to lifetable, disease, intervention, or cost engine calculations.

## Test Coverage Added

- `tests/testthat/test-reporting.R` covers:
  - overall and stratified cost summaries,
  - reporting-only age bands,
  - generic PMSLT summaries carrying cost columns,
  - cost comparisons using `intervention - BAU`,
  - incompatible BAU/intervention structures,
  - ICER prerequisite errors,
  - positive, zero, and negative incremental HALY handling.

## Handoff Notes

- Later PSA builders can call the deterministic summary helpers per draw and
  bind draw identifiers around the returned plain data frames.
- Later cost-engine work should emit exact-age rows keyed by `time_step`, `age`,
  `sex`, and `stratum` so these reporting functions can consume the outputs
  without adapter code.
