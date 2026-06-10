# pmslttools

`pmslttools` is an early-stage R package for guiding proportional multistate
lifetable (PMSLT) simulation modelling projects.

The package starts before modelling. It helps a beginner define the intended
model, generate project-specific input templates, identify which parameters are
needed, and prepare a clear path toward disease consistency solving and PMSLT
simulation.

## Current scope

This first scaffold includes:

- `pmslt_spec()` to define a model from minimal information.
- `next_pmslt_step()` to ask what to do next in the workflow.
- `age_bands()` to create standard age-group definitions.
- `draft_input_templates()` to generate beginner-friendly CSV templates.
- `validate_raw_inputs()` to check completed raw CSV templates before disease
  consistency solving.
- `check_raw_input_readiness()` to validate and summarise raw input readiness
  in one beginner-facing step.
- `validate_spec()` and `diagnose_missing_parameters()` to explain modelling
  requirements before data collection.
- `solve_disease_consistency()` to turn checked raw disease inputs into the
  canonical exact-age `pmslt_disease_epi.csv` file. `solver = "disbayes"` is
  the default real consistency-solver bridge when the optional `disbayes`
  package and its Stan backend are installed. `solver = "dismod_slove"` remains
  available for deterministic workflows that run without optional solver
  infrastructure.
- `dismod_slove()` to read an `input_raw` directory, disaggregate coarse
  disease age groups to exact single-year ages, and fill missing disease
  parameters where simple illness-death consistency equations are identifiable.
  It can optionally propagate uncertainty from `lower_95` and `upper_95`
  columns by Monte Carlo sampling.
- `initialize_pmslt_lifetable()` to create a one-step, single-year,
  business-as-usual all-cause lifetable from population, mortality, and
  optional morbidity inputs.
- `run_pmslt_lifetable_bau()` to run the deterministic BAU all-cause lifetable
  for multiple yearly cycles with single-year population ageing.
- `integrate_disease_deltas()` to attach deterministic disease-attributable
  cases, deaths, and YLDs beside BAU all-cause lifetable rows.
- `summarise_pmslt_results()` to inspect BAU all-cause and disease-delta
  outputs overall or by exact `time_step`, `age`, `sex`, `stratum`, and
  `disease`, or by the reporting `age_band` labels stored in `pmslt_spec()`.
- `compare_pmslt_results()` to compare compatible intervention PMSLT outputs
  against BAU outputs as simple `intervention - BAU` reporting deltas.
- `calculate_halys()` and `compare_halys()` to report simple HALY-style
  summaries as `person_years - yld`, overall or by the same reporting groups.
- `summarise_costs()`, `compare_costs()`, and `calculate_icers()` to summarise
  deterministic costs, report `intervention - BAU` cost deltas, and calculate
  ICERs only after incremental costs and incremental HALYs are both available.

Full simulation engine functions will be migrated from the existing PMSLT
template in later modules.

## Active beginner workflow

```r
library(pmslttools)

spec <- pmslt_spec(
  intervention = "Tobacco tax",
  intervention_arms = c("Tax only", "Tax plus acute care"),
  mechanism = "both",
  diseases = c("CHD", "Stroke"),
  risk_factors = "Smoking",
  risk_categories = list(Smoking = c("Never", "Current", "Former")),
  ages = age_bands(20, 100, by = 5),
  sexes = c("male", "female"),
  strata = "total",
  horizon = 80
)

draft_input_templates(spec, output_dir = "inputs_raw")

# After filling the generated CSV files, validate them before modelling.
readiness <- check_raw_input_readiness("inputs_raw", spec)
readiness$can_proceed
readiness$issues

# If readiness$can_proceed is TRUE, create the canonical disease input.
solve_disease_consistency("inputs_raw")

# Use the disease-consistency output in intervention workflows.
results <- run_pmslt_interventions(
  disease_epi = "inputs_raw/disease_consistency_results/pmslt_disease_epi.csv",
  risk_prevalence = "inputs_raw/08_risk_factor_prevalence.csv",
  relative_risks = "inputs_raw/09_relative_risks.csv",
  direct_effects = "inputs_raw/10_direct_intervention_effects.csv"
)

# The all-cause lifetable starter currently expects exact-age data.
population <- data.frame(
  age = c(40L, 41L),
  sex = "female",
  stratum = "total",
  population = c(1000, 900)
)

mortality <- data.frame(
  age = c(40L, 41L),
  sex = "female",
  stratum = "total",
  mortality_rate = c(0.01, 0.02)
)

morbidity <- data.frame(
  age = c(40L, 41L),
  sex = "female",
  stratum = "total",
  yld_rate = c(0.04, 0.05)
)

bau <- run_pmslt_lifetable_bau(
  population,
  mortality,
  morbidity,
  horizon = 2,
  spec = spec
)

summarise_pmslt_results(bau)
summarise_pmslt_results(bau, by = "age_band")
calculate_halys(bau, by = "age_band")
```

This creates the CSV templates and a `README_inputs_raw.md` guide inside the
output folder. The guide explains every file and every blank column that the
student needs to fill before disease consistency solving. The output also includes
`00_column_dictionary.csv`, which marks columns as generated, required,
conditional, or optional. After filling the templates, run
`check_raw_input_readiness()` for a one-step can-proceed signal, next-step
guidance, and access to the full issue table before moving on to disease
consistency solving.
For lower-level control, use `validate_raw_inputs()` to get the issue table and
`summarise_raw_input_issues()` to summarise it.

`05_disease_epidemiology_raw.csv` includes both `excess_mortality_rate` and
`disease_mortality_rate`. These are deliberately separate: excess mortality is
the additional mortality among people with disease, while disease mortality is
explicit disease-specific mortality evidence used by consistency solvers. The
long `06_dismod_input_skeleton.csv` uses `parameter = "mortality"` for that
disease-specific mortality evidence.

With `solver = "disbayes"`, the bridge fits one model per disease, sex, and
stratum, then maps disbayes `inc`, `rem`, `cf`, and `prev_prob` estimates back
to `incidence_BAU`, `remission_rate`, `case_fatality_BAU`, and
`prevalence_initial`. It writes `pmslt_disease_epi.csv`,
`disbayes_solver_long.csv`, `disbayes_fit_summary.csv`,
`disbayes_rate_conversion_audit.csv`, `disbayes_evidence_audit.csv`, and
`disbayes_group_diagnostics.csv`. The optional package is deliberately not a
hard dependency; install and configure `disbayes` separately, or choose
`solver = "dismod_slove"`.

The current all-cause lifetable helpers do not apply intervention effects,
costs, discounting, age weighting, PSA, births, migration, or entrants.
Intervention disease modules and BAU all-cause lifetable helpers are separate
implemented pieces until the later full main PMSLT engine is built.

## What do I do next?

```r
next_pmslt_step()
next_pmslt_step("raw_inputs")
next_pmslt_step("disease_consistency")
next_pmslt_step("interventions")
next_pmslt_step("lifetable")
next_pmslt_step("summaries")

readiness <- check_raw_input_readiness(input_dir, spec)
next_pmslt_step(object = readiness)
```

## Lower-level disease consistency options

`solve_disease_consistency()` is the beginner-facing function for writing
`pmslt_disease_epi.csv`. The default solver is `solver = "disbayes"` when the
optional solver stack is installed. Users who need lower-level deterministic
solver diagnostics can call `dismod_slove()` directly, or set
`solver = "dismod_slove"` in the high-level workflow.

```r
solve_disease_consistency(
  "inputs_raw",
  solver = "dismod_slove",
  output_dir = "inputs_raw/disease_consistency_uncertainty",
  uncertainty = TRUE,
  draws = 2000,
  seed = 1
)
```

`mock_dismod_output()` remains available for demonstration and test-data
generation only. It is not a solver option for `solve_disease_consistency()`.

## Conceptual mock DisMod demonstration

```r
generate_mock_pmslt_inputs("mock_inputs_raw")
mock_dismod_output("mock_inputs_raw")
plot_dismod_corrections("mock_inputs_raw/mock_dismod_output")
plot_dismod_age_curve("mock_inputs_raw/mock_dismod_output")
```

This creates mock raw inputs, a teaching-only mock DisMod output, and a PNG plot
comparing raw epidemiological parameters with corrected values. It also creates
single-year continuous-age predictions, PMSLT age-band diagnostic summaries,
and the canonical single-year disease input:

- `mock_dismod_output_continuous.csv`
- `mock_dismod_output_pmslt_ages.csv` for diagnostic/reporting summaries
- `pmslt_disease_epi.csv` with exact integer `age`
- `dismod_continuous_age_curve.png`

It is for learning the workflow shape only, not a disease consistency solver.

## Conceptual disease module example

After disease consistency solving, use `pmslt_disease_epi.csv` as the disease
input:

```r
disease_epi <- read_pmslt_disease_inputs(
  "mock_inputs_raw/mock_dismod_output/pmslt_disease_epi.csv"
)

disease_deltas <- run_pmslt_disease_lifetable(disease_epi)
```

The package treats this post-DisMod file as the canonical disease input for
subsequent PMSLT modules. Raw disease inputs may be age-banded and are retained
as an audit trail, not as the direct model input. `pmslt_disease_epi.csv` is
single-year: it uses an exact integer `age` column and does not use
`age_start`, `age_end`, or `age_label`. Future PMSLT engine modules should use
exact integer age internally; age groups can be rebuilt later for output
reporting summaries.

## BAU all-cause lifetable starter

```r
population <- data.frame(
  age = c(40L, 41L),
  sex = "female",
  stratum = "total",
  population = c(1000, 900)
)

mortality <- data.frame(
  age = c(40L, 41L),
  sex = "female",
  stratum = "total",
  mortality_rate = c(0.01, 0.02)
)

lifetable <- initialize_pmslt_lifetable(population, mortality)
summary_spec <- pmslt_spec(
  intervention = "Reporting example",
  mechanism = "direct",
  diseases = "CHD",
  ages = age_bands(40, 45, by = 3, open_ended = FALSE),
  sexes = "female",
  strata = "total",
  horizon = 1
)
bau <- run_pmslt_lifetable_bau(population, mortality, horizon = 1, spec = summary_spec)
disease_attached <- integrate_disease_deltas(bau, disease_epi)
summarise_pmslt_results(disease_attached)
summarise_pmslt_results(disease_attached, by = c("disease", "age"))
summarise_pmslt_results(disease_attached, by = c("disease", "age_band"))

intervention_attached <- disease_attached
intervention_attached$population <- intervention_attached$population * 0.99
compare_pmslt_results(disease_attached, intervention_attached)
compare_pmslt_results(disease_attached, intervention_attached, by = "age_band")
calculate_halys(disease_attached)
calculate_halys(disease_attached, by = "age_band")
incremental_halys <- compare_halys(disease_attached, intervention_attached)

bau_costs <- disease_attached
bau_costs$total_cost <- bau_costs$person_years * 100
intervention_costs <- bau_costs
intervention_costs$total_cost <- intervention_costs$total_cost + 500
incremental_costs <- compare_costs(bau_costs, intervention_costs)
calculate_icers(
  cbind(incremental_costs, haly_difference = incremental_halys$haly_difference)
)
```

`initialize_pmslt_lifetable()` runs one deterministic BAU time step.
`run_pmslt_lifetable_bau()` runs multiple yearly BAU cycles. If mortality or
morbidity inputs include `time_step`, rates are matched by `time_step`;
otherwise baseline rates are reused every cycle. Survivors age forward by one
year each cycle. The minimum starting age receives no new entrants, and the
maximum age is treated as open-ended for now.
`integrate_disease_deltas()` joins exact-age `pmslt_disease_epi.csv` rows to
BAU lifetable rows and attaches `total_disease_cases`,
`total_disease_deaths`, and `total_disease_yld`. Disease-specific long rows are
kept in the `disease_deltas` attribute.
`summarise_pmslt_results()` returns plain data-frame summaries for all-cause
lifetable metrics and, when disease deltas are attached, disease-attributable
metrics. Disease-specific summaries use the `disease_deltas` attribute.
Age-band summaries use the age labels in `spec$ages`, so run the lifetable with
`spec = pmslt_spec(..., ages = age_bands(...))` when you need grouped age
reporting.
`compare_pmslt_results()` reuses these summaries to report
`population_difference`, `deaths_difference`, `person_years_difference`,
`yld_difference` when available, and integrated disease-total differences when
both inputs include disease totals. Both inputs must have matching
`time_step`, `age`, `sex`, and `stratum` rows.
`calculate_halys()` reports `halys = person_years - yld` from existing PMSLT
outputs and keeps integrated disease-total columns when they are available.
`compare_halys()` compares compatible outputs as `intervention - BAU`, returning
`haly_difference`, `person_years_difference`, and `yld_difference`.
`summarise_costs()` and `compare_costs()` use the same common reporting groups
for deterministic cost outputs with `cost`, `costs`, `total_cost`, or columns
ending in `_cost` or `_costs`. `calculate_icers()` requires an incremental cost
column and an incremental HALY column in the same table; it reports ICER values
only for positive incremental HALYs and labels zero or negative incremental
HALYs explicitly.

These all-cause lifetable functions do not apply interventions, PIFs, direct
effects, costs, discounting, age weighting, PSA, births, migration, or entrants
yet. Disease-attributable deaths are attached beside all-cause deaths; they are
not subtracted from the all-cause lifetable in this slice.

## Intervention workflow details

For risk-factor interventions, `calculate_pif_from_inputs()` converts
`08_risk_factor_prevalence.csv` and `09_relative_risks.csv` into the PIF table
used by the disease lifetable. It first checks that risk-category prevalences
sum to 1 within each age, sex, stratum, time step, risk factor, and intervention
arm. For interventions that directly change disease incidence, case fatality, or
morbidity, fill `10_direct_intervention_effects.csv`. Multiple intervention
arms can live in the same template folder:

```r
results <- run_pmslt_interventions(
  disease_epi = "inputs_raw/disease_consistency_results/pmslt_disease_epi.csv",
  risk_prevalence = "inputs_raw/08_risk_factor_prevalence.csv",
  relative_risks = "inputs_raw/09_relative_risks.csv",
  direct_effects = "inputs_raw/10_direct_intervention_effects.csv"
)
```

This supports PIF-only, direct-only, and combined intervention scenarios.
