# Pact 8 Workflow Hardening Handoff

Worker: 8
Date: 2026-05-30

## Scope Completed

- Aligned `next_pmslt_step()` with the active implemented beginner stages:
  `spec`, `templates`, `raw_inputs`, `raw_validation`,
  `disease_consistency`, `interventions`, `lifetable`, `summaries`, and
  `reporting`.
- Removed top-level navigation support for obsolete/conceptual stage names:
  `dismod_lite`, `pmslt_disease_inputs`, `disease_lifetable`, and `halys`.
- Updated workflow guidance so successful raw validation points to
  `solve_disease_consistency()`, then disease consistency points to
  `run_pmslt_interventions()`, then lifetable and summary helpers.
- Reworked README examples so the active path follows:
  `pmslt_spec()` -> templates -> raw readiness -> disease consistency ->
  interventions -> BAU lifetable -> summaries.
- Marked mock DisMod and direct lower-level solver usage as conceptual or
  diagnostic examples rather than the active beginner workflow.
- Updated `CODEX.md` so future agents keep the same active example order and do
  not treat mock DisMod or direct `dismod_slove()` calls as the main path.

## Boundaries Preserved

- No modelling calculations changed.
- No raw schemas, disease consistency solver behaviour, intervention formulas,
  lifetable calculations, cost functions, or summary semantics changed.
- `inst/artifacts/package_architecture.md` was read but not edited.
- Existing unrelated working-tree changes were not reverted.

## Release-Readiness Checklist

- [x] README active example shows only implemented functions.
- [x] README conceptual/demo examples are labelled as conceptual or lower-level
  options.
- [x] `next_pmslt_step()` no longer presents mock/lower-level implementation
  details as top-level workflow stages.
- [x] Workflow navigation has tests for the active stage list, obsolete stage
  rejection, raw-validation branching, and recommended function order.
- [x] `CODEX.md` mirrors the active beginner workflow order.
- [ ] Regenerate roxygen documentation for `next_pmslt_step()` before a release
  build, because this pact did not edit generated `.Rd` files.
- [ ] Run full `devtools::test()` after all pact workers merge their slices.
- [ ] Run `R CMD build .` and `R CMD check pmslttools_*.tar.gz --no-manual
  --no-build-vignettes` after the full pact is integrated.
- [x] Confirmed README cost-function references match current NAMESPACE exports:
  `summarise_costs()`, `compare_costs()`, and `calculate_icers()`.

## Validation

- `Rscript -e 'testthat::test_file("tests/testthat/test-workflow-navigation.R")'`
  failed because bare `test_file()` did not load the package namespace; all
  failures were missing function bindings.
- `Rscript -e 'devtools::test(filter = "workflow-navigation")'` passed:
  101 passed, 0 failed, 0 warnings, 0 skipped.
