# CODEX Notes for pmslttools

Last updated: 2026-05-22

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
7. Initializing the deterministic all-cause BAU lifetable.
8. Later integrating disease deltas, outcomes, costs, and PSA.

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
3. `pmslt_disease_epi.csv` is the canonical downstream disease input and uses
   exact single-year integer `age`.
4. Multiple intervention arms should be represented at template generation
   stage through `pmslt_spec(intervention_arms = ...)`.
5. PIF-mediated effects and direct disease effects must remain conceptually
   separate.
6. DisMod-lite and mock DisMod functions are teaching tools, not replacements
   for real DisMod-MR.
7. Prefer base R unless a dependency clearly improves usability.
8. Avoid broad refactors until schemas and workflow contracts are stable.
9. Raw epidemiology templates may remain age-banded; future PMSLT engine
   modules should use exact integer age internally and aggregate ages only for
   reporting outputs.
10. Age-band summaries are reporting-only and must come from `spec$ages`; do
    not change lifetable age calculations to implement grouped reporting.
11. Intervention comparisons are reporting-only in this slice. Use
    `compare_pmslt_results()` for compatible completed outputs; do not add new
    intervention simulation mechanics here.

## Current Public API

- `pmslt_spec()`
- `age_bands()`
- `validate_spec()`
- `draft_input_templates()`
- `write_input_template_guide()`
- `diagnose_missing_parameters()`
- `dismod_slove()`
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
- `initialize_pmslt_lifetable()`
- `run_pmslt_lifetable_bau()`
- `integrate_disease_deltas()`
- `summarise_pmslt_results()`
- `compare_pmslt_results()`

## Important Files

- `R/spec.R`: model specification, age bands, spec validation.
- `R/templates.R`: raw CSV template generation.
- `R/input-guide.R`: markdown guide and column dictionary generation.
- `R/diagnostics.R`: missing disease parameter diagnostics.
- `R/dismod-lite.R`: simple teaching-oriented DisMod-style solver.
- `R/mock-dismod.R`: mock data, mock DisMod outputs, plots, continuous-age
  processing, single-year PMSLT disease input preparation.
- `R/pmslt-workflow.R`: post-DisMod disease input validation, PIF calculation,
  disease lifetable, multi-arm intervention runner.
- `R/main-lifetable.R`: deterministic BAU all-cause lifetable initialization,
  single-year ageing, disease-attributable quantity attachment, and summary
  helpers.
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

bau_lifetable <- initialize_pmslt_lifetable(
  population = data.frame(
    age = 40:41,
    sex = "female",
    stratum = "total",
    population = c(1000, 900)
  ),
  mortality = data.frame(
    age = 40:41,
    sex = "female",
    stratum = "total",
    mortality_rate = c(0.01, 0.02)
  )
)

bau_cycles <- run_pmslt_lifetable_bau(
  population = data.frame(
    age = 40:41,
    sex = "female",
    stratum = "total",
    population = c(1000, 900)
  ),
  mortality = data.frame(
    age = 40:41,
    sex = "female",
    stratum = "total",
    mortality_rate = c(0.01, 0.02)
  ),
  horizon = 5
)

disease_attached <- integrate_disease_deltas(
  lifetable = run_pmslt_lifetable_bau(
    population = data.frame(
      age = 40:41,
      sex = "female",
      stratum = "total",
      population = c(1000, 900)
    ),
    mortality = data.frame(
      age = 40:41,
      sex = "female",
      stratum = "total",
      mortality_rate = c(0.01, 0.02)
    ),
    horizon = 1
  ),
  disease_epi = "inputs_raw/mock_dismod_output/pmslt_disease_epi.csv"
)

summarise_pmslt_results(disease_attached)
summarise_pmslt_results(disease_attached, by = c("disease", "age"))
summarise_pmslt_results(disease_attached, by = c("disease", "age_band"))
```

## Current Known Issues

1. `run_pmslt_disease_lifetable()` is not a full PMSLT model yet. It is a
   disease-specific module.
2. Real DisMod-MR integration does not exist yet.
3. `demo_mock_inputs_raw/` may need regeneration after the latest multi-arm
   direct-effect changes.
4. `initialize_pmslt_lifetable()` runs one BAU time step only.
5. `integrate_disease_deltas()` attaches disease-attributable cases, deaths,
   and YLDs beside BAU all-cause lifetable rows. It does not subtract disease
   deaths from all-cause deaths.
6. `run_pmslt_lifetable_bau()` ages survivors forward across BAU cycles, but
   it still does not add births, migration, entrants, interventions, costs,
   equity, or PSA.
7. `summarise_pmslt_results()` supports exact-age summaries and reporting-only
   `age_band` summaries when the lifetable result has a `pmslt_spec` with
   age bands attached.
8. `compare_pmslt_results()` compares compatible PMSLT outputs against BAU
   outputs as `intervention - BAU` deltas overall or by `time_step`, `sex`,
   `stratum`, exact `age`, or reporting `age_band`.

## Next Best Tasks

1. Regenerate `demo_mock_inputs_raw/`.
2. Add a full beginner vignette.
3. Decide the later full main-lifetable convention for applying disease
   mortality and morbidity deltas.

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
