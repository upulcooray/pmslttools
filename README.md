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
  disease age groups to the template age grid, and fill missing disease
  parameters where simple illness-death consistency equations are identifiable.
  It can optionally propagate uncertainty from `lower_95` and `upper_95`
  columns by Monte Carlo sampling.

Simulation engine functions will be migrated from the existing PMSLT template in
later modules.

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
single-year continuous-age predictions and PMSLT age-grid predictions:

- `mock_dismod_output_continuous.csv`
- `mock_dismod_output_pmslt_ages.csv`
- `pmslt_disease_epi.csv`
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
subsequent PMSLT modules. Raw disease inputs are retained as an audit trail, not
as the direct model input.

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
