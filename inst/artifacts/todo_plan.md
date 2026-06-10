# pmslttools Todo Plan

Last updated: 2026-06-10

## Status update 2026-06-10 (0.1.0)

Completed since the last revision:

- One-call end-to-end driver `run_pmslt()` (Module IV/V equivalent) chaining
  disease consistency, intervention deltas, the all-cause main lifetable, and
  HALY/cost/ICER reporting into a `pmslt_run` object.
- `prepare_lifetable_inputs()` bridges the age-banded census templates
  (`01`-`03`) to the exact-age main lifetable (closes the "Module I not yet
  migrated" gap for template-sourced inputs).
- Phase 5.1 cost discounting (`discount_rate`), 5.2 pipeline-wide PSA with
  HALY/cost/ICER uncertainty intervals, 5.3 scenario label, and 5.4 equity
  disaggregation are wired through `run_pmslt()`.
- Phase 6.1 vignette (`pmslt-end-to-end`) and 6.3 concept guide added.

Remaining / future work:

- 6.2 demo folder regeneration (the demo dir is gitignored; optional).
- Population-weighted equity preservation (renormalising mode) — current equity
  is reference-stratum scaling only.
- Per-arm disease-specific cost detail under intervention rates (costing
  currently uses BAU disease prevalence carried through the bridge).

(Original plan below retained for history.)

## Guiding Priorities

1. Keep the package beginner-friendly.
2. Stabilise input and output schemas before expanding the engine.
3. Keep raw, disease consistency solver outputs, and PMSLT-ready files
   separate.
4. Make intervention handling intuitive at template stage and model stage.
5. Add full PMSLT components only after disease input contracts are clear.

## Source Template Migration Map

This package is being built from the modelling ideas in
`../PMSLT_Template_v1.R`, but the script should not be copied directly. The
package has clearer CSV schemas, post-DisMod disease inputs, and multi-arm
intervention handling. The source template should be mined module by module.

Migration status:

- Pre-simulation coherence check: partly superseded by `diagnose_missing_parameters()`
  and `dismod_slove()`. Still useful for future raw validation messages.
- Module I main lifetable initialisation: not yet migrated. Needed for full
  population PMSLT.
- Module II PIF calculation: migrated and improved as `calculate_pif_from_inputs()`.
- Module III disease lifetable: partly migrated as `run_pmslt_disease_lifetable()`;
  disease costs and YLD outputs still need migration.
- Module IV main lifetable integration: not yet migrated. This is the most
  important next engine layer after intervention validation.
- Module V aggregation and ICERs: not yet migrated. Needed after main lifetable.
- Equity mortality disaggregation: not yet migrated. Should be connected to
  `11_stratum_rate_ratios.csv`.
- Master execution pipeline: should be rebuilt later as `run_pmslt()`, not
  copied directly.
- PSA sampler and probabilistic wrapper: useful design, but should be rebuilt
  after deterministic schemas and engine outputs stabilise.

## Phase 1: Clarify Current Intervention Layer

Status: in progress

### 1.1 Rename direct-effect helper

Status: completed 2026-05-17.

Problem:

- `add_direct_effect_multipliers()` is technically correct but unclear.

Todo:

- Rename to `apply_direct_disease_effects()` or
  `attach_direct_effect_multipliers()`.
- Add a short explanatory comment for:

```r
effective_multiplier <- 1 - coverage * (1 - rr)
```

Acceptance criteria:

- Tests still pass.
- `run_pmslt_interventions()` output unchanged.
- Source code is clearer to a beginner reading it.

Implementation note:

- Renamed the helper to `apply_direct_disease_effects()`.
- Added an explanatory code comment about converting treatment-group RR and
  coverage into a population-level multiplier.

### 1.2 Validate prevalence distributions

Status: completed 2026-05-17.

Problem:

- PIF calculation currently requires complete prevalence and RR values but does
  not check that category prevalence sums to 1.

Todo:

- Add `validate_risk_prevalence_inputs()`.
- Check BAU category sums by age, sex, stratum, time step, and risk factor.
- Check intervention category sums by age, sex, stratum, time step, risk factor,
  and intervention.
- Use a default tolerance such as `1e-6` or `0.001`.
- Produce plain-language warnings or errors.

Acceptance criteria:

- Bad category sums are detected.
- Error messages identify the affected risk factor and intervention arm.

Implementation note:

- Added exported `validate_risk_prevalence_inputs()`.
- `calculate_pif_from_inputs()` now calls this validation before joining RRs.
- Added tests for valid mock prevalence inputs and invalid category sums.

### 1.3 Document multi-risk-factor PIF assumptions

Status: completed 2026-05-17.

Problem:

- Multiple risk-factor PIFs are combined as `1 - prod(1 - pif)`.

Todo:

- Document this in `calculate_pif_from_inputs()` help.
- Add an argument later if needed:

```r
pif_combination = c("independent", "additive")
```

Acceptance criteria:

- Users understand the independence-style assumption.

Implementation note:

- Documented the `1 - prod(1 - pif)` independence-style approximation in
  `calculate_pif_from_inputs()` documentation.

## Phase 2: Stabilise Schemas

Status: high priority

### 2.1 Create central schema definitions

Status: completed 2026-05-17.

Problem:

- Template columns, guide descriptions, requirements, and validators are
  duplicated across files.

Todo:

- Add `R/schema.R`.
- Define one schema object per CSV file.
- Include:
  - file name
  - column names
  - requirement level
  - description
  - validation type
  - allowed values where relevant

Acceptance criteria:

- `draft_input_templates()`, `00_column_dictionary.csv`, and
  `README_inputs_raw.md` draw from the same schema source.

Implementation note:

- Added `R/schema.R` with central schema definitions for each raw CSV template.
- `00_column_dictionary.csv` now includes `validation_type` and
  `allowed_values` columns from the same schema source.
- `README_inputs_raw.md` now prints requirement and validation metadata from
  the central schema.

### 2.2 Add raw input validators

Status: completed 2026-05-18.

Problem:

- The package generates raw templates but does not yet have a comprehensive raw
  input validation step.

Todo:

- Add `validate_raw_inputs(input_dir, spec = NULL)`.
- Validate required files.
- Validate generated ID columns.
- Validate required/conditional columns.
- Validate rates are non-negative and proportions are 0 to 1.
- Validate risk categories match across prevalence and RR files.

Acceptance criteria:

- A beginner can run one command after filling templates and get a clear issue
  list.

Implementation note:

- Added exported `validate_raw_inputs(input_dir, spec = NULL)`.
- The validator uses central schema metadata plus optional `pmslt_spec`
  information to check expected files, duplicate files, duplicated columns,
  unexpected columns, missing columns, required missing values, numeric types,
  allowed generated values, duplicate identifying rows, non-negative rates,
  proportions bounded by 0 and 1, positive relative risks/rate ratios,
  age-band ordering, and simple uncertainty bounds.
- It returns all issues it can find instead of stopping early, including a
  stable issue table when `input_dir` does not exist or is not a folder.

### 2.3 Add issue-list output format

Status: completed 2026-05-18.

Problem:

- Validation should not always stop at the first error.

Todo:

- Return a data frame with:
  - file
  - row
  - column
  - severity
  - message
  - suggested_fix

Acceptance criteria:

- Validation output can be printed, saved to CSV, or used in a future Shiny app.

Implementation note:

- Added internal helpers `new_validation_issue()`,
  `append_validation_issue()`, `append_validation_issues()`, and
  `empty_validation_issues()`.
- `validate_raw_inputs()` returns an S3 data frame with class
  `pmslt_validation_issues` and stable columns:
  `file`, `row`, `column`, `severity`, `message`, `suggested_fix`.
- Added a `print.pmslt_validation_issues()` method with issue counts by
  severity and a short preview.
- Added exported `summarise_raw_input_issues()` with a compact can-proceed
  signal, error and warning counts, file-level counts, and beginner-facing
  next-step guidance.
- Added exported `check_raw_input_readiness()` as the beginner-facing one-step
  helper that returns the validation issue table, summary, `can_proceed`, and
  `next_step` without duplicating validation rules.

## Phase 3: Improve Disease Consistency Solver Integration

Status: high priority

### 3.0 Solver refactor decision record

Status: planned from 2026-05-25 grill-me design session.

Decision:

- Replace the external DisMod-MR-centred direction with a package-native
  disease consistency solver workflow.
- Add `solve_disease_consistency(input_dir, solver = ...)` as the
  beginner-facing bridge from raw disease inputs to canonical
  `pmslt_disease_epi.csv`.
- Keep `dismod_slove()` as a valid deterministic modelling option, not only a
  teaching helper.
- Make `disbayes` the planned primary real consistency solver once the adapter
  and execution path are implemented and tested.
- Keep `disbayes` optional in `Suggests`; the package should still install,
  load, validate templates, run deterministic workflows, and run
  `dismod_slove()` without Stan/RStan being configured.
- Hard remove the external DisMod-MR adapter API during this refactor rather
  than keeping deprecated callable aliases.
- Reuse the existing PMSLT raw templates rather than adding a separate
  disbayes-native user template.
- Add explicit disease mortality evidence:
  - `05_disease_epidemiology_raw.csv` gains `disease_mortality_rate`.
  - `06_dismod_input_skeleton.csv` allows `parameter = "mortality"`.
  - `excess_mortality_rate` must not be silently reinterpreted as disbayes
    mortality.
- Keep the filename `06_dismod_input_skeleton.csv`, but redefine it as generic
  long-format disease-consistency solver evidence.
- Keep solver-grade uncertainty only in `06_dismod_input_skeleton.csv` for the
  first disbayes slices.
- Keep `pmslt_disease_epi.csv` rate-based and explicit. The disbayes adapter
  converts rates to probabilities internally and records the conversion in an
  audit table.
- Fit disbayes independently by `disease + sex + stratum` in the first
  implementation.
- Require disbayes evidence to include mortality plus at least one of incidence
  or prevalence. If a group is under-specified, stop with diagnostics and let
  the user fill evidence or choose `solver = "dismod_slove"`.
- Fit disbayes internally on a complete `0:max(target_age)` single-year age
  grid, then subset final PMSLT-ready output back to the target PMSLT ages.
- Expand age-banded evidence using a constant-within-band rule in the first
  slice, and audit whether rows are exact, expanded, or padded.
- Keep `mock_dismod_output()` as demo/test-data generation only; it is not a
  `solve_disease_consistency()` solver option.
- Split the refactor into staged implementation slices.

Staged implementation plan:

1. Schema/API cleanup slice:
   add `disease_mortality_rate`, add skeleton `mortality`, hard remove
   external DisMod-MR, add `solve_disease_consistency()` with the
   `dismod_slove` branch working end to end, and leave the disbayes branch as
   an explicit not-yet-implemented message.
2. Disbayes adapter preparation slice:
   add single-year expansion, rate-to-probability conversion, uncertainty
   diagnostics, group evidence checks, and audit table generation without
   running Stan.
3. Disbayes execution slice:
   call `disbayes::disbayes()`, tidy results, map outputs back to rate-based
   PMSLT disease inputs, and write fit summaries and long parameter outputs.
4. Workflow/docs slice:
   update `next_pmslt_step()`, README, architecture, todo plan, implementation
   log, examples, and beginner-facing guidance so the new main path is clear.

Temporary default rule:

- In Slice 1, default `solve_disease_consistency()` to `solver =
  "dismod_slove"` because that branch can run immediately.
- After the disbayes execution slice is implemented and tested, switch the
  default to `solver = "disbayes"` while retaining `solver = "dismod_slove"`.

### 3.0a Implement solver refactor Slice 1

Status: implemented 2026-05-25.

Completed:

- Added `disease_mortality_rate` to `05_disease_epidemiology_raw.csv` in the
  template generator, schema metadata, input guide, validators, mock data, and
  tests.
- Added `mortality` to the allowed long-format parameters in
  `06_dismod_input_skeleton.csv`.
- Updated plain-language guidance so `mortality` means disease-specific
  mortality evidence for consistency solvers, while `excess_mortality_rate`
  remains excess mortality among people with disease.
- Kept `06_dismod_input_skeleton.csv` as the filename, but described it as
  generic disease-consistency solver evidence.
- Removed external DisMod-MR source files, exports, tests, man pages, README
  sections, and artifact references from the active workflow.
- Added exported `solve_disease_consistency()` with:
  - `solver = c("dismod_slove", "disbayes")` for the transitional slice.
  - `solver = "dismod_slove"` writing canonical `pmslt_disease_epi.csv` plus
    existing diagnostic outputs.
  - `solver = "disbayes"` stopping with a clear not-yet-implemented message.
- Updated `next_pmslt_step()` so the post-readiness recommendation is
  `solve_disease_consistency()`, not direct `dismod_slove()`.
- Updated `CODEX.md`, `inst/artifacts/package_architecture.md`,
  `inst/artifacts/todo_plan.md`, and `inst/artifacts/implementation_log.md`.
- Package-aware validation completed: `devtools::document()` and
  `devtools::test()` passed with 521 tests.

Acceptance criteria:

- `solve_disease_consistency(input_dir, solver = "dismod_slove")` creates a
  valid exact-age `pmslt_disease_epi.csv`.
- Direct `dismod_slove()` remains available for users who want solver
  diagnostics.
- `mock_dismod_output()` remains available but is documented as demo/test-data
  generation only.
- No active beginner-facing documentation recommends the external DisMod-MR
  adapter.
- Tests cover the new disease mortality column, skeleton `mortality`
  parameter, high-level `dismod_slove` branch, and clear disbayes placeholder
  error.

### 3.0b Prepare disbayes adapter without execution

Status: planned after Slice 1.

Todo:

- Convert raw and skeleton evidence into a disbayes-ready internal table by
  `disease`, `sex`, and `stratum`.
- Expand age bands to exact single-year rows using a constant-within-band rule.
- Pad internal disbayes fit ages to `0:max(target_age)` and mark padded rows in
  the audit.
- Convert rate evidence to annual probabilities only inside the adapter using
  `1 - exp(-rate)`.
- Require mortality plus at least one of incidence or prevalence for every
  group.
- Require usable uncertainty by default: `lower_95`/`upper_95` or
  `sample_size` in `06_dismod_input_skeleton.csv`.
- Produce audit tables for source rows, converted probabilities, age
  expansion, missing evidence, and insufficient uncertainty.
- Keep point-estimate-only groups on the `dismod_slove()` path unless the user
  explicitly enables default uncertainty in a later option.

Acceptance criteria:

- Adapter diagnostics are structured and beginner-readable.
- No Stan or `disbayes` execution is required for this slice's tests.
- Evidence failures tell the user to fill more skeleton evidence or choose
  `solver = "dismod_slove"`.

### 3.0c Execute disbayes solver and bridge to PMSLT

Status: planned after adapter preparation.

Todo:

- Add optional `disbayes` dependency checks with a clear install/setup message.
- Fit one `disbayes::disbayes()` model per disease, sex, and stratum.
- Default to an execution method that is practical for package users, with
  advanced method choices exposed through solver options.
- Tidy disbayes outputs and map:
  - `inc` to `incidence_BAU`
  - `rem` to `remission_rate`
  - `cf` to `case_fatality_BAU`
  - `prev_prob` to `prevalence_initial`
- Carry raw `excess_mortality_rate` to `excess_mortality_BAU` when explicitly
  supplied; otherwise leave `excess_mortality_BAU` missing with provenance. Do
  not silently copy case fatality into excess mortality.
- Join `disability_weight` from raw disease inputs by disease, sex, stratum,
  and target exact age.
- Write canonical `pmslt_disease_epi.csv`, long solver parameter outputs, fit
  summaries, and audit files.
- After this slice is validated, change the high-level default to
  `solver = "disbayes"`.

Acceptance criteria:

- The package still loads and non-disbayes workflows still run without
  `disbayes` installed.
- Tests for actual disbayes execution are skipped when `disbayes` is not
  available.
- The final PMSLT-ready file remains rate-based, exact-age, and validated by
  `validate_pmslt_disease_inputs()`.

### 3.1 Separate teaching DisMod from real DisMod adapters

Status: superseded and removed from the active roadmap by Slice 1.

Outcome:

- The package no longer keeps an external DisMod-MR active API.
- `dismod_slove()` remains a deterministic package-native solver and
  diagnostic helper.
- `mock_dismod_output()` remains demo/test-data generation only.
- Future real consistency-solver work should continue through the
  `solve_disease_consistency()` disbayes adapter and execution slices above.

### 3.2 Define canonical DisMod output contract

Status: completed 2026-05-18.

Problem:

- Downstream modules need a stable post-DisMod format.

Todo:

- Formalise `pmslt_disease_epi.csv` schema.
- Add a section to architecture docs.
- Add `write_pmslt_disease_inputs()` if useful.

Acceptance criteria:

- Every downstream disease module consumes the same schema.

Implementation note:

- Added central PMSLT-ready schema metadata in `R/schema.R` via
  `pmslt_ready_input_schemas()` and `pmslt_disease_epi_schema()`.
- Kept PMSLT-ready schemas separate from raw input template schemas.
- Formalised `pmslt_disease_epi.csv` as the canonical downstream disease
  epidemiology input with required columns:
  `age`, `sex`, `stratum`, `disease`, `time_step`, `incidence_BAU`,
  `prevalence_initial`, `remission_rate`, `excess_mortality_BAU`,
  `case_fatality_BAU`, `disability_weight`.
- Refactored the canonical disease file to exact single-year age resolution:
  raw disease files may remain age-banded, but `pmslt_disease_epi.csv` must
  have one row per disease, sex, stratum, time step, and integer age.
- `prepare_pmslt_disease_inputs()` now orders output columns from the canonical
  schema, writes single-year rows from post-DisMod age smoothing, and validates
  the prepared file before writing.
- `validate_pmslt_disease_inputs()` now derives required columns from the
  canonical schema and checks required columns, integer age, numeric fields,
  non-negative rates, proportions between 0 and 1, and rejection of age-band
  columns in PMSLT-ready disease inputs.
- Added tests for schema existence, writer alignment, reader acceptance, and
  validator rejection paths.
- Audit follow-up confirmed that examples and downstream disease workflow tests
  use exact-age `pmslt_disease_epi.csv`, while raw age-banded inputs remain
  separate and may be expanded where intervention inputs intentionally cover
  age bands.

### 3.2a Define real DisMod-MR output adapter contract

Status: superseded and removed from the active roadmap by Slice 1.

Outcome:

- External DisMod-MR output reading, validation, and bridge code were removed
  from the active package API.
- Future output contracts should be defined for `solve_disease_consistency()`
  solver branches, starting with the disbayes preparation and execution slices
  above.

### 3.3 Improve continuous-age diagnostics and reporting

Problem:

- The canonical PMSLT-ready disease input is now single-year. Age-band mapping
  remains useful for diagnostic summaries and output reporting, but should not
  define internal simulation state.

Todo:

- Document when to use each method.
- Consider weighted age-band averaging if population weights are available.

Acceptance criteria:

- Students understand when discrete age bands are acceptable and when
  continuous-age smoothing should be used.
- Documentation clearly says age bands are for raw input convenience and
  reporting, while `pmslt_disease_epi.csv` is single-year.

## Phase 4: Build Full PMSLT Model Modules

Status: medium priority, after schemas

### 4.1 Main all-cause lifetable

Source template reference:

- `PMSLT_Template_v1.R::initialize_main_lifetable()`

Todo:

- Add `initialize_pmslt_lifetable()`.
- Use:
  - `01_population.csv`
  - `02_all_cause_mortality.csv`
  - `03_all_cause_morbidity.csv`
  - `04_life_expectancy.csv`
- Track alive, deaths, person-years, morbidity, and life years by age, sex,
  stratum, and time step.

Acceptance criteria:

- BAU lifetable runs without disease interventions.

Implementation note:

- Added exported `initialize_pmslt_lifetable(population, mortality, morbidity = NULL, spec = NULL)`.
- The first slice accepts data frames or CSV paths, requires exact integer
  single-year `age`, and validates `age`, `sex`, `stratum`, `population`,
  `mortality_rate`, and optional `morbidity_rate`.
- It accepts template-style column aliases `initial_population`, `acmr_BAU`,
  and `pYLD_BAU` while returning standard engine columns.
- It runs one deterministic BAU time step only:
  `deaths = population * mortality_rate`,
  `alive_end = population - deaths`, and
  `person_years = population - 0.5 * deaths`.
- It does not yet use life expectancy, age the population, integrate disease
  deltas, model interventions, add costs, or run PSA.
- Added exported `run_pmslt_lifetable_bau(population, mortality, morbidity = NULL, horizon = NULL, spec = NULL)`.
- The BAU runner extends the same all-cause calculations across yearly cycles
  with exact consecutive single-year ages.
- `horizon` is taken from the explicit argument, then `spec$horizon`, then
  defaults to 1.
- Static mortality and morbidity rates are reused each cycle when no
  `time_step` column exists. Time-varying rates are matched by `time_step`
  when present.
- Survivors age forward one year per cycle. The minimum starting age receives
  no new entrants, and the maximum age is treated as open-ended for now.
- The BAU runner does not add births, migration, entrants, disease deltas,
  intervention effects, costs, equity, or PSA.

### 4.2 Disease delta integration

Source template reference:

- `PMSLT_Template_v1.R::run_main_lifetable()`

Todo:

- Add `integrate_disease_deltas()`.
- Combine disease-specific mortality and morbidity deltas into all-cause
  lifetable quantities.
- Decide and document whether disease deltas are additive, multiplicative, or
  capped.

Acceptance criteria:

- `run_pmslt_interventions()` can feed a main PMSLT model.

Implementation note:

- Added exported `integrate_disease_deltas(lifetable, disease_epi)`.
- This first slice attaches disease-attributable quantities beside
  `run_pmslt_lifetable_bau()` output, rather than changing all-cause deaths.
- Inputs use the canonical exact-age `pmslt_disease_epi.csv` contract and are
  validated with `validate_pmslt_disease_inputs()`.
- Joins are validated by `time_step`, `age`, `sex`, and `stratum`.
- Deterministic formulas are:
  `disease_cases = person_years * incidence_BAU`,
  `disease_deaths = person_years * prevalence_initial * case_fatality_BAU`,
  and `disease_yld = person_years * prevalence_initial * disability_weight`.
- Multiple diseases are aggregated into `total_disease_cases`,
  `total_disease_deaths`, and `total_disease_yld` on each lifetable row.
- Disease-specific long output is preserved in the `disease_deltas` attribute.
- No intervention effects, PIFs, direct effects, costs, PSA, or equity logic
  were added.

### 4.3 Population ageing

Status: completed for deterministic BAU all-cause lifetable slice.

Todo:

- Implement age advancement between cycles.
- Decide how open-ended age bands are handled.
- Test conservation of population except deaths and migration assumptions.

Acceptance criteria:

- Population flow through age bands is transparent and tested.

Implementation note:

- Population ageing is implemented for exact single-year ages in
  `run_pmslt_lifetable_bau()`.
- The implemented maximum-age rule is open-ended single-age retention:
  survivors at the maximum age remain there and survivors from the previous age
  also age into the maximum age.
- No births, migration, entrants, or new cohorts are introduced.

### 4.4 Outcome summaries

Source template reference:

- `PMSLT_Template_v1.R::aggregate_population_results()`

Todo:

- Add `summarise_pmslt_results()`.
- Summarise BAU all-cause outputs overall and by exact `time_step`, `age`,
  `sex`, and `stratum`.
- Summarise attached disease totals when `integrate_disease_deltas()` has been
  run.
- Use `attr(results, "disease_deltas")` for disease-specific summaries when
  `by` includes `disease`.
- Add reporting-only `age_band` summaries using age bands stored in
  `pmslt_spec()`, without changing single-year lifetable calculations.
- Later modules can add:
  - life years
  - HALYs/DALYs
  - deaths avoided
  - morbidity changes
  - stratified differences

Acceptance criteria:

- BAU and disease-delta outputs can be summarised by exact age, disease, sex,
  stratum, time, and configured age band.
- Intervention summaries remain future work.

Implementation note:

- Added exported `summarise_pmslt_results(results, by = ...)`.
- `by = "overall"` returns one ungrouped summary row.
- Non-disease summaries include `population`, `deaths`, `person_years`, and
  `yld` when present.
- Integrated disease summaries also include `total_disease_cases`,
  `total_disease_deaths`, and `total_disease_yld`.
- Disease-specific summaries require the `disease_deltas` attribute and return
  `disease_cases`, `disease_deaths`, and `disease_yld`.
- Age-band summaries are now supported with `by = "age_band"` or
  `group_by = "age_band"` when results were created with
  `spec = pmslt_spec(..., ages = age_bands(...))`.
- Disease-specific summaries can group by both `disease` and `age_band`.
- Age-band reporting is an aggregation layer only; exact integer age remains
  the engine state.

## Phase 4.4: Intervention Comparison Reporting

Status: implemented

Todo:

- Add `compare_pmslt_results()`.
- Validate that BAU and intervention results are PMSLT lifetable outputs.
- Validate matching `time_step`, `age`, `sex`, and `stratum` structure before
  comparing summaries.
- Return simple `intervention - BAU` deltas for all-cause metrics and
  integrated disease-total metrics when present.
- Support overall, exact-age, age-band, time-step, sex, and stratum reporting
  groups.

Acceptance criteria:

- Compatible BAU and intervention outputs compare overall and by grouped
  summaries.
- Age-band comparison remains a reporting aggregation using `spec$ages`.
- Mismatched structures fail with a clear beginner-friendly error.
- Identical inputs return zero deltas.
- No intervention simulation mechanics, costs, PSA, HALYs, DALYs, discounting,
  or engine changes are added.

Implementation note:

- Added exported `compare_pmslt_results(bau_results, intervention_results, by = ...)`.
- Differences are named with a `_difference` suffix, for example
  `population_difference`, `deaths_difference`,
  `person_years_difference`, and `yld_difference`.
- Integrated disease totals are compared when both inputs include
  `total_disease_cases`, `total_disease_deaths`, and `total_disease_yld`.
- Disease-specific long-output contrasts remain optional later work.

## Phase 4.5: HALY-style Health Outcome Reporting

Status: implemented

Todo:

- Add `calculate_halys()`.
- Add `compare_halys()`.
- Calculate HALYs as `person_years - yld` using existing PMSLT output
  summaries.
- Support overall, time-step, sex, stratum, exact-age, and reporting-only
  age-band summaries.
- Preserve integrated disease-total summary columns when present.
- Require `yld` data and provide beginner-friendly errors when it is missing.
- Validate compatible BAU and intervention structures before comparison.

Acceptance criteria:

- HALY summaries return `halys`, `person_years`, and `yld`.
- Comparison summaries return `haly_difference`,
  `person_years_difference`, and `yld_difference`.
- Identical inputs return zero differences.
- No DALYs, discounting, age weighting, costs, PSA, uncertainty intervals, or
  lifetable engine changes are added.

Implementation note:

- Added exported `calculate_halys(results, by = ...)`.
- Added exported `compare_halys(bau_results, intervention_results, by = ...)`.
- Both helpers reuse the existing summary/comparison layer in
  `R/main-lifetable.R`.
- `calculate_halys()` requires `person_years` and `yld`, then reports
  `halys = person_years - yld`.
- `compare_halys()` calculates differences as `intervention - BAU`.

## Phase 5: Costs and PSA

Status: later

### 5.1 Cost module

Source template reference:

- `PMSLT_Template_v1.R::run_disease_lifetable()`
- `PMSLT_Template_v1.R::run_main_lifetable()`

Todo:

- Consume `12_costs.csv`.
- Separate disease costs, background costs, and intervention costs.
- Add discounting.

### 5.2 Probabilistic sensitivity analysis

Source template reference:

- `PMSLT_Template_v1.R::draw_psa_parameters()`
- `PMSLT_Template_v1.R::run_probabilistic_pmslt()`

Todo:

- Define uncertainty inputs.
- Add parameter draw engine.
- Run repeated PMSLT simulations.
- Summarise uncertainty intervals.

### 5.3 Scenario management

Todo:

- Store assumptions per intervention arm.
- Allow scenario labels and scenario metadata.
- Support comparing multiple interventions and combined intervention packages.

### 5.4 Equity disaggregation

Source template reference:

- `PMSLT_Template_v1.R::disaggregate_mortality()`

Todo:

- Add a tested base-R helper for converting aggregate rates to stratum-specific
  rates using supplied rate ratios.
- Connect it to `11_stratum_rate_ratios.csv`.
- Preserve the aggregate total while applying stratum rate ratios.

Acceptance criteria:

- Weighted stratum-specific survival reproduces aggregate survival.

## Phase 6: Teaching Materials

Status: ongoing

### 6.0 Add workflow next-step guidance

Status: completed

Completed:

- Added exported `next_pmslt_step(stage = NULL, object = NULL)`.
- Supported beginner workflow stages from `spec` through `halys`.
- Added conservative S3 class inference for `pmslt_spec`,
  `raw_input_readiness_check`, and `summarised_raw_input_issues`.
- Kept the helper guidance-only; no raw schemas, DisMod-lite behaviour,
  PMSLT-ready disease inputs, lifetable calculations, or reporting semantics
  were changed.

### 6.1 Add vignette

Todo:

- Create `vignettes/pmslt_workflow_from_spec_to_interventions.Rmd`.
- Walk through:
  1. Model spec.
  2. Template generation.
  3. Filling mock data.
  4. DisMod-lite/mock DisMod.
  5. Plotting corrections.
  6. Post-DisMod disease input.
  7. PIF and direct intervention modelling.

### 6.2 Regenerate demo folder

Problem:

- `demo_mock_inputs_raw/` may not reflect the latest multi-arm/direct-effect
  template structure.

Todo:

- Regenerate with current `generate_mock_pmslt_inputs()`.
- Run `mock_dismod_output()`.
- Include `10_direct_intervention_effects.csv` if demo data is committed.

### 6.3 Add concept guide

Todo:

- Add a plain-language document:
  `inst/artifacts/pmslt_concepts_for_beginners.md`.
- Explain:
  - BAU vs intervention
  - incidence vs prevalence
  - remission
  - excess mortality vs case fatality
  - disability weight
  - PIF
  - direct disease effects
  - why DisMod is used

## Commit Checklist

Before each meaningful push:

```r
devtools::test()
```

Before each package milestone:

```sh
R CMD build .
R CMD check pmslttools_*.tar.gz --no-manual --no-build-vignettes
```

Before changing CSV schemas:

- Update template generator.
- Update input guide.
- Update column dictionary.
- Update validators.
- Update mock data.
- Update tests.
- Update architecture docs if the workflow changes.
