# Pact 5 Equity And Stratum Rate-Ratio Handoff

Date: 2026-05-30

## Scope Completed

- Reworked `11_stratum_rate_ratios.csv` into a long-format contract with one
  row per `age_start`, `sex`, `stratum`, and `parameter`.
- Defined supported disaggregation parameters:
  - `acmr`: `mortality_rate` / `acmr_BAU`
  - `morbidity`: `morbidity_rate` / `pYLD_BAU`
  - `incidence`: `incidence_BAU` / `incidence_rate`
  - `remission`: `remission_rate`
  - `excess_mortality`: `excess_mortality_BAU` / `excess_mortality_rate`
  - `case_fatality`: `case_fatality_BAU` / `case_fatality_rate`
  - `mortality`: `disease_mortality_rate`
- Added `disaggregate_stratum_rates()` and
  `stratum_rate_ratio_definitions()` in `R/equity.R`.
- Added raw validation for rate-ratio completeness across age, sex, stratum,
  and parameter when a `pmslt_spec` is supplied.
- Wired optional `stratum_rate_ratios` arguments into:
  - `initialize_pmslt_lifetable()`
  - `run_pmslt_lifetable_bau()`
  - `integrate_disease_deltas()`
- Added audit columns for disaggregated rates:
  - `<rate>_original_aggregate`
  - `<rate>_rate_ratio`
  - `<rate>_rate_ratio_parameter`
  - `<rate>_reference_stratum`

## Boundary Notes

- Strata are checked against `pmslt_spec(strata = ...)` when a spec is supplied.
- The module only prepares BAU all-cause or disease-rate inputs before
  lifetable/disease-delta execution.
- No intervention effect estimation, distributional cost-effectiveness metrics,
  ICERs, discounting, or PSA logic were added in this pact.

## Validation

Commands run:

```sh
Rscript -e 'devtools::test(filter = "equity")'
Rscript -e 'devtools::test(filter = "raw-validation")'
Rscript -e 'devtools::test(filter = "main-lifetable")'
Rscript -e 'devtools::document()'
```

Results:

- `equity`: 19 passed, 0 failed.
- `raw-validation`: 105 passed, 0 failed.
- `main-lifetable`: 161 passed, 0 failed.
- `devtools::document()` completed and regenerated roxygen-managed metadata,
  including `disaggregate_stratum_rates.Rd`,
  `stratum_rate_ratio_definitions.Rd`, and updated lifetable Rd files.
