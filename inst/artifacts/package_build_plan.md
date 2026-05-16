# PMSLT R Package Build Plan

## Goal

Convert the current PMSLT modelling template into a beginner-friendly R package
that guides PhD students and other new simulation modellers from model scoping,
through raw parameter collection and DisMod processing, into a modular PMSLT
simulation workflow.

## Core Principle

The package should not start with the simulation engine. It should start with
the question a beginner actually has: what data do I need for this model?

The package should therefore be organised around explicit workflow stages,
schemas, validators, and clear messages.

## Proposed Workflow

```r
spec <- pmslt_spec(
  intervention = "Tobacco tax",
  mechanism = "risk_factor",
  diseases = c("CHD", "Stroke", "Lung cancer", "COPD"),
  risk_factors = "Smoking",
  ages = age_bands(0, 100, by = 5),
  sexes = c("male", "female"),
  strata = "total",
  horizon = 80,
  cost_effectiveness = TRUE
)

draft_input_templates(spec, output_dir = "inputs_raw")
raw <- read_pmslt_inputs("inputs_raw")
dismod_input <- prepare_dismod_inputs(raw, spec, output_dir = "inputs_dismod")
dismod_output <- read_dismod_outputs("inputs_dismod/results")
model_inputs <- prepare_pmslt_inputs(raw, dismod_output, spec)
result <- run_pmslt(model_inputs, spec)
summarise_pmslt(result)
plot_pmslt(result)
```

## Package Layers

1. Specification layer
   - `pmslt_spec()`
   - `age_bands()`
   - `validate_spec()`
   - `print.pmslt_spec()`

2. Template and data-collection layer
   - `draft_input_templates()`
   - `draft_dismod_templates()`
   - `export_template_csvs()`

3. Validation and DisMod layer
   - `validate_raw_inputs()`
   - `diagnose_missing_parameters()`
   - `prepare_dismod_inputs()`
   - `read_dismod_outputs()`
   - `check_dismod_coherence()`
   - `prepare_pmslt_inputs()`

4. Simulation layer
   - `initialize_main_lifetable()`
   - `calculate_pif()`
   - `run_disease_lifetable()`
   - `integrate_disease_deltas()`
   - `aggregate_population_results()`
   - `run_pmslt()`
   - `run_psa()`

## Early Build Order

1. Scaffold the R package.
2. Implement `pmslt_spec()` and age-band helpers.
3. Implement CSV template generation.
4. Add plain-language diagnostics for missing parameters.
5. Add raw input reading and validation.
6. Add DisMod input and output adapters.
7. Refactor the deterministic PMSLT engine from the existing script.
8. Add worked examples and vignettes.
9. Add PSA and cost-effectiveness extensions.
10. Consider an Excel workbook generator and Shiny validation dashboard after
    the core schema is stable.

## Naming Standards

Use clear names that separate all-cause and disease-specific quantities:

- `acmr_BAU`: all-cause mortality rate.
- `pYLD_BAU`: all-cause morbidity or prevalent YLD rate.
- `incidence_BAU`: disease incidence rate.
- `prevalence_initial`: base-year prevalence.
- `remission_rate`: disease remission rate.
- `excess_mortality_rate`: mortality among diseased beyond background mortality.
- `case_fatality_rate`: case fatality rate, if this is the intended input.
- `disease_mortality_rate`: cause-specific disease mortality only when truly used.

Avoid reusing `mort_BAU` for both all-cause mortality and disease mortality.

## First Implementation Slice

The first package slice should cover the beginning of the workflow:

- Define a model specification.
- Validate that the specification is coherent.
- Generate raw input CSV templates.
- Explain which disease parameters are required and which can be estimated
  through DisMod.

This makes the package immediately useful for planning projects before the full
simulation engine is migrated.
