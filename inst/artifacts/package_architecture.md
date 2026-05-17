# pmslttools Package Architecture

Last updated: 2026-05-17

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
solve_dismod_lite("inputs_raw")

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

## Layer 3: Missing Parameter Diagnostics

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

## Layer 4: DisMod-Lite and Mock DisMod Processing

Files:

- `R/dismod-lite.R`
- `R/mock-dismod.R`

Public functions:

- `solve_dismod_lite()`
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
- Expand coarse age observations to the target PMSLT age grid.
- Fill identifiable missing values using simple steady-state illness-death
  equations.
- Optionally propagate uncertainty using Monte Carlo draws from lower and upper
  bounds.
- Produce mock before/after DisMod outputs for teaching.
- Smooth mock DisMod outputs over continuous age and map them back to PMSLT
  age bands.
- Prepare `pmslt_disease_epi.csv`, the canonical post-DisMod disease input.

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

- `solve_dismod_lite()` and `mock_dismod_output()` are not replacements for
  real DisMod-MR. They exist to teach workflow shape and to support local
  package development until a real DisMod adapter is added.

Design rule:

- Downstream PMSLT functions should consume `pmslt_disease_epi.csv`, not the raw
  `05_disease_epidemiology_raw.csv` file.

## Layer 5: PMSLT Disease Workflow

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

## Layer 6: Planned Main PMSLT Lifetable

Files:

- Planned: `R/main-lifetable.R`

Planned public functions:

- `initialize_pmslt_lifetable()`
- `integrate_disease_deltas()`
- `summarise_pmslt_results()`

Source template concepts:

- `initialize_main_lifetable()`
- `run_main_lifetable()`
- `aggregate_population_results()`

Responsibilities:

- Read population, all-cause mortality, all-cause morbidity, and life
  expectancy inputs.
- Run BAU and intervention population lifetables.
- Integrate disease-specific mortality and morbidity deltas from the disease
  module.
- Calculate person-years, deaths, HALYs, DALYs, costs, and stratified
  summaries.

Boundary:

- This layer should be added only after raw schemas and post-DisMod disease
  inputs remain stable.

## Layer 7: Planned Uncertainty, Costs, and Equity Extensions

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
- `tests/testthat/test-dismod-lite.R`
- `tests/testthat/test-mock-dismod.R`
- `tests/testthat/test-pmslt-workflow.R`

Current coverage:

- Model specification and risk categories.
- Template generation and input guide generation.
- Missing parameter diagnostics.
- DisMod-lite age disaggregation and uncertainty propagation.
- Mock DisMod output generation and plots.
- Post-DisMod disease input validation.
- Disease lifetable operation.
- PIF calculation from raw intervention inputs.
- Multi-arm intervention runner with direct effects.

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
- `calculate_pif_from_inputs()`
- `validate_risk_prevalence_inputs()`
- `diagnose_missing_parameters()`
- `draft_input_templates()`
- `generate_mock_pmslt_inputs()`
- `mock_dismod_output()`
- `mock_pmslt_spec()`
- `plot_dismod_age_curve()`
- `plot_dismod_corrections()`
- `prepare_pmslt_disease_inputs()`
- `predict_dismod_to_age_grid()`
- `read_pmslt_disease_inputs()`
- `run_pmslt_disease_lifetable()`
- `run_pmslt_interventions()`
- `pmslt_spec()`
- `solve_dismod_lite()`
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
9. Port from `PMSLT_Template_v1.R` in small tested slices with artifact updates
   at each step.
