# Pact 2 Disbayes Execution Bridge Handoff

Date: 2026-05-30

## Implemented

- `solve_disease_consistency()` now defaults to `solver = "disbayes"` while
  preserving explicit `solver = "dismod_slove"` for non-disbayes workflows.
- `disbayes` is listed in `Suggests` only. The package still loads and the
  deterministic disease consistency tests run without `disbayes` installed.
- The disbayes branch checks for the optional package and gives a clear setup
  message when it is unavailable.
- The execution bridge keeps a clean adapter boundary:
  - prepare PMSLT raw inputs and long solver evidence,
  - fit independently by `disease + sex + stratum`,
  - tidy fitted outputs,
  - map to canonical `pmslt_disease_epi.csv`,
  - write fit summaries and audit CSVs.
- The fitted output mapping is explicit:
  - `inc` -> `incidence_BAU`
  - `rem` -> `remission_rate`
  - `cf` -> `case_fatality_BAU`
  - `prev_prob` -> `prevalence_initial`
- Fitted disbayes annual probabilities are converted back to canonical rates
  with `-log(1 - probability)` for incidence, remission, and case fatality.
- Explicit `excess_mortality_rate` is carried into `excess_mortality_BAU` only
  when supplied. It is not derived from `cf`.
- `disability_weight` is joined from `05_disease_epidemiology_raw.csv`.
- Execution writes:
  - `pmslt_disease_epi.csv`
  - `disbayes_solver_long.csv`
  - `disbayes_fit_summary.csv`
  - `disbayes_rate_conversion_audit.csv`
  - `disbayes_evidence_audit.csv`
  - `disbayes_group_diagnostics.csv`

## Optional Dependency Behaviour

`disbayes` is not installed in the local test environment used for this slice.
High-level real execution therefore stops with the optional dependency message.
Tests cover the execution and mapping contract by injecting a fake
`fit_function` through the internal adapter boundary.

## Real API Verification

`disbayes` 1.1.1 was installed and the adapter was updated against its real
API. The fitting call now passes a wide age-indexed data frame with
`inc_prob`/`inc_lower`/`inc_upper`, `prev_prob`/`prev_lower`/`prev_upper`,
`mort_prob`/`mort_lower`/`mort_upper`, and
`rem_prob`/`rem_lower`/`rem_upper` columns. Fitted `disbayes` objects are
converted with `disbayes::tidy()`, then mapped from `inc_prob`, `rem_prob`,
`cf_prob`, and `prev_prob` back to canonical PMSLT fields.

The real smoke test used a 0:89 exact-age fixture and completed successfully
with `solve_disease_consistency(..., solver = "disbayes", method = "opt",
draws = 0, iter = 1000)`.

## Verification

- `Rscript -e 'pkgload::load_all("."); testthat::test_file("tests/testthat/test-disease-consistency.R"); testthat::test_file("tests/testthat/test-dismod-lite.R")'`
  - Result: pass; disease-consistency 18 tests, dismod-lite 25 tests.
- `Rscript -e 'devtools::test()'`
  - Result: pass; 642 tests.
- `R CMD check --no-manual --no-build-vignettes .`
  - Result: failed at dependency checking because suggested package
    `disbayes` is not installed.
- `_R_CHECK_FORCE_SUGGESTS_=false R CMD check --no-manual --no-build-vignettes .`
  - Result: package installs and loads, but check fails on an existing test
    that expects source `README.md`/`CODEX.md` paths during installed-package
    checks. The same run also reports pre-existing package-structure warnings
    for `.agents` and the generated `..Rcheck` directory.
- After installing `disbayes` 1.1.1:
  - `Rscript -e 'devtools::test()'` passed with 643 passed and 1 skipped.
  - `R CMD build . && R CMD check pmslttools_0.0.0.9009.tar.gz --no-manual --no-build-vignettes`
    passed with status OK.
  - A direct real-disbayes smoke test passed using a 0:89 exact-age fixture.
