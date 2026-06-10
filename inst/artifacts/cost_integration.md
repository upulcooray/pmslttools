# Cost Integration In The PMSLT Model

This note explains how costs are currently integrated in `pmslttools` based on
the implemented code. The current cost pathway is deterministic and sits after
lifetable outputs have already been produced. It does not change mortality,
morbidity, disease, or intervention calculations.

## Where Cost Inputs Enter

Costs enter through the optional raw input template `12_costs.csv`.

The template is generated only when the project specification has
`cost_effectiveness = TRUE`. In that case, `draft_input_templates()` includes
`12_costs.csv` alongside the other raw input files. The template is built from
the disease grid and therefore has one row per age band, sex, stratum, and
disease combination.

The schema for `12_costs.csv` is defined centrally in `R/schema.R` and exposed
through the input guide. The key fields are:

- `age_start`, `age_end`, and `age_label`: age range covered by the cost row.
- `sex`: sex group.
- `stratum`: population stratum.
- `disease`: disease name.
- `disease_cost`: annual cost per prevalent disease case.
- `background_cost`: annual non-disease-specific health-system cost per person.
- `currency`: uppercase three-letter currency code, such as `AUD`.
- `price_year`: price year for all costs.
- `source`: data source.
- `notes`: free-text description of cost perspective or assumptions.

## Validation Before Attachment

The main validator is `validate_cost_inputs()` in `R/costs.R`.

It accepts either a data frame or a path to a `12_costs.csv` file. Validation
uses the central raw input schema and then adds cost-specific consistency
checks. The implemented checks require:

- all schema columns to be present;
- required fields such as `disease_cost`, `currency`, `price_year`, and
  `source` to be filled;
- cost fields to be non-negative;
- `currency` to be a valid uppercase three-letter code;
- one currency across the whole file;
- one price year across the whole file;
- no duplicate rows for the cost key;
- consistent `background_cost` values across disease rows for the same
  `age_start`, `age_end`, `sex`, and `stratum`.

The repeated `background_cost` check matters because `12_costs.csv` has one row
per disease, but background costs are not disease-specific in the implemented
model. The same background cost is allowed to appear repeatedly across disease
rows for the same demographic group, but it must not differ across those rows.

If validation finds errors, `attach_pmslt_costs()` stops and asks the user to
inspect the issue table from `validate_cost_inputs()`.

## Attachment Point In The Model

Costs are attached by `attach_pmslt_costs()` after a lifetable result already
exists.

The expected input is a `pmslt_lifetable` result from one of these paths:

- `run_pmslt_lifetable_bau()`, for all-cause BAU lifetable rows; or
- `integrate_disease_deltas()`, for all-cause lifetable rows with
  disease-specific deltas attached in the `disease_deltas` attribute.

The cost module therefore behaves as a post-processing layer over exact-age
lifetable rows. It does not run the lifetable, apply interventions, change
rates, discount costs, age weight outputs, or run PSA.

## Background Cost Calculation

For each exact-age lifetable row, `attach_pmslt_costs()` matches exactly one
background cost row by:

- exact age falling within `age_start` to `age_end`;
- matching `sex`;
- matching `stratum`.

The disease column is ignored for background cost matching. Internally, repeated
background values across diseases are collapsed to one value per age range, sex,
and stratum.

The formula is:

```text
background_costs = person_years * background_cost_per_person
```

If `background_cost` is blank in the cost input, it is normalised to zero before
attachment.

## Disease Cost Calculation

Disease costs are calculated only when the lifetable result has disease deltas
attached. In practice, that means `attach_pmslt_costs()` can calculate disease
costs after `integrate_disease_deltas()` or after a workflow that preserves the
same `disease_deltas` attribute.

For each disease-delta row, the cost module first matches the disease row back
to the all-cause lifetable row using:

- `time_step`;
- exact `age`;
- `sex`;
- `stratum`.

It then matches exactly one cost row using:

- exact age falling within `age_start` to `age_end`;
- matching `sex`;
- matching `stratum`;
- matching `disease`.

The implemented formulas are:

```text
prevalent_cases = person_years * disease_prevalence
disease_costs = prevalent_cases * disease_cost_per_case
```

Disease costs are stored in a disease-specific details table on the
`cost_disease_details` attribute. The lifetable-level output stores their sum
per all-cause lifetable row as `total_disease_costs`.

If no disease deltas are present, `total_disease_costs` is set to zero and only
background costs are attached.

## Cost Columns Added To Lifetable Outputs

`attach_pmslt_costs()` returns the original `pmslt_lifetable` result with these
additional columns:

- `background_cost_per_person`;
- `background_costs`;
- `total_disease_costs`;
- `total_costs`.

The total is calculated as:

```text
total_costs = background_costs + total_disease_costs
```

The function also preserves existing lifetable attributes such as `spec`,
`ageing_rule`, and `disease_deltas`. It adds cost metadata attributes:

- `cost_currency`;
- `cost_price_year`;
- `cost_disease_details`, when disease-delta cost details are available.

## Summarising Costs

There are two summary layers.

### PMSLT-Specific Cost Summaries

`summarise_pmslt_costs()` summarises outputs from `attach_pmslt_costs()`.

For non-disease summaries, it totals:

- `background_costs`;
- `total_disease_costs`;
- `total_costs`.

Supported grouping variables are:

- `overall`;
- `time_step`;
- `sex`;
- `stratum`;
- `age`;
- `age_band`.

When `disease` is included in the grouping, the function switches to the
`cost_disease_details` attribute and summarises:

- `prevalent_cases`;
- `disease_costs`;
- `total_costs`, set equal to `disease_costs` for disease-specific summaries.

All PMSLT-specific cost summaries append `currency` and `price_year` columns
from the cost metadata attributes.

### Generic Reporting Cost Summaries

`summarise_costs()` in `R/reporting.R` is a generic reporting helper. It is not
tied to `12_costs.csv` or `attach_pmslt_costs()`. It summarises any compatible
PMSLT-style table with key columns `time_step`, `age`, `sex`, and `stratum` plus
detected cost columns.

Detected cost columns are:

- `cost`;
- `costs`;
- `total_cost`;
- any column ending in `_cost` or `_costs`.

Users can override detection with `cost_cols`.

## Comparing BAU And Intervention Costs

Cost comparison uses an explicit `intervention - BAU` convention.

For costed PMSLT lifetable outputs, `compare_pmslt_costs()`:

1. checks that both inputs came through `attach_pmslt_costs()`;
2. checks that both inputs have the same currency and price year;
3. checks that the BAU and intervention row structures are compatible;
4. summarises both inputs with `summarise_pmslt_costs()`;
5. returns difference columns such as `total_costs_difference`.

For generic cost tables, `compare_costs()` performs the same reporting-level
comparison for detected or supplied cost columns, again using
`intervention - BAU`.

## ICER Calculation

ICERs are calculated by `calculate_icers()` in `R/reporting.R`.

This function does not attach costs or calculate HALYs. It expects a table that
already contains:

- one incremental cost column; and
- one incremental HALY column.

The expected convention is still `intervention - BAU`.

The formula is:

```text
icer = incremental_cost / incremental_haly
```

The function only reports a numeric ICER when incremental HALYs are positive.
Rows with zero or negative incremental HALYs are labelled in `icer_status`.

## Current Boundaries

The implemented cost pathway deliberately does not include:

- discounting;
- ICER thresholds;
- probabilistic sensitivity analysis for cost outputs;
- one-off intervention implementation costs;
- separate fields for health-system, patient, societal, or productivity costs;
- inflation or price-year conversion;
- currency conversion;
- age weighting;
- distributional cost-effectiveness metrics;
- changes to lifetable, disease, or intervention model mechanics.

The `notes` field can describe cost perspective or assumptions, but the current
calculation does not branch on that field.

## Practical Workflow

A typical deterministic cost workflow is:

```r
spec <- pmslt_spec(
  intervention = "Example intervention",
  mechanism = "direct",
  diseases = "CHD",
  cost_effectiveness = TRUE
)

draft_input_templates(spec, output_dir = "inputs_raw")

cost_issues <- validate_cost_inputs("inputs_raw/12_costs.csv", spec = spec)

bau <- run_pmslt_lifetable_bau(population, mortality, horizon = spec$horizon, spec = spec)
bau_with_disease <- integrate_disease_deltas(bau, disease_epi)
bau_costed <- attach_pmslt_costs(bau_with_disease, "inputs_raw/12_costs.csv", spec = spec)

summarise_pmslt_costs(bau_costed)
summarise_pmslt_costs(bau_costed, by = c("time_step", "sex", "stratum", "disease"))
```

For intervention comparison, both BAU and intervention outputs should be costed
before comparison:

```r
bau_costed <- attach_pmslt_costs(bau_result, "inputs_raw/12_costs.csv", spec = spec)
intervention_costed <- attach_pmslt_costs(intervention_result, "inputs_raw/12_costs.csv", spec = spec)

incremental_costs <- compare_pmslt_costs(bau_costed, intervention_costed)
incremental_halys <- compare_halys(bau_result, intervention_result)

calculate_icers(
  cbind(incremental_costs, haly_difference = incremental_halys$haly_difference)
)
```

## Important Interpretation Notes

Costs are annual and flow through person-years. Background costs represent
annual cost per person in the lifetable row. Disease costs represent annual cost
per prevalent disease case.

Because costs are attached after the lifetable has been calculated, any
intervention cost difference currently arises through changed person-years,
changed disease prevalence in attached disease deltas, or externally supplied
cost columns. There is not yet a separate intervention implementation-cost
module.

The current model treats one `currency` and one `price_year` as mandatory for a
cost input file. This keeps deterministic comparisons interpretable and avoids
silently combining costs measured on different monetary scales.
