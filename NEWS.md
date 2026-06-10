# pmslttools 0.1.0

First consolidated release. This version brings together the model specification,
input-template, disease-consistency, intervention, lifetable, reporting, costing,
equity, and probabilistic-sensitivity layers into one validated package state.

## Disease consistency solvers

* `solve_disease_consistency()` provides one beginner-facing step from checked raw
  disease inputs to canonical `pmslt_disease_epi.csv`.
* Deterministic `dismod_slove()` solver remains the default and needs no optional
  dependencies.
* Optional `solver = "disbayes"` runs a real Bayesian disease-consistency fit (one
  model per disease/sex/stratum) and maps fitted incidence, remission, case
  fatality, and prevalence back to canonical PMSLT inputs. `disbayes` stays in
  `Suggests`; the package installs and runs the deterministic path without it.

## Inputs, validation, and guidance

* `pmslt_spec()` / `draft_input_templates()` generate project-specific CSV
  templates with a written input guide.
* `validate_raw_inputs()`, `check_raw_input_readiness()`, and
  `summarise_raw_input_issues()` give plain-language readiness diagnostics.
* `next_pmslt_step()` points modellers at the next workflow action.

## Modelling engine

* `calculate_pif_from_inputs()` computes potential impact fractions across multiple
  intervention arms and risk factors.
* `run_pmslt_interventions()` and `run_pmslt_disease_lifetable()` run the disease
  lifetable for business-as-usual and intervention scenarios.
* `run_pmslt_lifetable_bau()`, `run_pmslt_lifetable_interventions()`, and
  `integrate_disease_deltas()` provide the all-cause main lifetable with population
  ageing and disease integration.

## Outcomes, costs, equity, and uncertainty

* `calculate_halys()`, `summarise_pmslt_results()`, and `compare_pmslt_results()`
  summarise health outcomes.
* `attach_pmslt_costs()`, `compare_pmslt_costs()`, and `calculate_icers()` add
  costing and cost-effectiveness summaries.
* `disaggregate_stratum_rates()` applies equity rate ratios while preserving
  aggregate totals.
* `draw_psa_parameters()` and `run_psa_interventions()` provide probabilistic
  sensitivity analysis scaffolding.
