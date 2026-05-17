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
  mechanism = "risk_factor",
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
