# Pact 3 Intervention Lifetable Handoff

## Scope

This slice connects disease-level outputs from `run_pmslt_interventions()` to
the main all-cause PMSLT lifetable. It is deterministic only. It does not add
costs, PSA, discounting, age weighting, or equity logic.

## Beginner-facing path

1. Read or create canonical post-DisMod disease inputs with
   `read_pmslt_disease_inputs("pmslt_disease_epi.csv")`.
2. Run intervention disease effects with `run_pmslt_interventions()`.
3. Pass those outputs to `run_pmslt_lifetable_interventions()` with the main
   population, all-cause mortality, and optional morbidity inputs.
4. Compare each arm with `result$comparisons[[arm]]`, or use
   `compare_pmslt_results(result$bau, result$interventions[[arm]])`.

## Deterministic bridge rule

For each intervention arm, disease, exact age, sex, stratum, and time step,
`run_pmslt_interventions()` supplies disease-level `delta_mortality` and
`delta_morbidity` values. The main lifetable bridge aggregates those deltas
across diseases by `intervention`, `time_step`, `age`, `sex`, and `stratum`.

The all-cause intervention lifetable then applies:

```r
mortality_rate_Int = pmin(1, pmax(0, mortality_rate_BAU + sum(delta_mortality)))
morbidity_rate_Int = pmax(0, morbidity_rate_BAU + sum(delta_morbidity))
```

Deaths, alive-at-end, person-years, YLDs, and subsequent-cycle ageing are
recalculated from the adjusted all-cause rates. The maximum age keeps the
existing open-ended ageing rule from `run_pmslt_lifetable_bau()`.

## Outputs

`run_pmslt_lifetable_interventions()` returns a
`pmslt_lifetable_interventions` list with:

- `bau`: the comparable BAU all-cause lifetable.
- `interventions`: one `pmslt_lifetable` per intervention arm.
- `comparisons`: intervention-minus-BAU comparisons for each arm.
- `effect_rule`: the plain-text deterministic rule applied by the bridge.

The disease-specific long output is preserved as the `disease_deltas`
attribute on the BAU and intervention lifetables. The intervention lifetables
also carry row-level `total_delta_mortality` and `total_delta_morbidity`
columns for audit.

## Boundaries preserved

- Disease modules consume `pmslt_disease_epi.csv` only.
- Raw disease inputs are not consumed by this bridge.
- PIF-mediated effects and direct disease effects stay in
  `run_pmslt_interventions()`; the main lifetable receives their explicit
  combined disease-effect handoff.
- Cost, ICER, PSA, discounting, age weighting, and equity logic remain out of
  scope.
