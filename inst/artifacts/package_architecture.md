# pmslttools Package Architecture

Last updated: 2026-05-25

## Package Aim

`pmslttools` is being built as a beginner-friendly R package for planning,
structuring, and running proportional multistate lifetable (PMSLT) simulation
projects. The package should guide a new modeller from a small model
specification to project-specific input templates, DisMod-style disease
parameter processing, intervention modelling, and eventually full PMSLT
population outputs.

The package is intentionally workflow-oriented. Functions should make the next
modelling step obvious, use plain-language errors, and keep raw input files as
an audit trail.

## Current High-Level Workflow

```r
spec <- pmslt_spec(
  intervention = "Tobacco tax",
  intervention_arms = c("Tax only", "Tax plus acute care"),
  mechanism = "both",
  diseases = c("CHD", "Stroke"),
  risk_factors = "Smoking",
  risk_categories = list(Smoking = c("Never", "Current", "Former")),
  ages = age_bands(40, 80, by = 10, open_ended = FALSE),
  sexes = c("male", "female"),
  strata = "total",
  horizon = 10
)

draft_input_templates(spec, output_dir = "inputs_raw")
dismod_slove("inputs_raw")

disease_epi <- read_pmslt_disease_inputs(
  "inputs_raw/mock_dismod_output/pmslt_disease_epi.csv"
)

results <- run_pmslt_interventions(
  disease_epi = disease_epi,
  risk_prevalence = "inputs_raw/08_risk_factor_prevalence.csv",
  relative_risks = "inputs_raw/09_relative_risks.csv",
  direct_effects = "inputs_raw/10_direct_intervention_effects.csv"
)
```

## Relationship To `PMSLT_Template_v1.R`

The original script at `../PMSLT_Template_v1.R` is treated as a prototype, not
as package-ready source. Its conceptual modules map to the package as follows:

- Pre-simulation epidemiological coherence checks inform diagnostics and raw
  validators.
- Module I main lifetable initialisation should become a package-level
  all-cause lifetable module.
- Module II PIF calculation has been superseded by
  `calculate_pif_from_inputs()`, which uses package CSV schemas and supports
  multiple intervention arms.
- Module III disease lifetable has been partly superseded by
  `run_pmslt_disease_lifetable()`, which consumes post-DisMod
  `pmslt_disease_epi.csv`; disease costs and YLD outputs still need migration.
- Module IV main lifetable integration remains to be rebuilt using package
  naming and schemas.
- Module V aggregation and ICER summaries remain to be rebuilt after the main
  lifetable is implemented.
- The equity mortality disaggregation helper should be migrated and connected
  to `11_stratum_rate_ratios.csv`.
- The PSA functions should be rebuilt after deterministic schemas and outputs
  stabilise.

Migration rule:

- Port modelling ideas from the original script into schema-driven package
  modules. Do not copy the old tidyverse-dependent implementation directly.

## Layer 1: Model Specification

Files:

- `R/spec.R`

Public functions:

- `pmslt_spec()`
- `age_bands()`
- `validate_spec()`

Responsibilities:

- Capture the minimum model design information.
- Store diseases, risk factors, risk categories, sexes, strata, age bands,
  horizon, intervention mechanism, and multiple intervention arms.
- Validate that risk-factor models have risk factors and categories.
- Provide a readable print method for beginner review.

Key object:

- `pmslt_spec`: a list with class `pmslt_spec`.

Important fields:

- `intervention`: broad project or intervention name.
- `intervention_arms`: named model scenarios compared with BAU.
- `mechanism`: `risk_factor`, `direct`, or `both`.
- `risk_categories`: named list, for example
  `list(Smoking = c("Never", "Current", "Former"))`.

Design rule:

- The specification is not a data file. It defines the shape of the data files.

## Layer 2: Raw Input Template Generation

Files:

- `R/templates.R`
- `R/input-guide.R`

Public functions:

- `draft_input_templates()`
- `write_input_template_guide()`

Main output files:

- `00_column_dictionary.csv`
- `00_model_specification.csv`
- `01_population.csv`
- `02_all_cause_mortality.csv`
- `03_all_cause_morbidity.csv`
- `04_life_expectancy.csv`
- `05_disease_epidemiology_raw.csv`
- `06_dismod_input_skeleton.csv`
- `07_bau_trends.csv`
- `08_risk_factor_prevalence.csv`
- `09_relative_risks.csv`
- `10_direct_intervention_effects.csv`
- `11_stratum_rate_ratios.csv`
- `12_costs.csv`
- `README_inputs_raw.md`

Responsibilities:

- Convert `pmslt_spec` into beginner-fillable CSV templates.
- Mark generated, required, conditional, and optional columns.
- Explain each empty column in `README_inputs_raw.md`.
- Expand risk-factor prevalence and direct-effect templates across
  `intervention_arms`.

Current template logic:

- Risk-factor files are generated when `mechanism` is `risk_factor` or `both`.
- Direct-effect files are generated when `mechanism` is `direct` or `both`.
- Stratum rate-ratio files are generated when non-total or multiple strata are
  supplied.
- Cost files are generated when `cost_effectiveness = TRUE`.

Design rule:

- Generated identifier columns should not require user editing unless the model
  specification was wrong. Users should revise `pmslt_spec()` and regenerate
  rather than manually reshaping files.

## Layer 3: Raw Input Validation

Files:

- `R/raw-validation.R`

Public functions:

- `validate_raw_inputs()`
- `summarise_raw_input_issues()`
- `check_raw_input_readiness()`

Responsibilities:

- Validate raw CSV files generated by `draft_input_templates()` before DisMod
  processing.
- Use `R/schema.R` as the central source for expected files, columns,
  requirement levels, validation types, and allowed values.
- Accumulate beginner-readable issues in a stable table with columns:
  `file`, `row`, `column`, `severity`, `message`, and `suggested_fix`.
- Summarise validation issues into a compact can-proceed signal, next-step
  guidance, and file-level issue counts.
- Provide a one-step readiness check that returns both the issue table and the
  summary without duplicating validation rules.
- Check file existence, duplicate files, required columns, unexpected columns,
  duplicated column names, missing required values, type coercion, duplicate
  identifying rows, allowed generated values when a `pmslt_spec` is supplied,
  basic numeric bounds, age-band ordering, and simple uncertainty-bound
  ordering.

Boundary:

- This layer validates raw user input files only. It does not replace DisMod
  validation, post-DisMod `pmslt_disease_epi.csv` validation, or advanced
  epidemiological coherence checks.

Design rule:

- Raw validation should keep going wherever possible and return a complete
  issue table instead of stopping after the first problem.

## Layer 3a: Workflow Navigation

Files:

- `R/workflow-navigation.R`

Public functions:

- `next_pmslt_step()`

Responsibilities:

- Provide beginner-friendly next-step guidance without running modelling code.
- Support explicit workflow stages from model specification through HALY
  reporting.
- Conservatively infer stages from stable pmslttools S3 classes such as
  `pmslt_spec`, `raw_input_readiness_check`, and
  `summarised_raw_input_issues`.

Boundary:

- This layer is guidance only. It must not change raw inputs, schemas,
  DisMod-lite behaviour, PMSLT-ready disease inputs, lifetable calculations, or
  reporting semantics.

## Layer 4: Missing Parameter Diagnostics

Files:

- `R/diagnostics.R`

Public functions:

- `diagnose_missing_parameters()`

Responsibilities:

- Explain whether each disease has enough raw epidemiological parameters for
  DisMod-style processing.
- Produce plain-language guidance for users who do not yet know which disease
  parameters are needed.

Current rule:

- The diagnostic expects at least three disease parameter types among incidence,
  prevalence, remission, excess mortality, and case fatality to be reasonably
  DisMod-ready.

Design rule:

- Diagnostics should teach. They should not only fail validation.

## Layer 5: DisMod-Lite and Mock DisMod Processing

Files:

- `R/dismod-lite.R`
- `R/mock-dismod.R`

Public functions:

- `dismod_slove()`
- `mock_pmslt_spec()`
- `generate_mock_pmslt_inputs()`
- `mock_dismod_output()`
- `smooth_dismod_age_curve()`
- `predict_dismod_to_age_grid()`
- `prepare_pmslt_disease_inputs()`
- `plot_dismod_corrections()`
- `plot_dismod_age_curve()`

Responsibilities:

- Provide a teaching-oriented DisMod-like process.
- Read raw disease inputs and long DisMod skeleton inputs.
- Expand coarse age observations to exact single-year ages for internal
  PMSLT-ready disease inputs.
- Fill identifiable missing values using simple steady-state illness-death
  equations.
- Optionally propagate uncertainty using Monte Carlo draws from lower and upper
  bounds.
- Produce mock before/after DisMod outputs for teaching.
- Smooth mock DisMod outputs over continuous age, keeping age-band summaries as
  diagnostic/reporting files only.
- Prepare `pmslt_disease_epi.csv`, the canonical single-year post-DisMod
  disease input.

Canonical PMSLT-ready disease schema:

- Defined separately from raw template schemas in `R/schema.R` via
  `pmslt_ready_input_schemas()` and `pmslt_disease_epi_schema()`.
- File: `pmslt_disease_epi.csv`.
- Required columns:
  `age`, `sex`, `stratum`, `disease`, `time_step`, `incidence_BAU`,
  `prevalence_initial`, `remission_rate`, `excess_mortality_BAU`,
  `case_fatality_BAU`, `disability_weight`.
- Optional provenance/trend columns currently written by
  `prepare_pmslt_disease_inputs()`:
  `prevalence_BAU_reference`, `incidence_apc`, `cfr_apc`,
  `prevalence_apc`, `input_source`.
- `age` is an exact single-year integer age. `age_start`, `age_end`, and
  `age_label` remain valid in raw templates and diagnostic/reporting files, but
  are rejected in `pmslt_disease_epi.csv`.
- `time_step` is the canonical PMSLT disease time column. The package does not
  currently use a separate `year` column in this file.

Workflow distinction:

- Raw disease values are collected in `05_disease_epidemiology_raw.csv` and
  validated with `validate_raw_inputs()`. These raw disease files may remain
  age-banded because real epidemiological inputs are often grouped.
- DisMod-lite files such as `mock_dismod_output_long.csv` and
  `mock_dismod_output_pmslt_ages.csv` are teaching/local diagnostic
  intermediates.
- Downstream PMSLT disease modules consume single-year `pmslt_disease_epi.csv`.

Important output files:

- `dismod_lite_solved_wide.csv`
- `dismod_lite_solved_long.csv`
- `dismod_lite_diagnostics.csv`
- `mock_dismod_output_wide.csv`
- `mock_dismod_output_long.csv`
- `mock_dismod_output_continuous.csv`
- `mock_dismod_output_pmslt_ages.csv`
- `pmslt_disease_epi.csv`

Boundary:

- `dismod_slove()` and `mock_dismod_output()` are not replacements for
  real DisMod-MR. They exist to teach workflow shape and to support local
  package development alongside a separate real DisMod-MR file adapter.

Design rule:

- Downstream PMSLT functions should consume `pmslt_disease_epi.csv`, not the raw
  `05_disease_epidemiology_raw.csv` file.
- Age bands are for input convenience and output reporting, not the canonical
  internal disease simulation state.
- Future main PMSLT engine modules should use exact integer `age` internally.
  Age groups can be reconstructed later for output summaries and presentation.
- Changes to `pmslt_disease_epi.csv` columns should be made in the central
  PMSLT-ready schema first, then reflected in readers, validators, and writers.

## Layer 5a: Real DisMod-MR File Adapter

Files:

- `R/dismod-mr-adapter.R`

Planned public functions:

- `prepare_dismod_mr_inputs()`
- Planned: `read_dismod_mr_outputs()`
- Planned: `validate_dismod_mr_outputs()`
- Planned: `prepare_pmslt_disease_inputs_from_dismod_mr()`

Responsibilities:

- Provide a real DisMod-MR file-format adapter so the package has a vertical
  workflow slice from raw PMSLT templates to external DisMod-MR outputs and then
  to canonical PMSLT-ready disease inputs.
- Prepare one combined long DisMod-MR input evidence file for all diseases,
  sexes, strata, age groups, and parameters.
- Preserve age-banded observations in the DisMod-MR input export; exact
  single-year ages are required after DisMod-MR, not before it.
- Write an explicit exact-age target grid describing the disease parameters the
  package expects DisMod-MR to estimate.
- Read and validate external DisMod-MR output files without trying to run
  DisMod-MR from R.
- Convert validated real DisMod-MR outputs into `pmslt_disease_epi.csv`.

DisMod-MR input export contract:

- `prepare_dismod_mr_inputs()` supports both
  `05_disease_epidemiology_raw.csv` and `06_dismod_input_skeleton.csv`.
- When both files provide the same disease, sex, stratum, age group, and
  parameter, `06_dismod_input_skeleton.csv` takes precedence.
- The main evidence export is a combined long file such as
  `dismod_mr_input_long.csv`.
- Evidence rows preserve the original age grouping with `age_start`, `age_end`,
  and `age_label`.
- Blank or missing parameter values are not exported as evidence observations.
  They are omitted from the evidence file and recorded in an omissions audit.
- The adapter writes companion audit files:
  `dismod_mr_input_omissions.csv`, `dismod_mr_input_summary.csv`, and
  `dismod_mr_target_grid.csv`.
- `dismod_mr_target_grid.csv` uses exact integer single-year `age`, because it
  represents requested predictions rather than observed evidence rows.
- If a `pmslt_spec` is supplied, target-grid ages come from `spec$ages`.
  Otherwise, exact ages are inferred from the union of raw disease input age
  coverage.
- If `spec$ages` requests ages outside observed evidence coverage, the adapter
  should allow the target grid but flag that DisMod-MR extrapolation may be
  required.

DisMod-MR output contract:

- Real DisMod-MR outputs should be read as a generic long parameter table, not
  as a PMSLT-ready wide file.
- Required columns are:
  `age`, `sex`, `stratum`, `disease`, `parameter`, and `mean_value`.
- `age` must be an exact integer single-year age. Age-banded DisMod-MR outputs
  are out of scope for the first adapter slice.
- Required parameter values are:
  `incidence`, `prevalence`, `remission`, `excess_mortality`, and
  `case_fatality`.
- Optional uncertainty columns are `lower_95` and `upper_95`. These should be
  preserved as provenance when present but not used by deterministic PMSLT
  modules until PSA support is built.
- `disability_weight` is not required from DisMod-MR. It remains a PMSLT raw
  input parameter and should be joined from `05_disease_epidemiology_raw.csv`
  during the bridge to `pmslt_disease_epi.csv`.

Bridge rule:

- `prepare_pmslt_disease_inputs_from_dismod_mr()` should map the generic
  DisMod-MR output parameters into the canonical PMSLT-ready columns:
  `incidence` to `incidence_BAU`, `prevalence` to
  `prevalence_initial`, `remission` to `remission_rate`,
  `excess_mortality` to `excess_mortality_BAU`, and `case_fatality` to
  `case_fatality_BAU`.
- The bridge should expand or join raw `disability_weight` values from
  age-banded raw inputs to exact output ages.
- The bridge should validate the resulting `pmslt_disease_epi.csv` with
  `validate_pmslt_disease_inputs()`.

Validation boundary:

- `prepare_dismod_mr_inputs()` should run narrow adapter-specific validation
  rather than requiring the whole raw input folder to pass
  `check_raw_input_readiness()`.
- Adapter validation should check required disease evidence files, identifier
  columns, allowed parameter names, numeric observed values, coherent
  uncertainty bounds when present, and target-grid construction.
- Full raw-input readiness remains a separate PMSLT workflow check before full
  model execution.

## Layer 6: PMSLT Disease Workflow

Files:

- `R/pmslt-workflow.R`

Public functions:

- `read_pmslt_disease_inputs()`
- `validate_pmslt_disease_inputs()`
- `validate_risk_prevalence_inputs()`
- `calculate_pif_from_inputs()`
- `run_pmslt_disease_lifetable()`
- `run_pmslt_interventions()`

Responsibilities:

- Read and validate the canonical post-DisMod disease input.
- Validate that risk-category prevalence distributions sum to 1 before PIF
  calculation.
- Convert risk-factor prevalence plus relative-risk inputs into PIFs.
- Run a narrow disease lifetable module using incidence, prevalence, remission,
  case fatality, and disability weight.
- Apply PIF-mediated effects and direct disease effects.
- Run multiple intervention arms from the same template folder.

Intervention types:

- PIF-only: intervention changes risk-factor prevalence; disease effect is
  calculated from `08_risk_factor_prevalence.csv` and `09_relative_risks.csv`.
- Direct-only: intervention directly changes disease incidence, case fatality,
  or morbidity through `10_direct_intervention_effects.csv`.
- Combined: intervention has both PIF-mediated and direct effects.

Direct-effect formula:

```r
effective_multiplier <- 1 - coverage * (1 - rr)
```

Example:

- `cfr_rr = 0.80`
- `coverage = 0.50`
- effective `cfr_multiplier = 0.90`

That means an average 10 percent reduction in case fatality after accounting for
partial coverage.

Design rule:

- `run_pmslt_interventions()` should be the beginner-facing entry point for
  intervention scenarios. Internal helper names may be more technical, but the
  user-facing function should remain clear.

Internal direct-effect helper:

- `apply_direct_disease_effects()` attaches population-level intervention
  multipliers to the disease input.
- Formula: `effective_multiplier <- 1 - coverage * (1 - rr)`.
- Example: `rr = 0.80` at `coverage = 0.50` becomes an overall multiplier of
  `0.90`.

## Layer 7: Main PMSLT Lifetable

Files:

- `R/main-lifetable.R`

Public functions:

- `initialize_pmslt_lifetable()`
- `run_pmslt_lifetable_bau()`
- `integrate_disease_deltas()`
- `summarise_pmslt_results()`
- `compare_pmslt_results()`
- `calculate_halys()`
- `compare_halys()`

Source template concepts:

- `initialize_main_lifetable()`
- `run_main_lifetable()`
- `aggregate_population_results()`

Responsibilities:

- Read exact single-year population, all-cause mortality, and optional
  all-cause morbidity inputs.
- Initialise one deterministic business-as-usual all-cause lifetable time step.
- Run deterministic multi-cycle business-as-usual all-cause lifetables with
  yearly single-age population ageing.
- Attach deterministic disease-attributable cases, deaths, and YLDs from
  exact-age `pmslt_disease_epi.csv` beside all-cause BAU lifetable rows.
- Summarise BAU all-cause and disease-delta outputs overall or by exact
  `time_step`, `age`, `sex`, `stratum`, `disease`, and reporting-only
  `age_band`.
- Compare compatible intervention outputs against BAU outputs as simple
  `intervention - BAU` reporting deltas overall or by `time_step`, `sex`,
  `stratum`, exact `age`, and reporting-only `age_band`.
- Calculate simple HALY-style summaries from existing `person_years` and `yld`
  outputs, and compare compatible HALY summaries as `intervention - BAU`.
- Run BAU and intervention population lifetables.
- Integrate disease-specific mortality and morbidity deltas from the disease
  module.
- Calculate person-years, deaths, HALYs, DALYs, costs, and stratified
  summaries.

Boundary:

- The current implementation is deliberately narrow. It ages surviving
  population forward under BAU and can attach disease-attributable quantities,
  but does not run interventions, add births, migration, entrants, costs,
  equity, or PSA.
- Disease-attributable deaths are not subtracted from all-cause deaths in the
  current slice. They are attached as adjacent output columns for inspection
  and later integration decisions.
- `run_pmslt_interventions()` remains separate from the main all-cause
  lifetable initialisation path.

Ageing and rate rules:

- `horizon` means the number of yearly cycles. `horizon = 1` returns only
  `time_step = 0` and matches `initialize_pmslt_lifetable()`.
- Ages must be exact consecutive single-year ages within each sex and stratum.
- At the next cycle, population at age `a` equals survivors from age `a - 1`
  in the previous cycle.
- The minimum starting age receives no new entrants.
- The maximum age is currently open-ended: survivors already at the maximum age
  stay there and survivors from the previous age also age into the maximum age.
- If mortality or morbidity inputs include `time_step`, rates are matched by
  `time_step`; otherwise baseline rates are reused every cycle.
- `integrate_disease_deltas()` joins disease inputs by `time_step`, `age`,
  `sex`, and `stratum`. It uses `prevalence_initial` as the prevalence term for
  this first single-year disease-delta slice.
- Disease-specific long output is retained in the `disease_deltas` attribute on
  the returned lifetable.
- `summarise_pmslt_results()` can aggregate exact ages into `age_band` labels
  from `attr(results, "spec")$ages`. This is reporting-only; exact
  single-year age remains the engine state.
- `compare_pmslt_results()` reuses the summary layer and validates that BAU
  and intervention results have matching `time_step`, `age`, `sex`, and
  `stratum` rows before calculating differences.
- Disease-specific long-output contrasts remain later work; this slice only
  compares all-cause metrics and integrated disease-total columns.
- `calculate_halys()` reuses `summarise_pmslt_results()` and reports
  `halys = person_years - yld`, preserving grouping columns and integrated
  disease-total columns when available.
- `compare_halys()` validates compatible BAU and intervention structures, then
  returns HALY, person-years, and YLD differences as `intervention - BAU`.
- HALY reporting does not add discounting, age weighting, DALYs, costs, PSA,
  uncertainty intervals, or engine calculation changes.

## Layer 8: Planned Uncertainty, Costs, and Equity Extensions

Planned modules:

- Cost module consuming `12_costs.csv`.
- PSA module inspired by the old `draw_psa_parameters()` and
  `run_probabilistic_pmslt()`.
- Equity disaggregation module inspired by `disaggregate_mortality()`.

Design rule:

- Deterministic model contracts come first. PSA should sample from stable
  schemas rather than ad hoc generated data frames.

## Tests

Files:

- `tests/testthat/test-spec.R`
- `tests/testthat/test-templates.R`
- `tests/testthat/test-raw-validation.R`
- `tests/testthat/test-pmslt-disease-schema.R`
- `tests/testthat/test-dismod-lite.R`
- `tests/testthat/test-mock-dismod.R`
- `tests/testthat/test-pmslt-workflow.R`
- `tests/testthat/test-main-lifetable.R`

Current coverage:

- Model specification and risk categories.
- Template generation and input guide generation.
- Raw input validation issue-table structure, accumulation, ordering, file,
  column, type, category, missing-value, and bounds checks.
- Canonical `pmslt_disease_epi.csv` schema existence, writer alignment, reader
  acceptance, and validator rejection for missing columns and invalid values.
- Missing parameter diagnostics.
- DisMod-lite age disaggregation and uncertainty propagation.
- Mock DisMod output generation and plots.
- Post-DisMod disease input validation.
- Disease lifetable operation.
- PIF calculation from raw intervention inputs.
- Multi-arm intervention runner with direct effects.
- One-step single-year BAU all-cause lifetable initialisation, including input
  validation, file path inputs, complete joins, and optional morbidity.
- Multi-cycle BAU all-cause lifetable ageing, open-ended maximum-age retention,
  static and time-varying rates, morbidity `yld`, horizon validation, complete
  time-varying joins, and no-new-entrant behaviour.

Validation command:

```r
devtools::test()
```

Package check command:

```sh
R CMD build .
R CMD check pmslttools_*.tar.gz --no-manual --no-build-vignettes
```

## Current Public API

- `age_bands()`
- `calculate_halys()`
- `calculate_pif_from_inputs()`
- `compare_halys()`
- `compare_pmslt_results()`
- `validate_risk_prevalence_inputs()`
- `diagnose_missing_parameters()`
- `draft_input_templates()`
- `generate_mock_pmslt_inputs()`
- `initialize_pmslt_lifetable()`
- `mock_dismod_output()`
- `mock_pmslt_spec()`
- `next_pmslt_step()`
- `plot_dismod_age_curve()`
- `plot_dismod_corrections()`
- `prepare_pmslt_disease_inputs()`
- `predict_dismod_to_age_grid()`
- `read_pmslt_disease_inputs()`
- `run_pmslt_disease_lifetable()`
- `run_pmslt_lifetable_bau()`
- `run_pmslt_interventions()`
- `pmslt_spec()`
- `summarise_pmslt_results()`
- `dismod_slove()`
- `smooth_dismod_age_curve()`
- `validate_pmslt_disease_inputs()`
- `validate_spec()`
- `write_input_template_guide()`

## Architecture Decisions To Preserve

1. Keep raw inputs, DisMod outputs, and PMSLT-ready inputs separate.
2. Treat `pmslt_disease_epi.csv` as the canonical disease input after DisMod.
3. Keep beginner-facing functions clear and workflow-oriented.
4. Support multiple intervention arms at template stage, not as a later
   afterthought.
5. Support direct disease effects separately from PIF-mediated risk-factor
   effects.
6. Keep mock DisMod functions clearly labelled as teaching-only.
7. Prefer explicit CSV schemas and validators over implicit assumptions.
8. Keep documentation close to the template files that students must fill.
