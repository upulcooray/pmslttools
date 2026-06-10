# Pact 7 PSA Handoff

Worker: 7
Date: 2026-05-30

## Implemented

- Added `R/psa.R` as a thin PSA layer over deterministic contracts.
- Defined `psa_parameter_draw_schema()` before sampler implementation.
- Added `draw_psa_parameters()` for schema-backed parameter draws.
- Added `run_psa_interventions()` to repeat `run_pmslt_interventions()` by draw.
- Added `summarise_psa_draws()` for draw-level uncertainty intervals.
- Added `tests/testthat/test-psa.R` for schema, reproducibility, repeated deterministic execution, failure reporting, and solver-evidence draws.

## Current Schema-Backed Sampling

- `06_dismod_input_skeleton.csv`: samples `mean_value` from `lower_95` and `upper_95` where supplied.
- `09_relative_risks.csv`: samples `rr` from `rr_lower` and `rr_upper` where supplied, then passes sampled RRs through the existing PIF and intervention runner.
- `pmslt_disease_epi.csv`: included as point estimates because the stable PMSLT-ready disease schema has no uncertainty columns.
- `10_direct_intervention_effects.csv`: included as point estimates because the stable direct-effect schema has no uncertainty columns.
- `12_costs.csv`: included as point estimates because the stable cost schema has no uncertainty columns.

Positive bounded parameters use a lognormal draw. Other bounded parameters use a truncated normal draw. Missing uncertainty bounds produce point-estimate draws.

## Boundaries Preserved

- Deterministic functions do not import or call PSA helpers.
- PSA validates inputs against existing package schemas before drawing.
- Non-solver PSA does not require Bayesian solver dependencies.
- Solver-evidence draws are available without requiring `disbayes`; full per-draw solver execution is intentionally left for a later pact once solver execution contracts are stable enough to write sampled inputs safely.

## Gaps For Later Pacts

- Add uncertainty columns to disease-ready, direct-effect, and cost schemas only if those deterministic contracts are deliberately extended.
- Add a cost PSA runner once deterministic cost outputs are connected to reporting summaries.
- Add per-draw disease-consistency execution after a stable solver input/output contract exists for writing sampled `06_dismod_input_skeleton.csv` files without side effects.

## Verification

- `Rscript -e 'pkgload::load_all(export_all = FALSE); testthat::test_file("tests/testthat/test-psa.R")'`: PASS, 20 expectations.
- `Rscript -e 'pkgload::load_all(export_all = FALSE); testthat::test_file("tests/testthat/test-pmslt-workflow.R")'`: one existing adjacent workflow failure in `intervention outputs bridge into comparable BAU and intervention lifetables`; the failure is outside the PSA-owned files.
