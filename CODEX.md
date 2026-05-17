# CODEX Notes for pmslttools

Last updated: 2026-05-17

## Project Purpose

`pmslttools` is an R package for guided proportional multistate lifetable
(PMSLT) modelling. The user wants it to be usable by PhD students and other
beginners who are new to simulation modelling.

The package should guide users through:

1. Defining a model with minimum required information.
2. Generating project-specific raw input CSV templates.
3. Collecting raw disease and intervention parameters.
4. Running or preparing DisMod-style disease parameter processing.
5. Producing `pmslt_disease_epi.csv` as the canonical post-DisMod disease input.
6. Running modular PMSLT disease and intervention workflows.
7. Later integrating full all-cause lifetable, outcomes, costs, and PSA.

## Repository

- Local path: `/Users/upul/Library/CloudStorage/GoogleDrive-upulcooray@gmail.com/My Drive/2nd_brain/projects/R codes/pmslttools`
- GitHub: `https://github.com/upulcooray/pmslttools`
- Main branch: `main`

## Current Package State

- Version: `0.0.0.9009`
- Current architecture docs:
  - `inst/artifacts/package_architecture.md`
  - `inst/artifacts/package_audit_2026-05-17.md`
  - `inst/artifacts/todo_plan.md`
  - `inst/artifacts/package_build_plan.md`

## Design Principles

1. Beginner-facing functions must be explicit and plain-language.
2. Raw inputs, DisMod outputs, and PMSLT-ready inputs must remain separate.
3. `pmslt_disease_epi.csv` is the canonical downstream disease input.
4. Multiple intervention arms should be represented at template generation
   stage through `pmslt_spec(intervention_arms = ...)`.
5. PIF-mediated effects and direct disease effects must remain conceptually
   separate.
6. DisMod-lite and mock DisMod functions are teaching tools, not replacements
   for real DisMod-MR.
7. Prefer base R unless a dependency clearly improves usability.
8. Avoid broad refactors until schemas and workflow contracts are stable.

## Current Public API

- `pmslt_spec()`
- `age_bands()`
- `validate_spec()`
- `draft_input_templates()`
- `write_input_template_guide()`
- `diagnose_missing_parameters()`
- `solve_dismod_lite()`
- `mock_pmslt_spec()`
- `generate_mock_pmslt_inputs()`
- `mock_dismod_output()`
- `smooth_dismod_age_curve()`
- `predict_dismod_to_age_grid()`
- `plot_dismod_corrections()`
- `plot_dismod_age_curve()`
- `prepare_pmslt_disease_inputs()`
- `read_pmslt_disease_inputs()`
- `validate_pmslt_disease_inputs()`
- `validate_risk_prevalence_inputs()`
- `calculate_pif_from_inputs()`
- `run_pmslt_disease_lifetable()`
- `run_pmslt_interventions()`

## Important Files

- `R/spec.R`: model specification, age bands, spec validation.
- `R/templates.R`: raw CSV template generation.
- `R/input-guide.R`: markdown guide and column dictionary generation.
- `R/diagnostics.R`: missing disease parameter diagnostics.
- `R/dismod-lite.R`: simple teaching-oriented DisMod-style solver.
- `R/mock-dismod.R`: mock data, mock DisMod outputs, plots, continuous-age
  processing, PMSLT disease input preparation.
- `R/pmslt-workflow.R`: post-DisMod disease input validation, PIF calculation,
  disease lifetable, multi-arm intervention runner.
- `tests/testthat/`: package tests.

## Current Workflow Shape

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

draft_input_templates(spec, "inputs_raw")
mock_dismod_output("inputs_raw")

results <- run_pmslt_interventions(
  disease_epi = "inputs_raw/mock_dismod_output/pmslt_disease_epi.csv",
  risk_prevalence = "inputs_raw/08_risk_factor_prevalence.csv",
  relative_risks = "inputs_raw/09_relative_risks.csv",
  direct_effects = "inputs_raw/10_direct_intervention_effects.csv"
)
```

## Current Known Issues

1. `run_pmslt_disease_lifetable()` is not a full PMSLT model yet. It is a
   disease-specific module.
2. Real DisMod-MR integration does not exist yet.
3. CSV schemas are spread across template generation, input guide, validators,
   and downstream functions.
4. `demo_mock_inputs_raw/` may need regeneration after the latest multi-arm
   direct-effect changes.

## Next Best Tasks

1. Create central schema definitions in `R/schema.R`.
2. Add `validate_raw_inputs()`.
3. Formalise the `pmslt_disease_epi.csv` schema.
4. Regenerate `demo_mock_inputs_raw/`.
5. Add a full beginner vignette.
6. Start main all-cause lifetable module after schemas stabilise.

## Validation Commands

Run during normal development:

```r
devtools::test()
```

Run before package milestone pushes:

```sh
R CMD build .
R CMD check pmslttools_*.tar.gz --no-manual --no-build-vignettes
```

Clean generated check artifacts after validation:

```sh
rm -rf pmslttools.Rcheck pmslttools_*.tar.gz
```

## Git Practice

- Do not revert user changes.
- Keep commits scoped to one workflow improvement.
- Update artifacts when architecture or workflow contracts change.
- Run tests before push; run full `R CMD check` for milestone changes.
