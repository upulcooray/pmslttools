# Pact 4 Costs Handoff

Worker 4 added the first deterministic cost module for `12_costs.csv`.

## Implemented

- `validate_cost_inputs()` validates `12_costs.csv` data frames or paths using
  the central schema metadata for `disease_cost`, `background_cost`,
  `currency`, `price_year`, and `source`.
- `currency` now uses a central `currency_code` validation type requiring
  uppercase three-letter codes such as `AUD`.
- Cost validation adds cross-field checks for a single currency, a single price
  year, and consistent repeated `background_cost` values within age, sex, and
  stratum groups.
- `attach_pmslt_costs()` attaches annual background costs to exact-age
  lifetable rows and disease-management costs to disease-delta rows when
  `integrate_disease_deltas()` has already been run.
- `summarise_pmslt_costs()` reports deterministic totals overall, by
  `time_step`, `sex`, `stratum`, `age`, `age_band`, and by `disease` when
  disease cost details are available.
- `compare_pmslt_costs()` reports intervention-minus-BAU cost differences.

## Boundaries Kept

- No discounting.
- No ICER thresholds.
- No PSA.
- No one-off intervention costs were added or mixed into annual
  disease-management costs.

## Notes For Next Pact

- Disease costs are annual costs per prevalent disease case:
  `person_years * disease_prevalence * disease_cost`.
- Background costs are annual costs per person and are counted once per
  lifetable row, even though the raw template has one row per disease.
- Cost comparison is a reporting helper. It assumes BAU and intervention
  lifetable outputs have already been produced by the deterministic modelling
  steps.
