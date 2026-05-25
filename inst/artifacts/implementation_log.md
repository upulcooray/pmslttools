# pmslttools Implementation Log

This log records stepwise package-building decisions so future work can resume
without re-reading the full conversation.

## 2026-05-17: Direct Disease Effect Helper Clarified

Reason:

- The internal helper `add_direct_effect_multipliers()` was unclear to the user.
- Direct intervention effects are important because some interventions act on
  disease incidence, case fatality, or morbidity directly rather than through a
  risk factor PIF.

Change:

- Renamed `add_direct_effect_multipliers()` to
  `apply_direct_disease_effects()`.
- Added a code comment explaining that coverage converts a treatment-group
  relative risk into a population-level multiplier:

```r
effective_multiplier <- 1 - coverage * (1 - rr)
```

Example:

- RR among covered people: `0.80`.
- Coverage: `0.50`.
- Population-level multiplier: `0.90`.

Effect:

- No public API change.
- `run_pmslt_interventions()` and `run_pmslt_disease_lifetable()` continue to
  behave the same way.

Related artifacts updated:

- `inst/artifacts/todo_plan.md`
- `inst/artifacts/package_architecture.md`

## 2026-05-17: Risk Prevalence Validation Added

Reason:

- PIFs are only meaningful when risk-category prevalence distributions sum to
  1. The package generated category templates but did not yet check category
  sums before calculating PIFs.

Change:

- Added exported `validate_risk_prevalence_inputs()`.
- The function checks both `prevalence_BAU` and
  `prevalence_intervention` within each intervention, age, sex, stratum,
  time step, and risk factor.
- `calculate_pif_from_inputs()` now calls this validator before joining
  relative risks.
- Added tests for valid mock inputs and invalid category sums.

Effect:

- Incorrectly filled `08_risk_factor_prevalence.csv` files fail early with a
  plain-language message that identifies the first affected intervention arm,
  risk factor, age, sex, stratum, and time step.

Related artifacts updated:

- `README.md`
- `inst/artifacts/todo_plan.md`
- `inst/artifacts/package_architecture.md`

## 2026-05-17: Central Raw Input Schemas Added

Reason:

- Template columns, guide descriptions, requirement levels, and future
  validation rules were split across template and guide code.
- Phase 2 needs a single schema source before adding comprehensive raw input
  validation.

Change:

- Added `R/schema.R` with one central schema entry per raw CSV template.
- Each schema entry records the file name, columns, requirement level,
  beginner-facing description, validation type, and allowed values where
  relevant.
- Updated `README_inputs_raw.md` generation and `00_column_dictionary.csv`
  generation to use the central schema metadata.
- Added tests that compare generated template columns with schema columns and
  check validation metadata in both the column dictionary and markdown guide.

Effect:

- Existing template filenames and ordinary data columns are unchanged.
- `00_column_dictionary.csv` now includes `validation_type` and
  `allowed_values`, which prepares the package for `validate_raw_inputs()`.

Validation:

- `devtools::test()` passed with 110 tests.
- `R CMD check pmslttools_0.0.0.9009.tar.gz --no-manual --no-build-vignettes`
  passed with status OK.

Related artifacts updated:

- `inst/artifacts/todo_plan.md`
- `inst/artifacts/implementation_log.md`

## 2026-05-18: Raw Input Validation Layer Added

Reason:

- The package could generate schema-driven raw templates, but users did not yet
  have one standard reusable validation step before DisMod processing.
- Raw validation needs to be non-destructive and beginner-friendly: it should
  accumulate issues and explain how to fix them instead of stopping at the
  first failed check.

Change:

- Added exported `validate_raw_inputs(input_dir, spec = NULL)`.
- Added internal issue-table helpers:
  `empty_validation_issues()`, `new_validation_issue()`,
  `append_validation_issue()`, and `append_validation_issues()`.
- Added S3 class `pmslt_validation_issues` and
  `print.pmslt_validation_issues()`.
- Added exported `summarise_raw_input_issues()` with S3 print method
  `print.summarised_raw_input_issues()` so beginners can see whether they can
  proceed, how many errors and warnings remain, which files need review, and
  the recommended next step.
- Added exported `check_raw_input_readiness(input_dir, spec = NULL)` with S3
  print method `print.raw_input_readiness_check()` to run raw validation and
  issue summarisation in one beginner-facing workflow step while preserving the
  original issue table.
- The validator checks:
  - missing expected raw CSV files;
  - unexpected duplicate CSV copies;
  - invalid `input_dir` paths returned as issue tables;
  - missing and duplicated columns;
  - unexpected extra columns reported as warnings;
  - blank required values;
  - numeric, integer, and calendar-year type problems;
  - schema-defined allowed values;
  - `pmslt_spec`-derived generated values such as sex, stratum, disease,
    intervention, risk factor, risk category, age bands, and time steps;
  - duplicate rows using identifying key columns defined in the raw schema;
  - non-negative rates and counts;
  - proportions bounded by 0 and 1;
  - positive relative risks and rate ratios;
  - `age_start <= age_end`;
  - simple `lower_95 <= mean_value <= upper_95` consistency.

Effect:

- Raw template validation now returns a stable, flat issue table with columns
  `file`, `row`, `column`, `severity`, `message`, and `suggested_fix`.
- The raw validation layer remains separate from DisMod validation and
  post-DisMod PMSLT disease input validation.

Validation:

- Added `tests/testthat/test-raw-validation.R`.
- `devtools::test()` passed with 138 tests.

Related artifacts updated:

- `NAMESPACE`
- `man/validate_raw_inputs.Rd`
- `inst/artifacts/todo_plan.md`
- `inst/artifacts/package_architecture.md`

## 2026-05-18: Canonical PMSLT Disease Epidemiology Schema Formalised

Reason:

- Downstream PMSLT disease modules need a stable post-DisMod disease input
  contract before additional engine modules are built.
- The package needed clearer separation between raw disease epidemiology
  templates, teaching/local DisMod-lite intermediates, and the PMSLT-ready
  disease epidemiology file.

Change:

- Added `pmslt_ready_input_schemas()` and `pmslt_disease_epi_schema()` in
  `R/schema.R`.
- Kept PMSLT-ready schema metadata separate from raw template schemas returned
  by `pmslt_input_schemas()`.
- Formalised `pmslt_disease_epi.csv` required columns:
  `age_start`, `age_end`, `age_label`, `sex`, `stratum`, `disease`,
  `time_step`, `incidence_BAU`, `prevalence_initial`, `remission_rate`,
  `excess_mortality_BAU`, `case_fatality_BAU`, and `disability_weight`.
- Documented optional trend/provenance columns currently written by
  `prepare_pmslt_disease_inputs()`:
  `prevalence_BAU_reference`, `incidence_apc`, `cfr_apc`,
  `prevalence_apc`, and `input_source`.
- Updated `prepare_pmslt_disease_inputs()` to order columns from the schema and
  validate before writing.
- Updated `validate_pmslt_disease_inputs()` to derive required columns from the
  schema and to reject non-numeric schema fields, negative rates, prevalence
  outside 0 to 1, invalid disability weights, and non-integer time steps.
- Updated roxygen text to clarify:
  - raw disease epidemiology belongs in `05_disease_epidemiology_raw.csv`;
  - raw template files are validated by `validate_raw_inputs()`;
  - DisMod-lite output files are teaching/local diagnostic intermediates;
  - downstream PMSLT disease modules consume `pmslt_disease_epi.csv`.

Effect:

- Existing public column names are preserved.
- `time_step` remains the canonical time column for PMSLT-ready disease inputs;
  no new `year` column was introduced.
- `mock_dismod_output()` and `prepare_pmslt_disease_inputs()` align with the
  canonical schema.

Validation:

- Added `tests/testthat/test-pmslt-disease-schema.R`.
- Local schema tests passed before full package validation.

Related artifacts updated:

- `R/schema.R`
- `R/mock-dismod.R`
- `R/pmslt-workflow.R`
- `inst/artifacts/package_architecture.md`

## 2026-05-20: Canonical Disease Input Moved to Single-Year Age

Reason:

- Future PMSLT lifetable modules should consume one stable disease input
  contract before main engine expansion resumes.
- Raw epidemiological evidence may be age-banded, but the internal
  PMSLT-ready disease file should not use age bands as simulation state.

Change:

- Updated `pmslt_disease_epi_schema()` so the required canonical age field is
  exact integer `age`, replacing `age_start`, `age_end`, and `age_label` in
  `pmslt_disease_epi.csv`.
- Kept raw template schemas age-banded where appropriate, including
  `05_disease_epidemiology_raw.csv` and `06_dismod_input_skeleton.csv`.
- Updated `prepare_pmslt_disease_inputs()` to write single-year rows from
  `mock_dismod_output_continuous.csv`; raw age-banded disability weights are
  expanded onto exact ages before merging.
- Updated `validate_pmslt_disease_inputs()` to reject missing or non-integer
  ages, reject age-band columns in PMSLT-ready inputs, check required columns,
  enforce non-negative rates, and keep prevalence/disability weights between
  0 and 1.
- Updated DisMod-lite diagnostic solving to expand age-banded observations to
  exact one-year rows while keeping it clearly documented as a teaching/local
  diagnostic helper.
- Kept `age_bands()` in the user-facing specification layer; age bands remain
  for input convenience and reporting/diagnostics, not canonical disease
  simulation state.

Validation:

- Added and updated tests covering single-year canonical schema, writer output
  uniqueness by exact age, validator acceptance/rejection paths, mock DisMod
  schema validity, DisMod-lite one-year expansion, and unchanged raw disease
  template age-band schemas.
- `devtools::test()` passed locally with 176 tests before roxygen regeneration.

Boundary:

- Main PMSLT lifetable expansion was not started in this slice.

Related artifacts updated:

- `R/schema.R`
- `R/mock-dismod.R`
- `R/dismod-lite.R`
- `R/pmslt-workflow.R`
- `tests/testthat/test-pmslt-disease-schema.R`
- `tests/testthat/test-dismod-lite.R`
- `tests/testthat/test-mock-dismod.R`
- `tests/testthat/test-pmslt-workflow.R`
- `tests/testthat/test-templates.R`
- `inst/artifacts/package_architecture.md`
- `inst/artifacts/todo_plan.md`
- `inst/artifacts/implementation_log.md`

## 2026-05-20: Single-Year Disease Input Contract Audit

Reason:

- The single-year `pmslt_disease_epi.csv` contract needed a cleanup pass before
  any main all-cause lifetable work starts.

Audit result:

- Stale PMSLT-ready age-band assumptions were reviewed across `R/`, `tests/`,
  `man/`, `README.md`, and package artifacts.
- Remaining `age_start`, `age_end`, `age_label`, and age-band references are
  valid where they describe raw input templates, `pmslt_spec()` age bands,
  DisMod-lite diagnostics, plotting/reporting summaries, or explicit validator
  rejection of age-banded PMSLT-ready inputs.
- Public documentation now states that raw epidemiology inputs may be
  age-banded, DisMod-lite/mock DisMod disaggregate to single-year age,
  `pmslt_disease_epi.csv` is single-year, future PMSLT engine modules should
  use exact integer age internally, and output summaries may later aggregate
  ages for reporting.

Change:

- Reordered `validate_pmslt_disease_inputs()` so age-banded PMSLT-ready files
  receive the beginner-facing age-band error before the generic missing
  required-column check.
- Added tests that scan package examples/documentation for PMSLT-ready disease
  examples using age-band columns.
- Added a focused intervention workflow test showing exact-age disease inputs
  can be combined with age-banded intervention input rows where expansion is
  intentional.

Boundary:

- Main all-cause lifetable, disease costs, and PSA were not started.

## 2026-05-20: First Single-Year BAU All-Cause Lifetable Slice

Reason:

- The single-year disease input contract is stable enough to start the main
  PMSLT engine, but the first implementation should stay deterministic and
  all-cause only.

Change:

- Added exported `initialize_pmslt_lifetable()` in `R/main-lifetable.R`.
- The function accepts data frames or CSV paths for population, all-cause
  mortality, and optional all-cause morbidity.
- Required engine columns are exact integer `age`, `sex`, `stratum`,
  `population`, and `mortality_rate`; optional morbidity supplies
  `morbidity_rate`.
- Template-style aliases are accepted for beginner workflow continuity:
  `initial_population`, `acmr_BAU`, and `pYLD_BAU`.
- The function validates required columns, exact single-year ages,
  non-negative population, mortality rates between 0 and 1, non-negative
  morbidity rates, duplicate keys, and complete joins.
- Output is a plain data frame with class `pmslt_lifetable` and columns for
  `time_step`, `deaths`, `alive_end`, `person_years`, `morbidity_rate`, and
  `yld_rate`.

Boundary:

- This slice runs one BAU time step only.
- It does not age the population, integrate disease deltas, alter
  `run_pmslt_interventions()`, add costs, or run PSA.

Validation:

- Added tests covering valid one-step formulas, data frame and CSV path inputs,
  missing required columns, non-integer age rejection, negative population
  rejection, mortality bounds, incomplete mortality joins, optional morbidity
  joins, and incomplete morbidity joins.
- `devtools::document()` completed and generated
  `man/initialize_pmslt_lifetable.Rd` plus the NAMESPACE export.
- `devtools::test()` passed with 203 tests.
- `rcmdcheck` was not available in the active R session, so
  `rcmdcheck::rcmdcheck()` was not run.

## 2026-05-20: Multi-Cycle BAU All-Cause Lifetable Ageing Slice

Reason:

- The one-step BAU all-cause lifetable needed transparent yearly population
  ageing before disease deltas or intervention effects are integrated.

Change:

- Added exported `run_pmslt_lifetable_bau()` in `R/main-lifetable.R`.
- Kept `initialize_pmslt_lifetable()` as the one-step initializer.
- The BAU runner accepts data frames or CSV paths for population, mortality,
  and optional morbidity.
- `horizon` is resolved from the explicit argument, then `spec$horizon`, then
  default `1`.
- The function validates positive integer horizon, required columns,
  single-year integer age, consecutive ages within sex/stratum, non-negative
  population, mortality rates between 0 and 1, non-negative morbidity rates,
  duplicate keys, and complete rate joins for every simulated cycle.
- Static mortality and morbidity inputs are reused every cycle when no
  `time_step` column exists.
- Time-varying mortality and morbidity inputs are matched by `time_step` when
  that column exists.
- Survivors age forward by one year each cycle. The minimum starting age gets
  no new entrants. The maximum age is open-ended: survivors already at the
  maximum age stay there and survivors from the previous age also age into it.
- Added `yld = person_years * morbidity_rate` while preserving `yld_rate`.

Boundary:

- No disease-specific deltas, PIFs, direct intervention effects, costs, PSA,
  equity disaggregation, births, migration, entrants, or new cohorts were
  added.
- The canonical `pmslt_disease_epi.csv` schema was not changed.

Validation:

- Added tests covering `horizon = 1` equivalence with the initializer,
  multi-cycle ageing, open-ended maximum-age retention, static rate reuse,
  time-varying mortality matching, morbidity matching and `yld`, invalid
  horizon rejection, incomplete time-varying joins, no-new-entrant behaviour,
  and consecutive-age validation.
- `devtools::document()` completed and generated `run_pmslt_lifetable_bau.Rd`
  plus the NAMESPACE export.
- `devtools::test()` passed with 233 tests.
- `rcmdcheck` was not available in the active R session, so
  `rcmdcheck::rcmdcheck()` was not run.

## 2026-05-20: Disease Delta Attachment for Single-Year BAU Lifetable

Reason:

- The BAU all-cause lifetable can now initialize and age deterministically, so
  the next narrow step is to attach disease-attributable quantities without
  changing all-cause death flow or introducing intervention logic.

Change:

- Added exported `integrate_disease_deltas()` in `R/main-lifetable.R`.
- The helper accepts a `run_pmslt_lifetable_bau()` output plus a data frame or
  CSV path for canonical `pmslt_disease_epi.csv`.
- Disease inputs are validated with `validate_pmslt_disease_inputs()` and keep
  the exact integer `age` contract.
- Joins are validated by `time_step`, `age`, `sex`, and `stratum`; incomplete
  disease rows for lifetable rows are rejected with a clear error.
- The helper computes:
  `disease_cases = person_years * incidence_BAU`,
  `disease_deaths = person_years * prevalence_initial * case_fatality_BAU`,
  and `disease_yld = person_years * prevalence_initial * disability_weight`.
- Multiple diseases are aggregated into `total_disease_cases`,
  `total_disease_deaths`, and `total_disease_yld` beside each all-cause
  lifetable row.
- Disease-specific long output is preserved in the `disease_deltas` attribute.

Boundary:

- Disease deaths are not subtracted from all-cause deaths yet.
- No intervention effects, PIFs, direct effects, costs, PSA, or equity logic
  were added.
- The `pmslt_disease_epi.csv` schema was not changed.

Validation:

- Added tests for single-disease joins, deterministic cases/deaths/YLD
  formulas, multiple-disease aggregation, incomplete join rejection, and
  invalid disease-input rejection through the existing validator.
- `devtools::document()` completed and generated
  `man/integrate_disease_deltas.Rd` plus the NAMESPACE export.
- `devtools::test()` passed with 249 tests.
- `rcmdcheck` was not installed in the active R session, so
  `rcmdcheck::rcmdcheck()` was not run.

## 2026-05-20: Rename DisMod-lite Helper

Reason:

- The public teaching/local DisMod-lite helper needed to use the requested
  beginner-facing function name.

Change:

- Renamed exported `solve_dismod_lite()` to `dismod_slove()`.
- Updated package references in README, CODEX, architecture/todo artifacts,
  tests, NAMESPACE, and the Rd help file.
- The on-disk output folder and CSV names still use `dismod_lite` because they
  describe the diagnostic output format rather than the R function name.

Boundary:

- No DisMod-lite equations, disease schema, lifetable logic, intervention
  logic, costs, PSA, or equity logic were changed.

Validation:

- Validation commands for this rename are recorded below when run.

## 2026-05-20: Beginner Result Summary Helpers

Reason:

- Before intervention integration, users need a simple way to inspect BAU
  all-cause lifetable outputs and attached disease-delta outputs.

Change:

- Added exported `summarise_pmslt_results()` in `R/main-lifetable.R`.
- The helper accepts output from `run_pmslt_lifetable_bau()` and
  `integrate_disease_deltas()`.
- `by = "overall"` returns one ungrouped summary row.
- Summaries can group by exact `time_step`, `sex`, `stratum`, and `age`.
- When `by` includes `disease`, the helper uses
  `attr(results, "disease_deltas")` and returns disease-specific metrics.
- All-cause summaries include `population`, `deaths`, `person_years`, and
  `yld` when present.
- Integrated summaries include `total_disease_cases`,
  `total_disease_deaths`, and `total_disease_yld`.

Boundary:

- Exact single-year age is preserved; no age-band reporting was added.
- No intervention effects, costs, PSA, equity logic, lifetable formula changes,
  or schema changes were added.

Validation:

- Added tests for overall BAU summaries, grouping by `time_step`, `sex` and
  `stratum`, exact `age`, integrated disease total summaries,
  disease-specific summaries from `disease_deltas`, missing disease-attribute
  errors, and invalid grouping errors.
- `devtools::document()` completed and generated
  `man/summarise_pmslt_results.Rd` plus the NAMESPACE export.
- `devtools::test()` passed with 275 tests.
- `rcmdcheck` was not installed in the active R session, so
  `rcmdcheck::rcmdcheck()` was not run.

## 2026-05-22: Age-Band Result Summaries

Reason:

- The main lifetable engine now uses exact single-year ages, but beginner
  reporting often needs familiar age bands such as `40-42` or `43-45`.
- This should be an output aggregation layer only, not a change to the PMSLT
  engine or disease-delta integration.

Change:

- Extended `summarise_pmslt_results()` to accept `by = "age_band"` and the
  optional alias `group_by = "age_band"`.
- Age-band labels are assigned from `attr(results, "spec")$ages`, using the
  same `age_bands()`/`pmslt_spec()` age-band table used elsewhere in the
  package.
- All-cause summaries can aggregate `population`, `deaths`, `person_years`,
  `yld`, and integrated disease total columns by `age_band`.
- Disease-specific summaries can aggregate the `disease_deltas` attribute by
  `age_band` and by combined `disease` plus `age_band`.
- Added beginner-friendly errors when age-band summaries are requested but the
  result has no attached `pmslt_spec`, invalid `spec$ages`, or exact ages not
  covered by the configured age bands.

Boundary:

- Exact integer age remains the internal lifetable and disease input state.
- No lifetable formulas, disease-delta formulas, intervention effects, costs,
  PSA, HALYs, DALYs, or population ageing logic were changed.

Validation:

- Added tests for BAU age-band output columns, equality of summed age-band and
  exact-age totals, integrated disease age-band summaries,
  disease-plus-age-band summaries, and missing age-band information errors.
- `devtools::document()` completed and regenerated
  `man/summarise_pmslt_results.Rd`.
- `devtools::test()` passed with 293 tests.

Related artifacts updated:

- `README.md`
- `CODEX.md`
- `inst/artifacts/todo_plan.md`
- `inst/artifacts/implementation_log.md`

## 2026-05-22: Intervention Comparison Summaries

Reason:

- The main PMSLT workflow can now run BAU lifetables, attach disease totals,
  summarise outputs, and report by age band.
- The next safe step is to compare completed intervention outputs against BAU
  outputs without adding new intervention simulation mechanics.

Change:

- Added exported `compare_pmslt_results()` in `R/main-lifetable.R`.
- The helper validates that both inputs are PMSLT lifetable outputs and that
  they have matching `time_step`, `age`, `sex`, and `stratum` rows.
- The helper reuses `summarise_pmslt_results()` internally and returns
  `intervention - BAU` difference columns.
- Supported comparison groups are `overall`, `time_step`, `sex`, `stratum`,
  exact `age`, and reporting-only `age_band`.
- Difference outputs include `population_difference`, `deaths_difference`,
  `person_years_difference`, `yld_difference` when available, and integrated
  disease-total differences when both inputs include disease totals.
- Added beginner-friendly errors for non-PMSLT inputs, mismatched structures,
  unsupported grouping variables, and optional metrics present in only one
  result.

Boundary:

- Reporting layer only.
- No exact-age engine formulas, disease-delta formulas, intervention
  mechanics, costs, PSA, HALYs, DALYs, discounting, or disease-specific long
  contrast outputs were added.

Validation:

- Added tests for overall comparison, age-band comparison, grouped comparison,
  mismatched structures, disease-total comparison, and zero deltas for
  identical inputs.
- `devtools::document()` completed and generated
  `man/compare_pmslt_results.Rd` plus the NAMESPACE export.
- `devtools::test()` passed with 315 tests.

Related artifacts updated:

- `README.md`
- `CODEX.md`
- `inst/artifacts/package_architecture.md`
- `inst/artifacts/todo_plan.md`
- `inst/artifacts/implementation_log.md`

## 2026-05-25: DisMod-MR to PMSLT Disease Input Bridge

Reason:

- Real DisMod-MR output reading and validation existed, but validated long
  model outputs still needed a formal bridge into canonical
  `pmslt_disease_epi.csv` rows.

Change:

- Added exported `prepare_pmslt_disease_inputs_from_dismod_mr()` in
  `R/dismod-mr-to-pmslt.R`.
- The bridge accepts DisMod-MR outputs as a data frame, CSV path, or
  `dismod_mr_outputs` object and always applies Pack 2 validation before
  conversion.
- Mapped DisMod-MR parameters to PMSLT disease columns:
  incidence, prevalence, remission, excess mortality, and case fatality.
- Joined `disability_weight` from raw disease inputs using disease, sex,
  stratum, and age-band coverage; missing or ambiguous matches fail clearly.
- Preserved optional uncertainty bounds as provenance columns when present.
- Added safe `output_path` writing with overwrite protection and a compact
  print method for the returned classed data frame.

Boundary:

- No DisMod-MR execution, Python/R-INLA dependency, costs, HALYs, PSA,
  intervention logic, lifetable runner changes, DisMod-lite changes, or mock
  DisMod changes were added.

Validation:

- Added focused tests for data-frame, path, and `dismod_mr_outputs` inputs;
  exact parameter mapping; age-band disability-weight joins; missing and
  ambiguous disability-weight failures; missing required parameters; optional
  uncertainty provenance; validation toggling; output writing and overwrite
  behavior; and print output.

Related artifacts updated:

- `README.md`
- `CODEX.md`
- `inst/artifacts/package_architecture.md`
- `inst/artifacts/todo_plan.md`
- `inst/artifacts/implementation_log.md`

## 2026-05-25: Real DisMod-MR Output Reader and Validator

Reason:

- Pack 1 prepares files for an external DisMod-MR workflow, but the package
  also needs a formal way to read, validate, and audit the modelled outputs
  that analysts produce outside R.

Change:

- Added exported `read_dismod_mr_outputs()` in `R/dismod-mr-output.R`.
- Added exported `validate_dismod_mr_outputs()` and S3 class
  `dismod_mr_output_validation`.
- Added S3 class `dismod_mr_outputs` plus print methods for the output object
  and validation object.
- The reader accepts one long-format CSV and an optional target grid supplied
  as a data frame or path to `dismod_mr_target_grid.csv`.
- The validator checks required columns, allowed DisMod-MR modelled
  parameters, exact integer single-year ages, non-empty identifiers,
  non-negative `mean_value`, optional uncertainty bounds, duplicate output
  keys, target-grid completeness, and extra output rows as warnings.
- `disability_weight` is rejected as an unsupported DisMod-MR modelled
  parameter.

Boundary:

- Output reading and validation only.
- No DisMod-MR execution, Python/R-INLA calls, `pmslt_disease_epi.csv`
  conversion, DisMod-lite changes, intervention changes, costs, PSA, or HALY
  changes.

Validation:

- Added `tests/testthat/test-dismod-mr-output.R` with temporary CSV fixtures
  covering valid outputs, strict/non-strict validation, unsupported parameters,
  exact-age checks, duplicate keys, uncertainty bounds, target-grid checks,
  path handling, and print methods.
- `devtools::document()` completed and generated
  `man/read_dismod_mr_outputs.Rd`, `man/validate_dismod_mr_outputs.Rd`, and
  the NAMESPACE exports. Existing manually owned `.Rd` files were skipped by
  roxygen as in earlier slices.
- `devtools::test()` passed with 557 tests.
- `R CMD build .` built `pmslttools_0.0.0.9009.tar.gz`.
- `R CMD check pmslttools_0.0.0.9009.tar.gz --no-manual --no-build-vignettes`
  completed with status OK.

Related artifacts updated:

- `README.md`
- `CODEX.md`
- `inst/artifacts/package_architecture.md`
- `inst/artifacts/todo_plan.md`
- `inst/artifacts/implementation_log.md`

## 2026-05-25: Real DisMod-MR Input Preparation Adapter

Reason:

- The package had teaching/local DisMod-lite helpers but no real file bridge
  from raw disease templates to external DisMod-MR inputs.

Change:

- Added exported `prepare_dismod_mr_inputs()` in `R/dismod-mr-adapter.R`.
- The adapter reads `05_disease_epidemiology_raw.csv` and optional
  `06_dismod_input_skeleton.csv`.
- It writes `dismod_mr_input_long.csv`, `dismod_mr_target_grid.csv`,
  `dismod_mr_input_omissions.csv`, and `dismod_mr_input_summary.csv`.
- Raw evidence age bands are preserved in the long evidence file, while the
  target grid expands to exact integer ages.
- Skeleton values take precedence over matching raw evidence rows, and
  overridden raw rows are reported in the omissions audit.

Boundary:

- File preparation only.
- No DisMod-MR execution, output reader, `pmslt_disease_epi.csv` conversion,
  DisMod-lite changes, intervention changes, PSA, costs, or HALY changes.

Validation:

- Added focused tests for file creation, required long columns, age-band
  preservation, exact-age target-grid expansion, skeleton support and
  precedence, unsupported parameters, disability-weight exclusion, overwrite
  protection, missing raw file errors, and print output.

Related artifacts updated:

- `README.md`
- `CODEX.md`
- `inst/artifacts/package_architecture.md`
- `inst/artifacts/todo_plan.md`
- `inst/artifacts/implementation_log.md`

## 2026-05-22: Workflow Next-Step Guidance

Reason:

- The package now has enough raw-input, DisMod-lite, PMSLT-ready disease input,
  intervention, lifetable, and HALY helpers that beginners need a simple way to
  ask what to do next.

Change:

- Added exported `next_pmslt_step(stage = NULL, object = NULL)` in
  `R/workflow-navigation.R`.
- Added compact S3 print method `print.pmslt_next_step()`.
- Supported explicit stages: `spec`, `templates`, `raw_inputs`,
  `raw_validation`, `dismod_lite`, `pmslt_disease_inputs`,
  `disease_lifetable`, `interventions`, and `halys`.
- Added conservative stage inference for `pmslt_spec`,
  `raw_input_readiness_check`, and `summarised_raw_input_issues` objects.

Boundary:

- Guidance only.
- No modelling functionality, schemas, validators, DisMod-lite behaviour,
  PMSLT-ready disease inputs, lifetable calculations, or reporting semantics
  were changed.

Validation:

- Added focused tests for no-argument guidance, all explicit stages,
  unsupported stages, explicit-stage precedence, object inference, and print
  behaviour.

Related artifacts updated:

- `README.md`
- `CODEX.md`
- `inst/artifacts/package_architecture.md`
- `inst/artifacts/todo_plan.md`
- `inst/artifacts/implementation_log.md`

## 2026-05-22: HALY-style Health Outcome Summaries

Reason:

- PMSLT outputs already include `person_years` and `yld`.
- A lightweight health outcome reporting layer can calculate
  `halys = person_years - yld` without changing the lifetable engine.

Change:

- Added exported `calculate_halys()` in `R/main-lifetable.R`.
- Added exported `compare_halys()` in `R/main-lifetable.R`.
- `calculate_halys()` reuses `summarise_pmslt_results()` internally and
  supports `overall`, `time_step`, `sex`, `stratum`, exact `age`, and
  reporting-only `age_band` summaries.
- HALY summary outputs include `halys`, `person_years`, and `yld`.
- Integrated disease-total summary columns are preserved when present.
- `compare_halys()` validates compatible BAU and intervention row structures,
  then returns `intervention - BAU` differences.
- HALY comparison outputs include `haly_difference`,
  `person_years_difference`, and `yld_difference`; integrated disease-total
  differences are included when both inputs have disease totals.
- Added beginner-friendly errors when `person_years` or `yld` are missing.

Boundary:

- Reporting/calculation layer only.
- No DALYs, discounting, age weighting, costs, PSA, uncertainty intervals, or
  lifetable engine calculations were added or changed.

Validation:

- Added tests for HALY calculation correctness, grouped HALY summaries,
  age-band HALY summaries, disease-total preservation, HALY comparison
  summaries, zero differences for identical inputs, and missing-`yld` errors.

Related artifacts updated:

- `README.md`
- `CODEX.md`
- `inst/artifacts/package_architecture.md`
- `inst/artifacts/todo_plan.md`
- `inst/artifacts/implementation_log.md`
