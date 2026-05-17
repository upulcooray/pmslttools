# pmslttools Todo Plan

Last updated: 2026-05-17

## Guiding Priorities

1. Keep the package beginner-friendly.
2. Stabilise input and output schemas before expanding the engine.
3. Keep raw, DisMod-processed, and PMSLT-ready files separate.
4. Make intervention handling intuitive at template stage and model stage.
5. Add full PMSLT components only after disease input contracts are clear.

## Source Template Migration Map

This package is being built from the modelling ideas in
`../PMSLT_Template_v1.R`, but the script should not be copied directly. The
package has clearer CSV schemas, post-DisMod disease inputs, and multi-arm
intervention handling. The source template should be mined module by module.

Migration status:

- Pre-simulation coherence check: partly superseded by `diagnose_missing_parameters()`
  and `solve_dismod_lite()`. Still useful for future raw validation messages.
- Module I main lifetable initialisation: not yet migrated. Needed for full
  population PMSLT.
- Module II PIF calculation: migrated and improved as `calculate_pif_from_inputs()`.
- Module III disease lifetable: partly migrated as `run_pmslt_disease_lifetable()`;
  disease costs and YLD outputs still need migration.
- Module IV main lifetable integration: not yet migrated. This is the most
  important next engine layer after intervention validation.
- Module V aggregation and ICERs: not yet migrated. Needed after main lifetable.
- Equity mortality disaggregation: not yet migrated. Should be connected to
  `11_stratum_rate_ratios.csv`.
- Master execution pipeline: should be rebuilt later as `run_pmslt()`, not
  copied directly.
- PSA sampler and probabilistic wrapper: useful design, but should be rebuilt
  after deterministic schemas and engine outputs stabilise.

## Phase 1: Clarify Current Intervention Layer

Status: in progress

### 1.1 Rename direct-effect helper

Status: completed 2026-05-17.

Problem:

- `add_direct_effect_multipliers()` is technically correct but unclear.

Todo:

- Rename to `apply_direct_disease_effects()` or
  `attach_direct_effect_multipliers()`.
- Add a short explanatory comment for:

```r
effective_multiplier <- 1 - coverage * (1 - rr)
```

Acceptance criteria:

- Tests still pass.
- `run_pmslt_interventions()` output unchanged.
- Source code is clearer to a beginner reading it.

Implementation note:

- Renamed the helper to `apply_direct_disease_effects()`.
- Added an explanatory code comment about converting treatment-group RR and
  coverage into a population-level multiplier.

### 1.2 Validate prevalence distributions

Status: completed 2026-05-17.

Problem:

- PIF calculation currently requires complete prevalence and RR values but does
  not check that category prevalence sums to 1.

Todo:

- Add `validate_risk_prevalence_inputs()`.
- Check BAU category sums by age, sex, stratum, time step, and risk factor.
- Check intervention category sums by age, sex, stratum, time step, risk factor,
  and intervention.
- Use a default tolerance such as `1e-6` or `0.001`.
- Produce plain-language warnings or errors.

Acceptance criteria:

- Bad category sums are detected.
- Error messages identify the affected risk factor and intervention arm.

Implementation note:

- Added exported `validate_risk_prevalence_inputs()`.
- `calculate_pif_from_inputs()` now calls this validation before joining RRs.
- Added tests for valid mock prevalence inputs and invalid category sums.

### 1.3 Document multi-risk-factor PIF assumptions

Status: completed 2026-05-17.

Problem:

- Multiple risk-factor PIFs are combined as `1 - prod(1 - pif)`.

Todo:

- Document this in `calculate_pif_from_inputs()` help.
- Add an argument later if needed:

```r
pif_combination = c("independent", "additive")
```

Acceptance criteria:

- Users understand the independence-style assumption.

Implementation note:

- Documented the `1 - prod(1 - pif)` independence-style approximation in
  `calculate_pif_from_inputs()` documentation.

## Phase 2: Stabilise Schemas

Status: high priority

### 2.1 Create central schema definitions

Problem:

- Template columns, guide descriptions, requirements, and validators are
  duplicated across files.

Todo:

- Add `R/schema.R`.
- Define one schema object per CSV file.
- Include:
  - file name
  - column names
  - requirement level
  - description
  - validation type
  - allowed values where relevant

Acceptance criteria:

- `draft_input_templates()`, `00_column_dictionary.csv`, and
  `README_inputs_raw.md` draw from the same schema source.

### 2.2 Add raw input validators

Problem:

- The package generates raw templates but does not yet have a comprehensive raw
  input validation step.

Todo:

- Add `validate_raw_inputs(input_dir, spec = NULL)`.
- Validate required files.
- Validate generated ID columns.
- Validate required/conditional columns.
- Validate rates are non-negative and proportions are 0 to 1.
- Validate risk categories match across prevalence and RR files.

Acceptance criteria:

- A beginner can run one command after filling templates and get a clear issue
  list.

### 2.3 Add issue-list output format

Problem:

- Validation should not always stop at the first error.

Todo:

- Return a data frame with:
  - file
  - row
  - column
  - severity
  - message
  - suggested_fix

Acceptance criteria:

- Validation output can be printed, saved to CSV, or used in a future Shiny app.

## Phase 3: Improve DisMod Integration

Status: high priority

### 3.1 Separate teaching DisMod from real DisMod adapters

Problem:

- `solve_dismod_lite()` and `mock_dismod_output()` are teaching tools, not real
  DisMod-MR integration.

Todo:

- Keep `solve_dismod_lite()` as a local teaching/diagnostic tool.
- Add planned functions:
  - `prepare_dismod_mr_inputs()`
  - `read_dismod_mr_outputs()`
  - `validate_dismod_outputs()`

Acceptance criteria:

- Documentation clearly separates DisMod-lite from real DisMod-MR.

### 3.2 Define canonical DisMod output contract

Problem:

- Downstream modules need a stable post-DisMod format.

Todo:

- Formalise `pmslt_disease_epi.csv` schema.
- Add a section to architecture docs.
- Add `write_pmslt_disease_inputs()` if useful.

Acceptance criteria:

- Every downstream disease module consumes the same schema.

### 3.3 Improve continuous-age to PMSLT-age mapping

Problem:

- Current mapping supports `band_mean` and `midpoint`, but more guidance is
  needed.

Todo:

- Document when to use each method.
- Consider weighted age-band averaging if population weights are available.

Acceptance criteria:

- Students understand when discrete age bands are acceptable and when
  continuous-age smoothing should be used.

## Phase 4: Build Full PMSLT Model Modules

Status: medium priority, after schemas

### 4.1 Main all-cause lifetable

Source template reference:

- `PMSLT_Template_v1.R::initialize_main_lifetable()`

Todo:

- Add `initialize_lifetable()`.
- Use:
  - `01_population.csv`
  - `02_all_cause_mortality.csv`
  - `03_all_cause_morbidity.csv`
  - `04_life_expectancy.csv`
- Track alive, deaths, person-years, morbidity, and life years by age, sex,
  stratum, and time step.

Acceptance criteria:

- BAU lifetable runs without disease interventions.

### 4.2 Disease delta integration

Source template reference:

- `PMSLT_Template_v1.R::run_main_lifetable()`

Todo:

- Add `integrate_disease_deltas()`.
- Combine disease-specific mortality and morbidity deltas into all-cause
  lifetable quantities.
- Decide and document whether disease deltas are additive, multiplicative, or
  capped.

Acceptance criteria:

- `run_pmslt_interventions()` can feed a main PMSLT model.

### 4.3 Population ageing

Todo:

- Implement age advancement between cycles.
- Decide how open-ended age bands are handled.
- Test conservation of population except deaths and migration assumptions.

Acceptance criteria:

- Population flow through age bands is transparent and tested.

### 4.4 Outcome summaries

Source template reference:

- `PMSLT_Template_v1.R::aggregate_population_results()`

Todo:

- Add:
  - life years
  - HALYs/DALYs
  - deaths avoided
  - morbidity changes
  - stratified differences

Acceptance criteria:

- Outputs can be summarised by intervention, disease, sex, stratum, and time.

## Phase 5: Costs and PSA

Status: later

### 5.1 Cost module

Source template reference:

- `PMSLT_Template_v1.R::run_disease_lifetable()`
- `PMSLT_Template_v1.R::run_main_lifetable()`

Todo:

- Consume `12_costs.csv`.
- Separate disease costs, background costs, and intervention costs.
- Add discounting.

### 5.2 Probabilistic sensitivity analysis

Source template reference:

- `PMSLT_Template_v1.R::draw_psa_parameters()`
- `PMSLT_Template_v1.R::run_probabilistic_pmslt()`

Todo:

- Define uncertainty inputs.
- Add parameter draw engine.
- Run repeated PMSLT simulations.
- Summarise uncertainty intervals.

### 5.3 Scenario management

Todo:

- Store assumptions per intervention arm.
- Allow scenario labels and scenario metadata.
- Support comparing multiple interventions and combined intervention packages.

### 5.4 Equity disaggregation

Source template reference:

- `PMSLT_Template_v1.R::disaggregate_mortality()`

Todo:

- Add a tested base-R helper for converting aggregate rates to stratum-specific
  rates using supplied rate ratios.
- Connect it to `11_stratum_rate_ratios.csv`.
- Preserve the aggregate total while applying stratum rate ratios.

Acceptance criteria:

- Weighted stratum-specific survival reproduces aggregate survival.

## Phase 6: Teaching Materials

Status: ongoing

### 6.1 Add vignette

Todo:

- Create `vignettes/pmslt_workflow_from_spec_to_interventions.Rmd`.
- Walk through:
  1. Model spec.
  2. Template generation.
  3. Filling mock data.
  4. DisMod-lite/mock DisMod.
  5. Plotting corrections.
  6. Post-DisMod disease input.
  7. PIF and direct intervention modelling.

### 6.2 Regenerate demo folder

Problem:

- `demo_mock_inputs_raw/` may not reflect the latest multi-arm/direct-effect
  template structure.

Todo:

- Regenerate with current `generate_mock_pmslt_inputs()`.
- Run `mock_dismod_output()`.
- Include `10_direct_intervention_effects.csv` if demo data is committed.

### 6.3 Add concept guide

Todo:

- Add a plain-language document:
  `inst/artifacts/pmslt_concepts_for_beginners.md`.
- Explain:
  - BAU vs intervention
  - incidence vs prevalence
  - remission
  - excess mortality vs case fatality
  - disability weight
  - PIF
  - direct disease effects
  - why DisMod is used

## Commit Checklist

Before each meaningful push:

```r
devtools::test()
```

Before each package milestone:

```sh
R CMD build .
R CMD check pmslttools_*.tar.gz --no-manual --no-build-vignettes
```

Before changing CSV schemas:

- Update template generator.
- Update input guide.
- Update column dictionary.
- Update validators.
- Update mock data.
- Update tests.
- Update architecture docs if the workflow changes.
