# pmslttools Audit

Audit date: 2026-05-17

Audited state:

- Package: `pmslttools`
- Version: `0.0.0.9008`
- Repository: `https://github.com/upulcooray/pmslttools`
- Main branch latest implementation before this audit: `0409eb1`

## Summary

The package has a useful early architecture for a beginner-oriented PMSLT
workflow. The strongest parts are model specification, template generation,
plain-language raw input documentation, mock DisMod demonstration files, and
the new multi-arm intervention workflow. The weakest parts are that the
simulation engine is still partial, the DisMod layer is teaching-only, and many
schemas are implicit in helper functions rather than represented as central
schema objects.

## What Works Well

1. Clear workflow entry point:
   - `pmslt_spec()` asks for minimum model structure.
   - `draft_input_templates()` creates the raw data collection files.
   - `write_input_template_guide()` explains columns for students.

2. Good beginner orientation:
   - Function names are mostly plain.
   - Template files are numbered in workflow order.
   - `00_column_dictionary.csv` marks generated, required, conditional, and
     optional fields.

3. Good separation of raw and processed disease inputs:
   - Raw disease input is collected in `05_disease_epidemiology_raw.csv`.
   - Post-DisMod PMSLT input is `pmslt_disease_epi.csv`.
   - Downstream functions are being aligned around the post-DisMod input.

4. Multiple intervention arms now exist at the template stage:
   - `pmslt_spec(intervention_arms = ...)` controls scenario expansion.
   - `08_risk_factor_prevalence.csv` includes `intervention`.
   - `10_direct_intervention_effects.csv` includes `intervention`.

5. Intervention types are now conceptually separated:
   - Risk-factor pathway: prevalence shift plus relative risks gives PIFs.
   - Direct disease pathway: incidence, case fatality, and morbidity
     multipliers.
   - Combined pathway: both are allowed through `mechanism = "both"`.

6. Test coverage exists and is useful:
   - Current tests cover spec creation, template generation, DisMod-lite,
     mock DisMod, plots, post-DisMod inputs, PIFs, and multi-arm interventions.

## Main Risks

### Risk 1: The disease lifetable is still a narrow module

`run_pmslt_disease_lifetable()` handles disease state transitions for a radix
cohort, but it is not yet a full PMSLT model. It does not yet integrate with
the all-cause lifetable, population counts, life expectancy, DALY outcomes,
costs, or age advancement in a full population model.

Impact:

- Users may think the current output is a complete PMSLT result when it is only
  a disease-specific module.

Recommended action:

- Keep documentation explicit.
- Add a higher-level placeholder or future `run_pmslt()` only when all-cause
  and population integration are implemented.

### Risk 2: DisMod-lite may be mistaken for real DisMod-MR

`solve_dismod_lite()` and `mock_dismod_output()` are useful for teaching, but
they are not substitutes for a real DisMod-MR or Bayesian disease modelling
workflow.

Impact:

- Students may overinterpret demonstration outputs.

Recommended action:

- Keep warning language in docs.
- Add `prepare_dismod_mr_inputs()` and `read_dismod_mr_outputs()` later, with
  very explicit boundaries.

### Risk 3: Schemas are duplicated across code and docs

Template columns, dictionary descriptions, validators, and downstream
requirements are currently spread across `R/templates.R`, `R/input-guide.R`,
`R/pmslt-workflow.R`, and `R/dismod-lite.R`.

Impact:

- Future schema changes can drift.
- It is easy to update a template but forget a validator or guide entry.

Recommended action:

- Introduce central schema definitions before the package grows much further.

### Risk 4: Direct-effect helper is conceptually unclear

The internal helper `add_direct_effect_multipliers()` works, but the name is
technical and the formula is not obvious to beginners.

Impact:

- Maintenance is harder.
- A beginner reading source code may not immediately understand coverage
  adjustment.

Recommended action:

- Rename internally to `apply_direct_disease_effects()` or
  `attach_direct_effect_multipliers()`.
- Add a compact code comment explaining:
  `1 - coverage * (1 - rr)`.

### Risk 5: PIF calculation needs stronger validation

`calculate_pif_from_inputs()` checks for missing RRs and complete values. It
does not yet warn if risk-category prevalence does not sum to 1 within age,
sex, stratum, time, risk factor, and intervention.

Impact:

- Bad prevalence distributions can silently produce misleading PIFs.

Recommended action:

- Add `validate_risk_prevalence_inputs()`.
- Warn or error when category sums differ from 1 beyond a tolerance.

### Risk 6: Multiple risk factor assumptions need documentation

The current PIF combiner calculates per-risk-factor PIFs and combines them as:

```r
1 - prod(1 - pif)
```

This is a common independence-style approximation, but it is still an
assumption.

Impact:

- Combined PIFs may be inappropriate if risk factors overlap or interact.

Recommended action:

- Document this explicitly.
- Later allow user-specified PIF combination methods.

### Risk 7: No central project vignette yet

README examples are helpful but not enough for a PhD student learning the full
workflow.

Impact:

- Users may not understand which files to fill, which files are generated, and
  which files are downstream model inputs.

Recommended action:

- Add a vignette or long tutorial:
  `vignettes/pmslt_workflow_from_spec_to_interventions.Rmd`.

## Immediate Code Quality Observations

1. Public API is still small and understandable.
2. Internal helpers are currently all in broad files; future growth will need
   more file separation.
3. Manual `.Rd` files are present, but long term the package should regenerate
   them through roxygen rather than hand-editing.
4. Example data under `demo_mock_inputs_raw/` appears to reflect an older
   generated state and may need regeneration after multi-arm/direct-effect
   changes.
5. Package does not currently depend on tidyverse, which keeps installation
   light. Continue using base R unless a dependency clearly improves usability.

## Suggested Architecture Refactor Later

When the package grows, split current files into narrower modules:

- `R/spec.R`
- `R/schema.R`
- `R/templates.R`
- `R/input-guide.R`
- `R/validation-raw.R`
- `R/dismod-lite.R`
- `R/dismod-mr-adapter.R`
- `R/prepare-pmslt-inputs.R`
- `R/interventions-pif.R`
- `R/interventions-direct.R`
- `R/disease-lifetable.R`
- `R/main-lifetable.R`
- `R/outcomes.R`
- `R/costs.R`
- `R/plotting.R`
- `R/mock-data.R`

Do this gradually. Do not refactor just for file neatness while the model
contracts are still changing.

## Recommended Next Technical Checks

Run before major commits:

```r
devtools::test()
```

Run before pushing user-facing package milestones:

```sh
R CMD build .
R CMD check pmslttools_*.tar.gz --no-manual --no-build-vignettes
```

Run after intervention-related changes:

```r
out <- tempfile("mock_inputs_")
generate_mock_pmslt_inputs(out)
mock_dismod_output(out)
results <- run_pmslt_interventions(
  disease_epi = file.path(out, "mock_dismod_output", "pmslt_disease_epi.csv"),
  risk_prevalence = file.path(out, "08_risk_factor_prevalence.csv"),
  relative_risks = file.path(out, "09_relative_risks.csv"),
  direct_effects = file.path(out, "10_direct_intervention_effects.csv")
)
stopifnot(length(unique(results$intervention)) == 2)
```

## Audit Conclusion

The package is on a sound path for a guided PMSLT modelling toolkit. The next
major step should not be adding more isolated helper functions. It should be
stabilising the data contracts and building a complete end-to-end teaching
workflow from `pmslt_spec()` to multi-intervention disease outputs, then adding
main lifetable integration once the post-DisMod disease input contract is firm.
