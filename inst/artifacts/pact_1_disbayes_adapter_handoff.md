# Pact 1 Disbayes Adapter Preparation Handoff

Date: 2026-05-30

Worker 1 scope completed:

- Added internal preparation code for `solver = "disbayes"` without calling
  `disbayes`, Stan, or RStan.
- Kept the default high-level solver as `dismod_slove`.
- Kept the canonical `pmslt_disease_epi.csv` schema unchanged.
- Kept `excess_mortality_rate` separate from explicit `mortality` evidence.

Implementation notes:

- Main code lives in `R/disease-consistency.R`.
- `prepare_disbayes_evidence()` reads `05_disease_epidemiology_raw.csv` and
  `06_dismod_input_skeleton.csv`, converts both to a long internal evidence
  table, and prefers filled 06 skeleton evidence over raw values for matching
  age and parameter rows.
- Raw disease columns map as follows:
  - `incidence_rate` -> `incidence`
  - `prevalence` -> `prevalence`
  - `remission_rate` -> `remission`
  - `disease_mortality_rate` -> `mortality`
  - `excess_mortality_rate` -> `excess_mortality`
  - `case_fatality_rate` -> `case_fatality`
- Age-banded evidence is expanded to exact ages using a constant-within-band
  rule and audited with `age_status = "expanded_constant"`.
- Internal fitting ages are padded to `0:max(target_age)` per
  disease/sex/stratum group and audited with `age_status = "padded"`.
- Rate-like evidence is converted to annual probabilities with
  `1 - exp(-rate)` inside the adapter only. Prevalence remains on the
  proportion scale.
- Diagnostics are structured into:
  - `completeness`: requires explicit `mortality` plus at least one of
    `incidence` or `prevalence` for every disease/sex/stratum group.
  - `uncertainty`: requires `lower_95`/`upper_95` or `sample_size` by default.
  - `diagnostics`: combined beginner-readable diagnostic table.
  - `age_audit`: exact, expanded, missing, and padded age provenance.

Public branch behavior:

- `solve_disease_consistency(solver = "disbayes")` now prepares evidence,
  writes preparation outputs, returns a `disease_consistency_result`, and does
  not write `pmslt_disease_epi.csv`.
- Written files:
  - `disbayes_evidence_prepared.csv`
  - `disbayes_preparation_diagnostics.csv`
  - `disbayes_age_audit.csv`
  - `disbayes_uncertainty_audit.csv`

Tests added:

- `tests/testthat/test-disease-consistency.R`
  - checks age-band expansion, zero-padding, internal rate-to-probability
    conversion, explicit mortality completeness, point-estimate-only
    uncertainty diagnostics, and the public `solver = "disbayes"` preparation
    branch.
- Removed the older placeholder test that expected the disbayes branch to stop
  before preparation.

Targeted checks run:

```sh
Rscript -e 'pkgload::load_all(); testthat::test_file("tests/testthat/test-disease-consistency.R")'
```

Result: 21 passes, 0 failures, 0 warnings, 0 skips.

```sh
Rscript -e 'pkgload::load_all(); testthat::test_file("tests/testthat/test-dismod-lite.R")'
```

Result: 25 passes, 0 failures, 0 warnings, 0 skips.

First attempted command:

```sh
Rscript -e 'testthat::test_file("tests/testthat/test-disease-consistency.R")'
```

Result: failed because `test_file()` was run without loading the package
namespace first. The successful command above used `pkgload::load_all()`.
