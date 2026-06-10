# PMSLT concepts for beginners

This is a plain-language reference for the ideas behind a proportional
multistate lifetable (PMSLT) model and the inputs `pmslttools` asks for. Read it
alongside the `pmslt-end-to-end` vignette.

## The two worlds: BAU vs intervention

A PMSLT model always compares at least two versions of the future for the same
population:

- **Business as usual (BAU)** — what happens if nothing changes.
- **Intervention** — what happens if a policy, programme, or treatment is
  introduced.

Every output that matters (lives, health, costs) is reported as the *difference*
between these two worlds. The package writes this difference as
`intervention - BAU`, so a fall in deaths shows up as a negative number.

## How a disease is modelled

Each disease is a little three-state machine that a person moves through over
time:

```
        incidence              case fatality
  healthy ─────────▶ with disease ─────────▶ dead
        ◀─────────
         remission
```

The rates that drive it are the disease inputs the package solves for:

- **Incidence** — the rate of *getting* the disease (healthy → diseased). It is
  a flow, measured per person-year.
- **Prevalence** — the *share of people who currently have* the disease. It is a
  stock, measured as a proportion. Incidence builds prevalence up over time;
  remission and death draw it down.
- **Remission** — the rate of recovering (diseased → healthy). Some diseases
  have effectively zero remission.
- **Case fatality** — the rate of dying *from the disease* among people who have
  it (diseased → dead).
- **Excess mortality** — how much *higher* the death rate is for people with the
  disease compared with people without it. Case fatality and excess mortality
  are related but not identical: case fatality is disease-specific death,
  excess mortality is the extra all-cause risk that comes with the disease.
  The package keeps them as separate, explicit fields so you never silently
  reinterpret one as the other.
- **Disability weight** — how bad a year lived with the disease is, on a 0 (full
  health) to 1 (equivalent to death) scale. It converts prevalence into years
  lived with disability (YLD).

These rates cannot be picked independently: a given incidence, remission, and
mortality imply a particular prevalence. Choosing them by hand almost always
produces an impossible combination.

## Why DisMod (and disbayes)

**Disease consistency solving** is the step that takes your scattered, often
incomplete evidence (some incidence here, a prevalence survey there) and finds a
*coherent* set of rates that the three-state machine can actually produce.

`pmslttools` offers two solvers:

- **`dismod_slove`** — a fast, deterministic, dependency-free solver. Good for
  getting started and for point-estimate evidence.
- **`disbayes`** — a Bayesian solver (optional install) that propagates
  uncertainty and is the more rigorous choice when your evidence carries
  confidence intervals or sample sizes.

Both write the same canonical `pmslt_disease_epi.csv`, so the rest of the
pipeline does not care which you used.

## How an intervention changes the disease

Interventions reach the disease model in two ways:

- **Through a risk factor (a PIF).** Many policies work by shifting a risk
  factor — smoking, body-mass index, diet. The **potential impact fraction
  (PIF)** is the proportion of disease incidence that would be avoided if the
  risk-factor distribution moved from its BAU pattern to the intervention
  pattern. The package computes it from `08_risk_factor_prevalence.csv` (who is
  in each risk category, with and without the intervention) and
  `09_relative_risks.csv` (how much each category raises disease risk). With
  several risk factors, their PIFs are combined as `1 - prod(1 - pif)`, an
  independence-style approximation.
- **Directly on the disease.** Some interventions act on incidence, case
  fatality, or morbidity directly — for example acute care that lowers case
  fatality. These go in `10_direct_intervention_effects.csv` as relative risks
  plus a **coverage** value. Coverage scales the treated-group effect up to the
  whole population: a relative risk of 0.80 delivered to 50% of people becomes a
  population multiplier of `1 - 0.5 * (1 - 0.80) = 0.90`.

A single intervention arm can use both mechanisms at once.

## From disease effects to population outcomes

The disease model produces, for each arm, the change in disease-specific
mortality and morbidity (the "deltas"). The **main all-cause lifetable** then
ages the whole population year by year, applying those deltas on top of
background mortality and morbidity, and tallies:

- **Person-years** — total years of life lived.
- **YLD** — years lived with disability (person-years weighted by disability).
- **HALYs** — health-adjusted life years, `person_years - yld`. This is the
  headline health outcome.

## Costs and cost-effectiveness

With cost inputs (`12_costs.csv`), the model attaches background and
disease-related costs to each lifetable row. The **ICER** (incremental
cost-effectiveness ratio) is then `incremental cost / incremental HALYs` for an
arm versus BAU. The package only reports a ratio when incremental HALYs are
positive, and flags the zero and negative cases explicitly instead of printing a
misleading number.

## Equity

The same model can be run with stratum-specific rates so that outcomes are
reported for sub-populations (for example by socioeconomic group). Rate ratios
in `11_stratum_rate_ratios.csv` disaggregate aggregate rates while preserving the
overall total, so the strata always add back up to the whole population.

## A one-line mental model

> Solve coherent disease rates → shift them with the intervention → age the
> population through the lifetable in both worlds → report the difference in
> health and money.
