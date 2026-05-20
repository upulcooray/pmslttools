# pmslttools

`pmslttools` is an early-stage R package for guiding proportional multistate
lifetable (PMSLT) simulation modelling projects.

The package starts before modelling. It helps a beginner define the intended
model, generate project-specific input templates, identify which parameters are
needed, and prepare a clear path toward DisMod processing and PMSLT simulation.

## Current scope

This first scaffold includes:

- `pmslt_spec()` to define a model from minimal information.
- `age_bands()` to create standard age-group definitions.
- `draft_input_templates()` to generate beginner-friendly CSV templates.
- `validate_spec()` and `diagnose_missing_parameters()` to explain modelling
  requirements before data collection.
- `solve_dismod_lite()` to read an `input_raw` directory, disaggregate coarse
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
  `disease`.

Full simulation engine functions will be migrated from the existing PMSLT
template in later modules.

## Example

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
solve_dismod_lite("inputs_raw")
solve_dismod_lite("inputs_raw", uncertainty = TRUE, draws = 2000, seed = 1)
```

This creates the CSV templates and a `README_inputs_raw.md` guide inside the
output folder. The guide explains every file and every blank column that the
student needs to fill before DisMod processing. The output also includes
`00_column_dictionary.csv`, which marks columns as generated, required,
conditional, or optional.

## Mock DisMod demonstration

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

It is for learning the workflow shape only, not a substitute for real DisMod-MR.

## Downstream PMSLT disease module

After DisMod processing, use `pmslt_disease_epi.csv` as the disease input:

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

## Main all-cause lifetable starter

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
bau <- run_pmslt_lifetable_bau(population, mortality, horizon = 1)
disease_attached <- integrate_disease_deltas(bau, disease_epi)
summarise_pmslt_results(disease_attached)
summarise_pmslt_results(disease_attached, by = c("disease", "age"))
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

These all-cause lifetable functions do not apply interventions, PIFs, direct
effects, costs, PSA, births, migration, or entrants yet. Disease-attributable
deaths are attached beside all-cause deaths; they are not subtracted from the
all-cause lifetable in this slice.

## Intervention workflow

For risk-factor interventions, `calculate_pif_from_inputs()` converts
`08_risk_factor_prevalence.csv` and `09_relative_risks.csv` into the PIF table
used by the disease lifetable. It first checks that risk-category prevalences
sum to 1 within each age, sex, stratum, time step, risk factor, and intervention
arm. For interventions that directly change disease incidence, case fatality, or
morbidity, fill `10_direct_intervention_effects.csv`. Multiple intervention
arms can live in the same template folder:

```r
results <- run_pmslt_interventions(
  disease_epi = "mock_inputs_raw/mock_dismod_output/pmslt_disease_epi.csv",
  risk_prevalence = "mock_inputs_raw/08_risk_factor_prevalence.csv",
  relative_risks = "mock_inputs_raw/09_relative_risks.csv",
  direct_effects = "mock_inputs_raw/10_direct_intervention_effects.csv"
)
```

This supports PIF-only, direct-only, and combined intervention scenarios.
