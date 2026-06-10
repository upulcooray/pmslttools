# pmslttools Package Architecture

Last updated: 2026-05-30

## Package Aim

`pmslttools` is being built as a beginner-friendly R package for planning,
structuring, and running proportional multistate lifetable (PMSLT) simulation
projects. The package should guide a new modeller from a small model
specification to project-specific input templates, disease consistency solver
workflows, intervention modelling, and eventually full PMSLT population
outputs.

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
readiness <- check_raw_input_readiness("inputs_raw", spec)
solve_disease_consistency("inputs_raw")

disease_epi <- read_pmslt_disease_inputs(
  "inputs_raw/disease_consistency_results/pmslt_disease_epi.csv"
)

results <- run_pmslt_interventions(
  disease_epi = disease_epi,
  risk_prevalence = "inputs_raw/08_risk_factor_prevalence.csv",
  relative_risks = "inputs_raw/09_relative_risks.csv",
  direct_effects = "inputs_raw/10_direct_intervention_effects.csv"
)
```

## Disease Consistency Solver Refactor

Decision record from the 2026-05-25 grill-me design session:

- Add a beginner-facing high-level solver function,
  `solve_disease_consistency(input_dir, solver = ...)`, so the main workflow
  has one obvious step from checked raw disease inputs to
  `pmslt_disease_epi.csv`.
- Keep lower-level solver functions available. `dismod_slove()` remains a
  valid package-native deterministic modelling option, not only a teaching
  helper. `mock_dismod_output()` remains demo/test-data generation only and
  should not become a `solve_disease_consistency()` solver choice.
- Make `disbayes` the planned primary real consistency solver once its adapter
  and execution path are implemented and tested. Keep `disbayes` optional in
  `Suggests` because it brings Stan/RStan setup requirements.
- During the staged implementation, default
  `solve_disease_consistency()` to `solver = "dismod_slove"` until the
  `disbayes` execution path works. After that, switch the default to
  `solver = "disbayes"` while keeping `solver = "dismod_slove"` explicit.
- Hard remove the external DisMod-MR adapter in this refactor rather than
  soft-deprecating it. Slice 1 removed its source files, exports, tests, man
  pages, and beginner-facing README path from the active package API.
- Reuse the existing raw template workflow. Do not add a separate
  disbayes-native user template. The package should translate raw PMSLT
  disease inputs into solver-specific inputs.
- Add explicit disease mortality evidence. `05_disease_epidemiology_raw.csv`
  now includes a wide `disease_mortality_rate` column. The long
  `06_dismod_input_skeleton.csv` now allows `parameter = "mortality"`.
  Do not silently reinterpret `excess_mortality_rate` as disease mortality.
- Keep the filename `06_dismod_input_skeleton.csv` for now, but redefine it as
  generic long-format disease-consistency solver evidence for `disbayes` and
  `dismod_slove`.
- Keep uncertainty metadata only in `06_dismod_input_skeleton.csv` for the
  first disbayes slice. `05_disease_epidemiology_raw.csv` stays
  point-estimate oriented and readable.
- Keep canonical `pmslt_disease_epi.csv` rate-based and explicit. Rate-to-
  probability conversion happens only inside the disbayes adapter using
  `1 - exp(-rate)`, and an audit table should record source values and
  converted probabilities.
- Map disbayes outputs back to canonical PMSLT columns explicitly:
  `inc` to `incidence_BAU`, `rem` to `remission_rate`, `cf` to
  `case_fatality_BAU`, and `prev_prob` to `prevalence_initial`.
  Do not automatically copy `cf` into `excess_mortality_BAU`. Carry raw
  `excess_mortality_rate` through when supplied; otherwise leave
  `excess_mortality_BAU` missing with provenance.
- Fit the first disbayes implementation independently by
  `disease + sex + stratum`. Hierarchical or pooled disbayes models can be a
  later explicit mode, not the first implementation.
- For disbayes, require mortality plus at least one of incidence or prevalence
  for each group. If evidence is insufficient, stop with structured
  diagnostics and let the user choose another solver or fill more evidence. Do
  not silently fall back.
- Internally fit disbayes on a complete single-year age grid from
  `0:max(target_age)`, because disbayes requires age to start at zero. Subset
  final `pmslt_disease_epi.csv` back to the PMSLT target ages.
- Expand age-banded raw evidence to exact single-year ages using an explicit
  constant-within-band rule in the first slice, with audit fields such as
  `source_age_start`, `source_age_end`, and
  `age_source = exact | expanded_constant | padded_missing`.
- By default, disbayes evidence should include usable uncertainty
  (`lower_95`/`upper_95` or `sample_size`) in the long skeleton. Point-estimate
  only evidence should use `dismod_slove()` unless the user explicitly enables
  default uncertainty.
- In Slice 1, `solve_disease_consistency(solver = "dismod_slove")` writes
  canonical `pmslt_disease_epi.csv` plus existing deterministic solver
  diagnostics. The `disbayes` branch intentionally stops before fitting until
  the later adapter and execution slices are implemented.

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
- Planned refactor note: disbayes readiness will use a stricter solver-specific
  rule: explicit mortality plus at least one of incidence or prevalence. The
  current three-parameter diagnostic should be updated or wrapped when the
  solver refactor reaches the disbayes adapter slice.

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

- `dismod_slove()` is a valid package-native deterministic disease-consistency
  solver and diagnostic helper.
- `mock_dismod_output()` is teaching and test-data generation only. It should
  not be presented as actual modelling.
- The planned solver refactor makes `disbayes` the primary real consistency
  solver while preserving `dismod_slove()` as an explicit modelling option.

Design rule:

- Downstream PMSLT functions should consume `pmslt_disease_epi.csv`, not the raw
  `05_disease_epidemiology_raw.csv` file.
- Age bands are for input convenience and output reporting, not the canonical
  internal disease simulation state.
- Future main PMSLT engine modules should use exact integer `age` internally.
  Age groups can be reconstructed later for output summaries and presentation.
- Changes to `pmslt_disease_epi.csv` columns should be made in the central
  PMSLT-ready schema first, then reflected in readers, validators, and writers.

## Layer 5a: Disease Consistency Solver Wrapper

Status:

- Slice 1 implemented on 2026-05-25.
- The external DisMod-MR adapter has been removed from the active API.

Files:

- `R/disease-consistency.R`
- `R/dismod-lite.R`
- `R/templates.R`
- `R/schema.R`

Public functions:

- `solve_disease_consistency()`
- `dismod_slove()`

Responsibilities:

- Provide the beginner-facing bridge from checked raw disease inputs to
  canonical `pmslt_disease_epi.csv`.
- Keep `dismod_slove()` available as a deterministic package-native solver and
  diagnostic helper.
- Keep `mock_dismod_output()` outside the solver choices; it remains
  demonstration/test-data generation only.
- Reserve `solver = "disbayes"` for the later real consistency solver. In this
  slice it stops with a plain not-yet-implemented message and does not add Stan
  or RStan dependencies.
- Keep explicit disease mortality evidence separate from excess mortality:
  `disease_mortality_rate` in `05_disease_epidemiology_raw.csv` maps to
  `parameter = "mortality"` evidence in `06_dismod_input_skeleton.csv`;
  `excess_mortality_rate` remains excess mortality among people with disease.

Current output contract:

- `solve_disease_consistency(input_dir, solver = "dismod_slove")` writes:
  - `dismod_lite_solved_wide.csv`
  - `dismod_lite_solved_long.csv`
  - `dismod_lite_diagnostics.csv`
  - `pmslt_disease_epi.csv`
- `pmslt_disease_epi.csv` remains exact-age, rate-based, and validated by
  `validate_pmslt_disease_inputs()`.
- `06_dismod_input_skeleton.csv` remains the filename for long solver evidence,
  but its active meaning is generic disease-consistency solver evidence rather
  than an external DisMod-MR file contract.

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

## Builder Architecture Pacts

These pacts define manageable implementation slices for builder agents. Each
builder should complete one pact at a time, update tests and documentation for
that pact, and avoid changing contracts owned by other pacts unless the
architecture document is updated first.

Common rules for all pacts:

- Preserve the workflow boundary:
  raw inputs -> disease consistency solver outputs -> `pmslt_disease_epi.csv`
  -> intervention and lifetable workflows.
- Prefer base R and explicit CSV schemas.
- Keep beginner-facing functions workflow-oriented with plain-language errors.
- Add or update tests in `tests/testthat/` for every public behaviour change.
- Run `devtools::test()` before handoff; run `R CMD check` when public API,
  documentation, optional dependencies, or package metadata change.
- Update `inst/artifacts/implementation_log.md` and this architecture file when
  a pact changes a durable package decision.

### Pact 1: Disbayes Adapter Preparation

Owner scope:

- Build internal, testable preparation code for `solver = "disbayes"` without
  running Stan, RStan, or `disbayes`.

Primary files:

- `R/disease-consistency.R`
- `R/schema.R`
- `R/dismod-lite.R` only if reusable age-expansion helpers are needed
- `tests/testthat/test-dismod-lite.R` or a new
  `tests/testthat/test-disease-consistency.R`

Deliverables:

- Convert `05_disease_epidemiology_raw.csv` and
  `06_dismod_input_skeleton.csv` into a disbayes-ready internal evidence table.
- Expand age-banded evidence to exact single-year ages using the documented
  constant-within-band rule.
- Pad internal fit ages to `0:max(target_age)` and mark padded rows.
- Convert rates to annual probabilities using `1 - exp(-rate)` only inside the
  adapter.
- Produce structured diagnostics and audit tables for age expansion, rate
  conversion, missing evidence, and insufficient uncertainty.
- Require mortality plus at least one of incidence or prevalence for every
  `disease + sex + stratum` group.
- Require usable uncertainty by default from `lower_95`/`upper_95` or
  `sample_size` in `06_dismod_input_skeleton.csv`.

Boundaries:

- Do not add `disbayes`, Stan, or RStan execution.
- Do not switch the default solver away from `dismod_slove`.
- Do not change the canonical `pmslt_disease_epi.csv` schema.
- Do not silently reinterpret `excess_mortality_rate` as disease mortality.

Acceptance criteria:

- Adapter preparation can be unit tested without optional dependencies.
- Under-specified evidence returns beginner-readable diagnostics identifying
  the affected disease, sex, stratum, missing parameter class, and suggested
  fix.
- Audit outputs distinguish exact, expanded, and padded ages.
- Point-estimate-only evidence tells users to use `solver = "dismod_slove"` or
  provide uncertainty, unless an explicit future option says otherwise.

Handoff:

- `solve_disease_consistency(solver = "disbayes")` may still stop before
  fitting, but should stop after returning or writing useful preparation
  diagnostics.

### Pact 2: Disbayes Execution Bridge

Owner scope:

- Run `disbayes` as the primary real disease consistency solver and map fitted
  outputs back to PMSLT-ready disease inputs.

Primary files:

- `R/disease-consistency.R`
- `R/schema.R`
- `DESCRIPTION`
- `NAMESPACE`
- `README.md`
- `tests/testthat/test-disease-consistency.R`

Deliverables:

- Add optional dependency checks for `disbayes` with clear setup messages.
- Fit one model per `disease + sex + stratum`.
- Tidy disbayes outputs and map:
  - `inc` to `incidence_BAU`
  - `rem` to `remission_rate`
  - `cf` to `case_fatality_BAU`
  - `prev_prob` to `prevalence_initial`
- Carry explicit raw `excess_mortality_rate` into
  `excess_mortality_BAU` when available; otherwise leave it missing with
  provenance.
- Join `disability_weight` from raw disease inputs.
- Write canonical `pmslt_disease_epi.csv`, fit summaries, long solver outputs,
  and audit files.
- After validation, switch the high-level default to `solver = "disbayes"`
  while preserving `solver = "dismod_slove"`.

Boundaries:

- Keep `disbayes` optional in `Suggests`.
- The package must still install, load, validate templates, and run
  `dismod_slove` workflows without `disbayes` installed.
- Do not make `mock_dismod_output()` a solver choice.
- Do not expose raw disbayes-native templates to beginners.

Acceptance criteria:

- Tests skip execution cleanly when `disbayes` is unavailable.
- Non-disbayes tests pass without optional solver infrastructure.
- The written `pmslt_disease_epi.csv` is exact-age, rate-based, and accepted by
  `validate_pmslt_disease_inputs()`.
- README and workflow navigation identify the new default path clearly.

Handoff:

- Builders working on PMSLT engines can treat `pmslt_disease_epi.csv` as stable
  and solver-independent.

### Pact 3: Intervention-To-Main-Lifetable Bridge

Owner scope:

- Connect intervention disease effects to the main all-cause lifetable without
  adding costs, equity, or PSA.

Primary files:

- `R/pmslt-workflow.R`
- `R/main-lifetable.R`
- `R/workflow-navigation.R`
- `tests/testthat/test-pmslt-workflow.R`
- `tests/testthat/test-main-lifetable.R`

Deliverables:

- Define a beginner-facing path from `run_pmslt_interventions()` outputs into a
  main PMSLT lifetable result.
- Decide and document the first deterministic rule for applying disease
  mortality and morbidity deltas to all-cause outcomes.
- Keep PIF-mediated effects and direct disease effects separate until their
  combined disease-input handoff is explicit.
- Preserve disease-specific long output for audit and summary.

Boundaries:

- Do not add cost, ICER, equity, PSA, discounting, or age weighting logic.
- Do not change raw input template schemas unless the bridge proves an
  essential missing field.
- Do not let disease modules consume raw `05_disease_epidemiology_raw.csv`.

Acceptance criteria:

- A toy model can run from canonical disease inputs and intervention inputs to
  comparable BAU and intervention lifetable outputs.
- Tests cover multi-arm interventions and direct-only, PIF-only, and combined
  mechanisms where relevant.
- Output comparison remains explicit about `intervention - BAU` direction.

Handoff:

- Cost and ICER builders can consume stable BAU and intervention lifetable
  summaries.

### Pact 4: Cost Module And Economic Summaries

Owner scope:

- Turn `12_costs.csv` into deterministic cost outputs and simple economic
  summaries after the deterministic intervention bridge is stable.

Primary files:

- `R/schema.R`
- `R/templates.R`
- `R/input-guide.R`
- `R/main-lifetable.R` or a new `R/costs.R`
- `tests/testthat/test-costs.R`

Deliverables:

- Validate disease costs, background costs, currency, price year, and source
  fields using central schema metadata.
- Attach disease and background costs to compatible exact-age lifetable rows.
- Produce total costs by time step, sex, stratum, disease where relevant, and
  overall.
- Add simple incremental cost summaries for intervention versus BAU.

Boundaries:

- Do not add discounting or ICER thresholds in the first cost slice unless a
  separate architecture decision defines them.
- Do not mix one-off intervention costs with annual disease-management costs
  without explicit fields and documentation.
- Do not add PSA sampling in the deterministic cost pact.

Acceptance criteria:

- Cost outputs are reproducible from `12_costs.csv` and deterministic
  lifetable results.
- Missing or inconsistent cost fields produce issue-table style diagnostics.
- Existing non-cost workflows still run when `cost_effectiveness = FALSE`.

Handoff:

- ICER/reporting builders can use deterministic total and incremental cost
  outputs.

### Pact 5: Equity And Stratum Rate-Ratio Module

Owner scope:

- Connect `11_stratum_rate_ratios.csv` to explicit stratum-specific mortality,
  morbidity, or disease-rate disaggregation.

Primary files:

- `R/schema.R`
- `R/raw-validation.R`
- `R/main-lifetable.R` or a new `R/equity.R`
- `tests/testthat/test-equity.R`

Deliverables:

- Define which aggregate rates can be disaggregated and which rate-ratio
  columns apply to each target.
- Validate rate-ratio completeness across sex, stratum, age, and parameter.
- Apply disaggregation before main lifetable execution, with audit columns
  showing original aggregate values and applied ratios.

Boundaries:

- Do not invent population strata outside `pmslt_spec(strata = ...)`.
- Do not mix equity disaggregation with intervention effect estimation.
- Do not add distributional cost-effectiveness metrics in this pact.

Acceptance criteria:

- Disaggregated inputs remain compatible with existing exact-age engine
  requirements.
- Tests cover complete, missing, and invalid rate-ratio cases.
- Outputs retain enough provenance for users to see how aggregate rates were
  converted.

Handoff:

- Deterministic and economic summaries can group by stratum without needing to
  know the disaggregation internals.

### Pact 6: Aggregation, ICER, And Reporting Layer

Owner scope:

- Provide stable deterministic summaries after BAU, intervention, HALY, and
  cost outputs are available.

Primary files:

- `R/main-lifetable.R` or a new `R/reporting.R`
- `R/workflow-navigation.R`
- `README.md`
- `tests/testthat/test-reporting.R`

Deliverables:

- Summarise deaths, person-years, YLDs, HALYs, disease quantities, and costs by
  common reporting groups.
- Add incremental summaries with a consistent `intervention - BAU` convention.
- Add ICER calculation only when both incremental costs and incremental HALYs
  are present.
- Keep exact-age state internal while supporting reporting-only age bands.

Boundaries:

- Do not add probabilistic intervals.
- Do not define policy thresholds or decision rules.
- Do not change engine calculations in the reporting layer.

Acceptance criteria:

- Summary functions reject incompatible BAU/intervention structures clearly.
- ICER outputs handle zero or negative incremental HALYs explicitly.
- Tests cover overall and stratified summaries.

Handoff:

- PSA builders can reuse deterministic summary functions for each draw.

### Pact 7: Probabilistic Sensitivity Analysis

Owner scope:

- Add PSA only after deterministic schemas, disease consistency, lifetable,
  intervention, cost, and reporting contracts are stable.

Primary files:

- New `R/psa.R`
- `R/schema.R`
- `tests/testthat/test-psa.R`

Deliverables:

- Define a parameter-draw schema before writing samplers.
- Sample from stable raw, solver, disease, cost, and intervention uncertainty
  fields.
- Run deterministic workflow functions repeatedly without changing their
  contracts.
- Return draw-level outputs plus summarised uncertainty intervals.

Boundaries:

- Do not sample from ad hoc data frames that bypass schemas.
- Do not make deterministic functions depend on PSA internals.
- Do not require optional Bayesian solver dependencies for non-solver PSA
  components.

Acceptance criteria:

- PSA results are reproducible with a seed.
- Draw failures are reported by draw and parameter group without hiding
  deterministic errors.
- Deterministic tests remain independent from PSA tests.

Handoff:

- Reporting can add uncertainty intervals without changing deterministic
  summary semantics.

### Pact 8: Workflow Hardening And Release Readiness

Owner scope:

- Keep the package coherent for beginner users as the modelling layers expand.

Primary files:

- `README.md`
- `CODEX.md`
- `R/workflow-navigation.R`
- `inst/artifacts/todo_plan.md`
- `inst/artifacts/implementation_log.md`
- `tests/testthat/test-workflow-navigation.R`

Deliverables:

- Keep `next_pmslt_step()` aligned with implemented workflow stages.
- Ensure examples move through the intended path:
  `pmslt_spec()` -> templates -> raw validation -> disease consistency ->
  interventions -> lifetable -> summaries.
- Remove obsolete API references when pacts replace earlier paths.
- Keep public API documentation and architecture decisions consistent.

Boundaries:

- Do not use workflow hardening as a place to smuggle modelling changes.
- Do not recommend planned functions as if they are implemented.

Acceptance criteria:

- README examples run or are explicitly marked as conceptual.
- `devtools::test()` passes.
- `R CMD check` is clean enough for the current development stage.
- Architecture, todo plan, implementation log, and public documentation do not
  contradict each other on the beginner workflow.

Handoff:

- New builder agents can read the architecture pacts, choose the next planned
  pact, and work without re-litigating stable package boundaries.

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
- `solve_disease_consistency()`
- `dismod_slove()`
- `smooth_dismod_age_curve()`
- `validate_pmslt_disease_inputs()`
- `validate_spec()`
- `write_input_template_guide()`

## Architecture Decisions To Preserve

1. Keep raw inputs, disease consistency solver outputs, and PMSLT-ready inputs
   separate.
2. Treat `pmslt_disease_epi.csv` as the canonical disease input after solver
   processing.
3. Keep beginner-facing functions clear and workflow-oriented.
4. Support multiple intervention arms at template stage, not as a later
   afterthought.
5. Support direct disease effects separately from PIF-mediated risk-factor
   effects.
6. Keep mock DisMod functions clearly labelled as teaching-only.
7. Prefer explicit CSV schemas and validators over implicit assumptions.
8. Keep documentation close to the template files that students must fill.
9. Keep `dismod_slove()` as an explicit deterministic modelling option while
   making `disbayes` the planned primary real consistency solver.
10. Do not silently reinterpret `excess_mortality_rate` as disease mortality.
    Disease mortality evidence must be explicit.
11. Keep canonical PMSLT disease inputs rate-based; solver-specific probability
    conversions belong inside adapters and audit files.
