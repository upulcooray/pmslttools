#' Initialize a one-step PMSLT all-cause lifetable
#'
#' Creates the business-as-usual starting state for the main all-cause PMSLT
#' lifetable. This first slice only runs one deterministic time step. It does
#' not age the population forward, apply disease deltas, model interventions,
#' add costs, or run PSA. If `stratum_rate_ratios` is supplied, aggregate
#' mortality and morbidity rates are first disaggregated to model strata.
#'
#' @param population Data frame or CSV path. Required columns are `age`, `sex`,
#'   `stratum`, and `population`. The template-style column
#'   `initial_population` is also accepted as `population`.
#' @param mortality Data frame or CSV path. Required columns are `age`, `sex`,
#'   `stratum`, and `mortality_rate`. The template-style column `acmr_BAU` is
#'   also accepted as `mortality_rate`.
#' @param morbidity Optional data frame or CSV path. When supplied, required
#'   columns are `age`, `sex`, `stratum`, and `morbidity_rate`. The
#'   template-style column `pYLD_BAU` is also accepted as `morbidity_rate`.
#'   When omitted, `morbidity_rate` is set to zero.
#' @param spec Optional `pmslt_spec` object. It is validated when supplied and
#'   stored as an attribute on the result.
#' @param stratum_rate_ratios Optional data frame or CSV path from
#'   `11_stratum_rate_ratios.csv`. When supplied, aggregate mortality and
#'   morbidity rates are disaggregated to the population strata before the
#'   one-step lifetable is calculated.
#'
#' @return A data frame with class `pmslt_lifetable`.
#' @export
#'
#' @examples
#' population <- data.frame(
#'   age = c(40L, 41L),
#'   sex = "female",
#'   stratum = "total",
#'   population = c(1000, 900)
#' )
#' mortality <- data.frame(
#'   age = c(40L, 41L),
#'   sex = "female",
#'   stratum = "total",
#'   mortality_rate = c(0.01, 0.02)
#' )
#' initialize_pmslt_lifetable(population, mortality)
initialize_pmslt_lifetable <- function(population,
                                       mortality,
                                       morbidity = NULL,
                                       spec = NULL,
                                       stratum_rate_ratios = NULL) {
  if (!is.null(spec)) {
    validate_spec(spec)
  }

  population <- read_lifetable_input(population, "population")
  mortality <- read_lifetable_input(mortality, "mortality")
  population <- normalize_lifetable_columns(
    population,
    aliases = c(population = "initial_population"),
    label = "population"
  )
  mortality <- normalize_lifetable_columns(
    mortality,
    aliases = c(mortality_rate = "acmr_BAU"),
    label = "mortality"
  )

  validate_lifetable_table(
    population,
    required = c("age", "sex", "stratum", "population"),
    numeric_rules = list(population = "non_negative"),
    label = "population"
  )
  population$population <- as.numeric(population$population)
  validate_lifetable_table(
    mortality,
    required = c("age", "sex", "stratum", "mortality_rate"),
    numeric_rules = list(mortality_rate = "probability"),
    label = "mortality"
  )
  mortality$mortality_rate <- as.numeric(mortality$mortality_rate)

  keys <- c("age", "sex", "stratum")
  population <- check_lifetable_keys(population, keys, "population")
  if (!is.null(stratum_rate_ratios)) {
    mortality <- disaggregate_stratum_rates(
      mortality,
      stratum_rate_ratios,
      target_keys = population[keys],
      spec = spec,
      label = "mortality"
    )
  }
  mortality <- check_lifetable_keys(mortality, keys, "mortality")
  check_complete_lifetable_join(population, mortality, keys, "mortality")

  population$.pmslt_row_id <- seq_len(nrow(population))
  mortality_cols <- c(keys, "mortality_rate", lifetable_rate_audit_columns(mortality, "mortality_rate"))
  out <- merge(
    population[c(keys, "population", ".pmslt_row_id")],
    mortality[mortality_cols],
    by = keys,
    all.x = TRUE,
    sort = FALSE
  )

  if (is.null(morbidity)) {
    out$morbidity_rate <- 0
  } else {
    morbidity <- read_lifetable_input(morbidity, "morbidity")
    morbidity <- normalize_lifetable_columns(
      morbidity,
      aliases = c(morbidity_rate = "pYLD_BAU"),
      label = "morbidity"
    )
    validate_lifetable_table(
      morbidity,
      required = c("age", "sex", "stratum", "morbidity_rate"),
      numeric_rules = list(morbidity_rate = "non_negative"),
      label = "morbidity"
    )
    morbidity$morbidity_rate <- as.numeric(morbidity$morbidity_rate)
    if (!is.null(stratum_rate_ratios)) {
      morbidity <- disaggregate_stratum_rates(
        morbidity,
        stratum_rate_ratios,
        target_keys = population[keys],
        spec = spec,
        label = "morbidity"
      )
    }
    morbidity <- check_lifetable_keys(morbidity, keys, "morbidity")
    check_complete_lifetable_join(population, morbidity, keys, "morbidity")
    morbidity_cols <- c(keys, "morbidity_rate", lifetable_rate_audit_columns(morbidity, "morbidity_rate"))
    out <- merge(
      out,
      morbidity[morbidity_cols],
      by = keys,
      all.x = TRUE,
      sort = FALSE
    )
  }

  out <- out[order(out$.pmslt_row_id), , drop = FALSE]
  out$time_step <- 0L
  out$deaths <- out$population * out$mortality_rate
  out$alive_end <- out$population - out$deaths
  out$person_years <- out$population - 0.5 * out$deaths
  out$yld_rate <- out$morbidity_rate

  audit_cols <- lifetable_output_audit_columns(out)
  out <- out[c(
    "time_step", "age", "sex", "stratum", "population",
    "mortality_rate", "deaths", "alive_end", "person_years",
    "morbidity_rate", "yld_rate", audit_cols
  )]
  row.names(out) <- NULL
  class(out) <- c("pmslt_lifetable", "data.frame")
  attr(out, "spec") <- spec
  out
}

#' Run a deterministic BAU PMSLT all-cause lifetable
#'
#' Runs the business-as-usual all-cause lifetable for multiple yearly cycles
#' using exact single-year integer ages. This function only ages surviving
#' population forward. It does not add births, migration, entrants, disease
#' deltas, intervention effects, costs, or PSA. If `stratum_rate_ratios` is
#' supplied, aggregate mortality and morbidity rates are first disaggregated to
#' model strata.
#'
#' @param population Data frame or CSV path. Required columns are `age`, `sex`,
#'   `stratum`, and `population`. The template-style column
#'   `initial_population` is also accepted as `population`.
#' @param mortality Data frame or CSV path. Required columns are `age`, `sex`,
#'   `stratum`, and `mortality_rate`. The template-style column `acmr_BAU` is
#'   also accepted as `mortality_rate`. If a `time_step` column is present,
#'   mortality rates are matched by `time_step`; otherwise baseline rates are
#'   reused every cycle.
#' @param morbidity Optional data frame or CSV path. When supplied, required
#'   columns are `age`, `sex`, `stratum`, and `morbidity_rate`. The
#'   template-style column `pYLD_BAU` is also accepted as `morbidity_rate`. If a
#'   `time_step` column is present, morbidity rates are matched by `time_step`;
#'   otherwise baseline rates are reused every cycle.
#' @param horizon Number of yearly cycles to run. If omitted, uses
#'   `spec$horizon` when `spec` is supplied, otherwise defaults to 1.
#' @param spec Optional `pmslt_spec` object.
#' @param stratum_rate_ratios Optional data frame or CSV path from
#'   `11_stratum_rate_ratios.csv`. When supplied, aggregate mortality and
#'   morbidity rates are disaggregated to the population strata before the BAU
#'   lifetable is executed.
#'
#' @details
#' Population ageing is deterministic and transparent. At the next cycle,
#' population at age `a` equals survivors from age `a - 1` in the previous
#' cycle. The minimum starting age receives no new entrants. The maximum age is
#' currently treated as open-ended: survivors already at the maximum age remain
#' there and survivors from the previous age also age into the maximum age.
#'
#' @return A data frame with class `pmslt_lifetable`.
#' @export
#'
#' @examples
#' population <- data.frame(
#'   age = c(40L, 41L),
#'   sex = "female",
#'   stratum = "total",
#'   population = c(1000, 900)
#' )
#' mortality <- data.frame(
#'   age = c(40L, 41L),
#'   sex = "female",
#'   stratum = "total",
#'   mortality_rate = c(0.01, 0.02)
#' )
#' run_pmslt_lifetable_bau(population, mortality, horizon = 2)
run_pmslt_lifetable_bau <- function(population,
                                    mortality,
                                    morbidity = NULL,
                                    horizon = NULL,
                                    spec = NULL,
                                    stratum_rate_ratios = NULL) {
  if (!is.null(spec)) {
    validate_spec(spec)
  }
  horizon <- validate_lifetable_horizon(horizon, spec)

  population <- prepare_lifetable_population(population)
  mortality <- prepare_lifetable_rates(
    mortality,
    label = "mortality",
    value_col = "mortality_rate",
    alias = "acmr_BAU",
    rule = "probability"
  )
  morbidity <- if (is.null(morbidity)) {
    NULL
  } else {
    prepare_lifetable_rates(
      morbidity,
      label = "morbidity",
      value_col = "morbidity_rate",
      alias = "pYLD_BAU",
      rule = "non_negative"
    )
  }

  keys <- c("age", "sex", "stratum")
  if (!is.null(stratum_rate_ratios)) {
    mortality <- disaggregate_stratum_rates(
      mortality,
      stratum_rate_ratios,
      target_keys = population[keys],
      spec = spec,
      label = "mortality"
    )
    if (!is.null(morbidity)) {
      morbidity <- disaggregate_stratum_rates(
        morbidity,
        stratum_rate_ratios,
        target_keys = population[keys],
        spec = spec,
        label = "morbidity"
      )
    }
  }
  validate_consecutive_lifetable_ages(population)
  validate_lifetable_rates_for_horizon(population, mortality, keys, horizon, "mortality")
  if (!is.null(morbidity)) {
    validate_lifetable_rates_for_horizon(population, morbidity, keys, horizon, "morbidity")
  }

  current_population <- population[keys]
  current_population$population <- population$population
  rows <- vector("list", horizon)
  for (time_step in seq_len(horizon) - 1L) {
    cycle <- current_population
    cycle$time_step <- time_step
    cycle <- attach_lifetable_rate(cycle, mortality, "mortality_rate", "mortality")
    if (is.null(morbidity)) {
      cycle$morbidity_rate <- 0
    } else {
      cycle <- attach_lifetable_rate(cycle, morbidity, "morbidity_rate", "morbidity")
    }
    cycle$deaths <- cycle$population * cycle$mortality_rate
    cycle$alive_end <- cycle$population - cycle$deaths
    cycle$person_years <- cycle$population - 0.5 * cycle$deaths
    cycle$yld_rate <- cycle$morbidity_rate
    cycle$yld <- cycle$person_years * cycle$morbidity_rate
    rows[[time_step + 1L]] <- cycle[c(
      "time_step", "age", "sex", "stratum", "population",
      "mortality_rate", "deaths", "alive_end", "person_years",
      "morbidity_rate", "yld_rate", "yld", lifetable_output_audit_columns(cycle)
    )]

    if (time_step < horizon - 1L) {
      current_population <- age_lifetable_population(cycle)
    }
  }

  out <- do.call(rbind, rows)
  row.names(out) <- NULL
  class(out) <- c("pmslt_lifetable", "data.frame")
  attr(out, "spec") <- spec
  attr(out, "ageing_rule") <- "open_ended_max_age"
  out
}

#' Run BAU and intervention all-cause lifetables from disease effects
#'
#' Bridges disease-level intervention outputs from [run_pmslt_interventions()]
#' into the main all-cause lifetable. It returns one comparable BAU lifetable
#' and one intervention lifetable per intervention arm. This bridge is
#' deterministic only: it does not add costs, PSA, discounting, age weighting,
#' or equity logic.
#'
#' @param population Data frame or CSV path for main lifetable population.
#' @param mortality Data frame or CSV path for BAU all-cause mortality rates.
#' @param morbidity Optional data frame or CSV path for BAU all-cause morbidity
#'   rates.
#' @param intervention_effects Data frame or CSV path returned by
#'   [run_pmslt_interventions()].
#' @param horizon Number of yearly cycles to run. If omitted, uses
#'   `spec$horizon` when `spec` is supplied, otherwise defaults to 1.
#' @param spec Optional `pmslt_spec` object.
#'
#' @details
#' Disease effects are first summed by `intervention`, `time_step`, `age`,
#' `sex`, and `stratum`. In each intervention cycle, the all-cause mortality
#' rate is updated as `mortality_rate + sum(delta_mortality)` and clamped to
#' `[0, 1]`; the all-cause morbidity rate is updated as
#' `morbidity_rate + sum(delta_morbidity)` and floored at zero. Deaths,
#' person-years, YLDs, survivors, and later-cycle ageing are then recalculated
#' from those adjusted all-cause rates.
#'
#' Disease-specific long output is preserved in the `disease_deltas` attribute
#' on the BAU and intervention lifetables.
#'
#' @return A list with class `pmslt_lifetable_interventions` containing `bau`,
#'   `interventions`, and `comparisons`. Comparison metrics use the
#'   intervention-minus-BAU direction.
#' @export
run_pmslt_lifetable_interventions <- function(population,
                                              mortality,
                                              morbidity = NULL,
                                              intervention_effects,
                                              horizon = NULL,
                                              spec = NULL) {
  if (!is.null(spec)) {
    validate_spec(spec)
  }
  horizon <- validate_lifetable_horizon(horizon, spec)
  effects <- prepare_lifetable_intervention_effects(intervention_effects)

  bau <- run_pmslt_lifetable_bau(
    population = population,
    mortality = mortality,
    morbidity = morbidity,
    horizon = horizon,
    spec = spec
  )
  bau <- attach_lifetable_disease_output(
    lifetable = bau,
    effects = first_intervention_effects(effects),
    scenario = "BAU",
    use_intervention = FALSE
  )

  population <- prepare_lifetable_population(population)
  mortality <- prepare_lifetable_rates(
    mortality,
    label = "mortality",
    value_col = "mortality_rate",
    alias = "acmr_BAU",
    rule = "probability"
  )
  morbidity <- if (is.null(morbidity)) {
    NULL
  } else {
    prepare_lifetable_rates(
      morbidity,
      label = "morbidity",
      value_col = "morbidity_rate",
      alias = "pYLD_BAU",
      rule = "non_negative"
    )
  }

  keys <- c("age", "sex", "stratum")
  validate_consecutive_lifetable_ages(population)
  validate_lifetable_rates_for_horizon(population, mortality, keys, horizon, "mortality")
  if (!is.null(morbidity)) {
    validate_lifetable_rates_for_horizon(population, morbidity, keys, horizon, "morbidity")
  }

  arms <- unique(effects$intervention)
  interventions <- stats::setNames(vector("list", length(arms)), arms)
  comparisons <- stats::setNames(vector("list", length(arms)), arms)
  for (arm in arms) {
    arm_effects <- effects[effects$intervention == arm, , drop = FALSE]
    interventions[[arm]] <- run_one_intervention_lifetable(
      population = population,
      mortality = mortality,
      morbidity = morbidity,
      effects = arm_effects,
      intervention = arm,
      horizon = horizon,
      spec = spec
    )
    comparisons[[arm]] <- compare_pmslt_results(bau, interventions[[arm]])
  }

  out <- list(
    bau = bau,
    interventions = interventions,
    comparisons = comparisons,
    effect_rule = "mortality_rate_Int = clamp(mortality_rate_BAU + sum(delta_mortality), 0, 1); morbidity_rate_Int = max(morbidity_rate_BAU + sum(delta_morbidity), 0)"
  )
  class(out) <- "pmslt_lifetable_interventions"
  out
}

#' Attach disease-attributable quantities to a BAU lifetable
#'
#' Adds deterministic disease-attributable cases, deaths, and YLDs beside the
#' all-cause business-as-usual lifetable. This first integration slice is
#' intentionally narrow: it does not subtract disease deaths from all-cause
#' deaths, apply interventions, apply PIFs, add costs, run PSA, or add equity
#' disaggregation.
#'
#' @param lifetable Data frame returned by [run_pmslt_lifetable_bau()].
#' @param disease_epi Data frame from [read_pmslt_disease_inputs()] or path to
#'   `pmslt_disease_epi.csv`.
#' @param stratum_rate_ratios Optional data frame or CSV path from
#'   `11_stratum_rate_ratios.csv`. When supplied, aggregate disease rates are
#'   disaggregated to lifetable strata before disease deltas are calculated.
#'
#' @details
#' Disease inputs are joined to the lifetable by `time_step`, `age`, `sex`, and
#' `stratum`. This helper uses the canonical `prevalence_initial` column as the
#' prevalence term for this single-year disease-delta slice, so
#' `prevalence_initial` must be present for every lifetable row being
#' integrated.
#'
#' The disease-specific long output is stored as the `disease_deltas` attribute
#' on the returned lifetable.
#'
#' @return A `pmslt_lifetable` data frame with `total_disease_cases`,
#'   `total_disease_deaths`, and `total_disease_yld` columns.
#' @export
integrate_disease_deltas <- function(lifetable, disease_epi, stratum_rate_ratios = NULL) {
  validate_disease_delta_lifetable(lifetable)
  disease_epi <- read_disease_delta_inputs(disease_epi)
  disease_epi <- validate_disease_delta_epi(disease_epi)

  keys <- c("time_step", "age", "sex", "stratum")
  lifetable_with_id <- lifetable
  lifetable_with_id$.pmslt_row_id <- seq_len(nrow(lifetable_with_id))
  if (!is.null(stratum_rate_ratios)) {
    disease_epi <- disaggregate_stratum_rates(
      disease_epi,
      stratum_rate_ratios,
      target_keys = unique(lifetable_with_id[keys[c(2, 3, 4)]]),
      spec = attr(lifetable, "spec", exact = TRUE),
      label = "disease_epi"
    )
  }

  validate_complete_disease_delta_join(lifetable_with_id, disease_epi, keys)
  long <- merge(
    lifetable_with_id[c(keys, "person_years", ".pmslt_row_id")],
    disease_epi[c(
      keys, "disease", "incidence_BAU", "prevalence_initial",
      "case_fatality_BAU", "disability_weight",
      lifetable_output_audit_columns(disease_epi)
    )],
    by = keys,
    all.x = TRUE,
    sort = FALSE
  )

  if (any(is.na(long$disease))) {
    stop("Disease inputs are missing rows for one or more lifetable rows.", call. = FALSE)
  }
  if (any(is.na(long$prevalence_initial))) {
    first <- long[is.na(long$prevalence_initial), ][1, , drop = FALSE]
    stop(
      "`prevalence_initial` must be supplied for every lifetable row in this first disease-delta slice. ",
      "First missing value is for age=", first$age[[1]],
      ", sex=", first$sex[[1]],
      ", stratum=", first$stratum[[1]],
      ", time_step=", first$time_step[[1]], ".",
      call. = FALSE
    )
  }

  long$disease_prevalence <- as.numeric(long$prevalence_initial)
  long$disease_cases <- long$person_years * long$incidence_BAU
  long$disease_deaths <- long$person_years * long$disease_prevalence * long$case_fatality_BAU
  long$disease_yld <- long$person_years * long$disease_prevalence * long$disability_weight
  validate_non_negative_disease_quantities(long)

  totals <- stats::aggregate(
    long[c("disease_cases", "disease_deaths", "disease_yld")],
    by = list(.pmslt_row_id = long$.pmslt_row_id),
    FUN = sum
  )
  names(totals)[names(totals) == "disease_cases"] <- "total_disease_cases"
  names(totals)[names(totals) == "disease_deaths"] <- "total_disease_deaths"
  names(totals)[names(totals) == "disease_yld"] <- "total_disease_yld"

  out <- merge(
    lifetable_with_id,
    totals,
    by = ".pmslt_row_id",
    all.x = TRUE,
    sort = FALSE
  )
  out <- out[order(out$.pmslt_row_id), , drop = FALSE]
  out$.pmslt_row_id <- NULL
  row.names(out) <- NULL
  class(out) <- class(lifetable)
  attr(out, "spec") <- attr(lifetable, "spec", exact = TRUE)
  attr(out, "ageing_rule") <- attr(lifetable, "ageing_rule", exact = TRUE)

  long <- long[order(long$.pmslt_row_id, long$disease), , drop = FALSE]
  long$.pmslt_row_id <- NULL
  row.names(long) <- NULL
  attr(out, "disease_deltas") <- long
  out
}

#' Summarise PMSLT lifetable results
#'
#' Creates beginner-friendly summary tables from BAU all-cause lifetable output
#' and from lifetables with attached disease-delta quantities. Summaries use the
#' package's exact single-year age internally. Use `"age_band"` to report ages
#' in the age bands stored in the `pmslt_spec` used to run the lifetable.
#'
#' @param results Output from [run_pmslt_lifetable_bau()] or
#'   [integrate_disease_deltas()].
#' @param by Character vector of grouping variables. Use `"overall"` for one
#'   ungrouped summary row, or any combination of `"time_step"`, `"sex"`,
#'   `"stratum"`, `"age"`, and `"age_band"`. Include `"disease"` to summarise
#'   the disease-specific long output stored by [integrate_disease_deltas()].
#' @param group_by Optional alias for `by`.
#'
#' @return A plain data frame with grouping columns followed by summary
#'   metrics.
#' @export
#'
#' @examples
#' population <- data.frame(
#'   age = c(40L, 41L),
#'   sex = "female",
#'   stratum = "total",
#'   population = c(1000, 900)
#' )
#' mortality <- data.frame(
#'   age = c(40L, 41L),
#'   sex = "female",
#'   stratum = "total",
#'   mortality_rate = c(0.01, 0.02)
#' )
#' spec <- pmslt_spec(
#'   intervention = "Example",
#'   mechanism = "direct",
#'   diseases = "CHD",
#'   ages = age_bands(40, 45, by = 3, open_ended = FALSE),
#'   sexes = "female",
#'   strata = "total",
#'   horizon = 1
#' )
#' bau <- run_pmslt_lifetable_bau(population, mortality, horizon = 1, spec = spec)
#' summarise_pmslt_results(bau)
#' summarise_pmslt_results(bau, by = "age")
#' summarise_pmslt_results(bau, by = "age_band")
summarise_pmslt_results <- function(results,
                                    by = c("overall", "time_step", "sex", "stratum", "age", "age_band", "disease"),
                                    group_by = NULL) {
  if (!is.null(group_by)) {
    if (!missing(by)) {
      stop("Use either `by` or `group_by`, not both.", call. = FALSE)
    }
    by <- group_by
  } else if (missing(by)) {
    by <- "overall"
  }
  if (!is.data.frame(results)) {
    stop("`results` must be a data frame returned by `run_pmslt_lifetable_bau()` or `integrate_disease_deltas()`.", call. = FALSE)
  }

  allowed <- c("overall", "time_step", "sex", "stratum", "age", "age_band", "disease")
  by <- as.character(by)
  bad <- setdiff(by, allowed)
  if (length(bad) > 0) {
    stop(
      "Unknown summary grouping variable: `", bad[[1]], "`. ",
      "Use one or more of: ", paste(allowed, collapse = ", "), ".",
      call. = FALSE
    )
  }
  if ("overall" %in% by && length(by) > 1) {
    stop("Use `by = \"overall\"` by itself, or choose specific grouping variables such as `time_step`, `sex`, `stratum`, `age`, `age_band`, or `disease`.", call. = FALSE)
  }

  if ("disease" %in% by) {
    return(summarise_disease_delta_results(results, by))
  }
  summarise_all_cause_results(results, by)
}

#' Compare intervention PMSLT results against BAU results
#'
#' Creates beginner-friendly intervention-minus-BAU summary tables from two
#' compatible PMSLT lifetable outputs. This is a reporting helper only: it does
#' not simulate an intervention or change the exact-age lifetable engine.
#'
#' @param bau_results BAU output from [run_pmslt_lifetable_bau()] or
#'   [integrate_disease_deltas()].
#' @param intervention_results Intervention output with the same `time_step`,
#'   `age`, `sex`, and `stratum` structure as `bau_results`.
#' @param by Character vector of grouping variables. Use `"overall"` for one
#'   ungrouped comparison row, or any combination of `"time_step"`, `"sex"`,
#'   `"stratum"`, `"age"`, and `"age_band"`.
#'
#' @return A plain data frame with grouping columns followed by difference
#'   metrics. Differences are calculated as `intervention - BAU`.
#' @export
#'
#' @examples
#' population <- data.frame(
#'   age = c(40L, 41L),
#'   sex = "female",
#'   stratum = "total",
#'   population = c(1000, 900)
#' )
#' mortality <- data.frame(
#'   age = c(40L, 41L),
#'   sex = "female",
#'   stratum = "total",
#'   mortality_rate = c(0.01, 0.02)
#' )
#' bau <- run_pmslt_lifetable_bau(population, mortality, horizon = 1)
#' compare_pmslt_results(bau, bau)
compare_pmslt_results <- function(bau_results,
                                  intervention_results,
                                  by = c("overall", "time_step", "sex", "stratum", "age", "age_band")) {
  by <- if (missing(by)) "overall" else as.character(by)
  validate_comparison_grouping(by)
  validate_pmslt_results_for_comparison(bau_results, "bau_results")
  validate_pmslt_results_for_comparison(intervention_results, "intervention_results")
  validate_comparison_structure(bau_results, intervention_results)
  validate_comparison_metrics(bau_results, intervention_results)

  bau_summary <- summarise_pmslt_results(bau_results, by = by)
  intervention_summary <- summarise_pmslt_results(intervention_results, by = by)
  compare_summary_tables(bau_summary, intervention_summary, by)
}

#' Calculate HALY-style health outcome summaries
#'
#' Creates a lightweight health-adjusted life-year style reporting summary from
#' existing PMSLT outputs. HALYs are calculated as `person_years - yld`. This is
#' a reporting helper only: it does not add discounting, age weighting, costs,
#' uncertainty intervals, DALYs, or change the lifetable engine.
#'
#' @param results Output from [run_pmslt_lifetable_bau()] or
#'   [integrate_disease_deltas()] with `person_years` and `yld` columns.
#' @param by Character vector of grouping variables. Use `"overall"` for one
#'   ungrouped summary row, or any combination of `"time_step"`, `"sex"`,
#'   `"stratum"`, `"age"`, and `"age_band"`.
#'
#' @return A plain data frame with grouping columns followed by `halys`,
#'   `person_years`, and `yld`. Integrated disease-total summary columns are
#'   preserved when they are available.
#' @export
#'
#' @examples
#' population <- data.frame(
#'   age = c(40L, 41L),
#'   sex = "female",
#'   stratum = "total",
#'   population = c(1000, 900)
#' )
#' mortality <- data.frame(
#'   age = c(40L, 41L),
#'   sex = "female",
#'   stratum = "total",
#'   mortality_rate = c(0.01, 0.02)
#' )
#' morbidity <- data.frame(
#'   age = c(40L, 41L),
#'   sex = "female",
#'   stratum = "total",
#'   morbidity_rate = c(0.12, 0.15)
#' )
#' bau <- run_pmslt_lifetable_bau(population, mortality, morbidity, horizon = 1)
#' calculate_halys(bau)
calculate_halys <- function(results,
                            by = c("overall", "time_step", "sex", "stratum", "age", "age_band")) {
  by <- if (missing(by)) "overall" else as.character(by)
  validate_comparison_grouping(by)
  validate_halys_input(results, "results")

  summary <- summarise_pmslt_results(results, by = by)
  require_haly_summary_metrics(summary, "results")
  add_haly_column(summary, by)
}

#' Compare HALY-style health outcome summaries
#'
#' Compares lightweight HALY summaries from compatible BAU and intervention
#' PMSLT outputs. Differences are calculated as `intervention - BAU`. This is a
#' reporting helper only and does not add discounting, age weighting, costs,
#' uncertainty intervals, DALYs, or change the lifetable engine.
#'
#' @param bau_results BAU output from [run_pmslt_lifetable_bau()] or
#'   [integrate_disease_deltas()] with `person_years` and `yld` columns.
#' @param intervention_results Intervention output with the same `time_step`,
#'   `age`, `sex`, and `stratum` structure as `bau_results`.
#' @param by Character vector of grouping variables. Use `"overall"` for one
#'   ungrouped comparison row, or any combination of `"time_step"`, `"sex"`,
#'   `"stratum"`, `"age"`, and `"age_band"`.
#'
#' @return A plain data frame with grouping columns followed by
#'   `haly_difference`, `person_years_difference`, and `yld_difference`.
#'   Integrated disease-total difference columns are included when both inputs
#'   include disease totals.
#' @export
#'
#' @examples
#' population <- data.frame(
#'   age = c(40L, 41L),
#'   sex = "female",
#'   stratum = "total",
#'   population = c(1000, 900)
#' )
#' mortality <- data.frame(
#'   age = c(40L, 41L),
#'   sex = "female",
#'   stratum = "total",
#'   mortality_rate = c(0.01, 0.02)
#' )
#' morbidity <- data.frame(
#'   age = c(40L, 41L),
#'   sex = "female",
#'   stratum = "total",
#'   morbidity_rate = c(0.12, 0.15)
#' )
#' bau <- run_pmslt_lifetable_bau(population, mortality, morbidity, horizon = 1)
#' compare_halys(bau, bau)
compare_halys <- function(bau_results,
                          intervention_results,
                          by = c("overall", "time_step", "sex", "stratum", "age", "age_band")) {
  by <- if (missing(by)) "overall" else as.character(by)
  validate_comparison_grouping(by)
  validate_pmslt_results_for_comparison(bau_results, "bau_results")
  validate_pmslt_results_for_comparison(intervention_results, "intervention_results")
  validate_halys_input(bau_results, "bau_results")
  validate_halys_input(intervention_results, "intervention_results")
  validate_comparison_structure(bau_results, intervention_results)
  validate_comparison_metrics(bau_results, intervention_results)

  bau_summary <- calculate_halys(bau_results, by = by)
  intervention_summary <- calculate_halys(intervention_results, by = by)
  out <- compare_summary_tables(bau_summary, intervention_summary, by)
  names(out)[names(out) == "halys_difference"] <- "haly_difference"
  out
}

read_lifetable_input <- function(x, label) {
  if (is.character(x) && length(x) == 1) {
    if (!file.exists(x)) {
      stop("Missing ", label, " file: ", x, call. = FALSE)
    }
    return(utils::read.csv(x, stringsAsFactors = FALSE, na.strings = c("", "NA")))
  }
  if (!is.data.frame(x)) {
    stop("`", label, "` must be a data frame or a CSV file path.", call. = FALSE)
  }
  x
}

normalize_lifetable_columns <- function(data, aliases, label) {
  for (target in names(aliases)) {
    alias <- unname(aliases[[target]])
    if (!target %in% names(data) && alias %in% names(data)) {
      names(data)[names(data) == alias] <- target
    }
  }
  data
}

validate_lifetable_table <- function(data, required, numeric_rules, label) {
  require_columns(data, required, label)
  validate_lifetable_age(data$age, label)

  for (column in names(numeric_rules)) {
    data[[column]] <- validate_lifetable_numeric(data[[column]], column, label)
    rule <- numeric_rules[[column]]
    if (identical(rule, "non_negative")) {
      if (any(data[[column]] < 0)) {
        stop("`", column, "` in ", label, " must be non-negative.", call. = FALSE)
      }
    } else if (identical(rule, "probability")) {
      if (any(data[[column]] < 0 | data[[column]] > 1)) {
        stop("`", column, "` in ", label, " must be between 0 and 1.", call. = FALSE)
      }
    }
  }

  invisible(TRUE)
}

validate_lifetable_age <- function(age, label) {
  value <- suppressWarnings(as.numeric(age))
  if (any(is.na(value))) {
    stop("`age` in ", label, " must be a non-missing whole-number single-year age.", call. = FALSE)
  }
  bad <- abs(value - round(value)) > .Machine$double.eps^0.5
  if (any(bad)) {
    stop("`age` in ", label, " must be a whole-number single-year age.", call. = FALSE)
  }
  invisible(TRUE)
}

validate_lifetable_numeric <- function(x, column, label) {
  value <- suppressWarnings(as.numeric(x))
  if (any(is.na(value))) {
    stop("`", column, "` in ", label, " must be numeric and non-missing.", call. = FALSE)
  }
  value
}

check_lifetable_keys <- function(data, keys, label) {
  data$age <- as.integer(as.numeric(data$age))
  data$sex <- as.character(data$sex)
  data$stratum <- as.character(data$stratum)
  missing_key <- !stats::complete.cases(data[keys])
  if (any(missing_key)) {
    stop("`", label, "` has missing age, sex, or stratum values.", call. = FALSE)
  }
  duplicated_key <- duplicated(data[keys])
  if (any(duplicated_key)) {
    stop(
      "`", label, "` must have only one row per age, sex, and stratum. First duplicate: ",
      format_lifetable_key(data[which(duplicated_key)[[1]], keys, drop = FALSE]),
      call. = FALSE
    )
  }
  data
}

check_complete_lifetable_join <- function(population, other, keys, label) {
  population_keys <- population[keys]
  other_keys <- other[keys]
  missing <- population_keys[!lifetable_key_in(population_keys, other_keys), , drop = FALSE]
  if (nrow(missing) > 0) {
    stop(
      "`", label, "` is missing rows for population keys. First missing key: ",
      format_lifetable_key(missing[1, , drop = FALSE]),
      call. = FALSE
    )
  }

  extra <- other_keys[!lifetable_key_in(other_keys, population_keys), , drop = FALSE]
  if (nrow(extra) > 0) {
    stop(
      "`", label, "` has rows that are not in population. First extra key: ",
      format_lifetable_key(extra[1, , drop = FALSE]),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

lifetable_key_in <- function(left, right) {
  paste(left$age, left$sex, left$stratum, sep = "\r") %in%
    paste(right$age, right$sex, right$stratum, sep = "\r")
}

format_lifetable_key <- function(data) {
  paste0(
    "age=", data$age[[1]],
    ", sex=", data$sex[[1]],
    ", stratum=", data$stratum[[1]]
  )
}

validate_lifetable_horizon <- function(horizon, spec) {
  if (is.null(horizon)) {
    horizon <- if (is.null(spec)) 1L else spec$horizon
  }
  value <- suppressWarnings(as.numeric(horizon))
  if (length(value) != 1 || is.na(value) || value <= 0 ||
      abs(value - round(value)) > .Machine$double.eps^0.5) {
    stop("`horizon` must be one positive whole number.", call. = FALSE)
  }
  as.integer(value)
}

prepare_lifetable_population <- function(population) {
  population <- read_lifetable_input(population, "population")
  population <- normalize_lifetable_columns(
    population,
    aliases = c(population = "initial_population"),
    label = "population"
  )
  validate_lifetable_table(
    population,
    required = c("age", "sex", "stratum", "population"),
    numeric_rules = list(population = "non_negative"),
    label = "population"
  )
  population$population <- as.numeric(population$population)
  check_lifetable_keys(population, c("age", "sex", "stratum"), "population")
}

prepare_lifetable_rates <- function(data, label, value_col, alias, rule) {
  data <- read_lifetable_input(data, label)
  data <- normalize_lifetable_columns(
    data,
    aliases = stats::setNames(alias, value_col),
    label = label
  )
  required <- c("age", "sex", "stratum", value_col)
  if ("time_step" %in% names(data)) {
    required <- c("time_step", required)
  }
  validate_lifetable_table(
    data,
    required = required,
    numeric_rules = stats::setNames(list(rule), value_col),
    label = label
  )
  data[[value_col]] <- as.numeric(data[[value_col]])
  data <- check_lifetable_keys(
    data,
    intersect(c("time_step", "age", "sex", "stratum"), names(data)),
    label
  )
  if ("time_step" %in% names(data)) {
    time_step <- suppressWarnings(as.numeric(data$time_step))
    if (any(is.na(time_step)) ||
        any(abs(time_step - round(time_step)) > .Machine$double.eps^0.5)) {
      stop("`time_step` in ", label, " must be whole numbers.", call. = FALSE)
    }
    data$time_step <- as.integer(time_step)
    if (any(data$time_step < 0)) {
      stop("`time_step` in ", label, " must be non-negative.", call. = FALSE)
    }
  }
  data
}

validate_consecutive_lifetable_ages <- function(population) {
  split_key <- paste(population$sex, population$stratum, sep = "\r")
  groups <- split(population, split_key)
  for (group in groups) {
    ages <- sort(unique(group$age))
    if (length(ages) > 1 && any(diff(ages) != 1L)) {
      stop(
        "`population` ages must be consecutive single-year ages within each sex and stratum. ",
        "First problem group: sex=", group$sex[[1]], ", stratum=", group$stratum[[1]], ".",
        call. = FALSE
      )
    }
  }
  invisible(TRUE)
}

validate_lifetable_rates_for_horizon <- function(population, rates, keys, horizon, label) {
  if (!"time_step" %in% names(rates)) {
    check_complete_lifetable_join(population, rates, keys, label)
    return(invisible(TRUE))
  }

  for (time_step in seq_len(horizon) - 1L) {
    cycle_rates <- rates[rates$time_step == time_step, , drop = FALSE]
    if (nrow(cycle_rates) == 0) {
      stop(
        "`", label, "` is missing all rows for time_step ", time_step, ".",
        call. = FALSE
      )
    }
    check_complete_lifetable_join(population, cycle_rates, keys, paste0(label, " at time_step ", time_step))
  }
  invisible(TRUE)
}

attach_lifetable_rate <- function(cycle, rates, value_col, label) {
  if ("time_step" %in% names(rates)) {
    cycle_rates <- rates[rates$time_step == cycle$time_step[[1]], , drop = FALSE]
    by_cols <- c("time_step", "age", "sex", "stratum")
  } else {
    cycle_rates <- rates
    by_cols <- c("age", "sex", "stratum")
  }
  rate_cols <- c(by_cols, value_col, lifetable_rate_audit_columns(cycle_rates, value_col))
  out <- merge(
    cycle,
    cycle_rates[rate_cols],
    by = by_cols,
    all.x = TRUE,
    sort = FALSE
  )
  if (any(is.na(out[[value_col]]))) {
    stop(
      "`", label, "` is missing a rate during lifetable simulation.",
      call. = FALSE
    )
  }
  out[order(out$sex, out$stratum, out$age), , drop = FALSE]
}

lifetable_rate_audit_columns <- function(data, value_col) {
  expected <- paste0(
    value_col,
    c("_original_aggregate", "_rate_ratio", "_rate_ratio_parameter", "_reference_stratum")
  )
  intersect(expected, names(data))
}

lifetable_output_audit_columns <- function(data) {
  grep(
    "_(original_aggregate|rate_ratio|rate_ratio_parameter|reference_stratum)$",
    names(data),
    value = TRUE
  )
}

age_lifetable_population <- function(cycle) {
  split_key <- paste(cycle$sex, cycle$stratum, sep = "\r")
  groups <- split(cycle, split_key)
  next_groups <- lapply(groups, age_one_lifetable_group)
  out <- do.call(rbind, next_groups)
  row.names(out) <- NULL
  out[order(out$sex, out$stratum, out$age), c("age", "sex", "stratum", "population")]
}

validate_disease_delta_lifetable <- function(lifetable) {
  if (!is.data.frame(lifetable)) {
    stop("`lifetable` must be the data frame returned by `run_pmslt_lifetable_bau()`.", call. = FALSE)
  }
  required <- c("time_step", "age", "sex", "stratum", "person_years")
  require_columns(lifetable, required, "lifetable")
  validate_lifetable_age(lifetable$age, "lifetable")
  person_years <- validate_lifetable_numeric(lifetable$person_years, "person_years", "lifetable")
  if (any(person_years < 0)) {
    stop("`person_years` in lifetable must be non-negative.", call. = FALSE)
  }
  time_step <- suppressWarnings(as.numeric(lifetable$time_step))
  if (any(is.na(time_step)) ||
      any(abs(time_step - round(time_step)) > .Machine$double.eps^0.5)) {
    stop("`time_step` in lifetable must contain non-missing whole numbers.", call. = FALSE)
  }
  if (any(!stats::complete.cases(lifetable[c("time_step", "age", "sex", "stratum")]))) {
    stop("`lifetable` has missing time_step, age, sex, or stratum values.", call. = FALSE)
  }
  invisible(TRUE)
}

summarise_all_cause_results <- function(results, by) {
  group_cols <- if (identical(by, "overall")) character() else by
  if ("age_band" %in% group_cols) {
    results <- attach_summary_age_band(results, results)
  }
  missing_groups <- setdiff(group_cols, names(results))
  if (length(missing_groups) > 0) {
    stop("Cannot summarise by `", missing_groups[[1]], "` because that column is not in `results`.", call. = FALSE)
  }

  metric_cols <- c("population", "deaths", "person_years")
  if ("yld" %in% names(results)) {
    metric_cols <- c(metric_cols, "yld")
  }
  disease_total_cols <- c("total_disease_cases", "total_disease_deaths", "total_disease_yld")
  if (all(disease_total_cols %in% names(results))) {
    metric_cols <- c(metric_cols, disease_total_cols)
  }
  cost_cols <- reporting_cost_columns(results)
  if (length(cost_cols) > 0) {
    metric_cols <- c(metric_cols, cost_cols)
  }
  require_summary_metrics(results, metric_cols, "results")
  summarise_numeric_columns(results, group_cols, metric_cols)
}

summarise_disease_delta_results <- function(results, by) {
  disease_deltas <- attr(results, "disease_deltas", exact = TRUE)
  if (!is.data.frame(disease_deltas)) {
    stop(
      "Disease-specific summaries need results from `integrate_disease_deltas()`. ",
      "Run `integrate_disease_deltas()` first, then summarise with `by` including `disease`.",
      call. = FALSE
    )
  }

  group_cols <- by
  if ("age_band" %in% group_cols) {
    disease_deltas <- attach_summary_age_band(disease_deltas, results)
  }
  missing_groups <- setdiff(group_cols, names(disease_deltas))
  if (length(missing_groups) > 0) {
    stop("Cannot summarise by `", missing_groups[[1]], "` because that column is not in the disease-delta output.", call. = FALSE)
  }
  metric_cols <- c("disease_cases", "disease_deaths", "disease_yld")
  require_summary_metrics(disease_deltas, metric_cols, "disease_deltas")
  summarise_numeric_columns(disease_deltas, group_cols, metric_cols)
}

attach_summary_age_band <- function(data, results) {
  age_table <- summary_age_table(results)
  require_columns(data, "age", "results")
  age <- suppressWarnings(as.numeric(data$age))
  if (any(is.na(age)) || any(abs(age - round(age)) > .Machine$double.eps^0.5)) {
    stop("Cannot summarise by `age_band` because `age` must contain exact whole-number ages.", call. = FALSE)
  }

  matched <- rep(NA_character_, length(age))
  for (i in seq_len(nrow(age_table))) {
    in_band <- age >= age_table$age_start[[i]] & age <= age_table$age_end[[i]]
    matched[in_band] <- age_table$age_label[[i]]
  }
  if (any(is.na(matched))) {
    first_age <- age[which(is.na(matched))[[1]]]
    stop(
      "Cannot summarise by `age_band` because age ", first_age,
      " is not covered by the age bands in `spec$ages`. ",
      "Update the `ages` argument in `pmslt_spec()` or summarise by exact `age`.",
      call. = FALSE
    )
  }

  data$age_band <- matched
  data
}

summary_age_table <- function(results) {
  spec <- attr(results, "spec", exact = TRUE)
  if (!inherits(spec, "pmslt_spec")) {
    stop(
      "Cannot summarise by `age_band` because `results` does not include age-band information. ",
      "Run the lifetable with `spec = pmslt_spec(..., ages = age_bands(...))`, ",
      "or summarise by exact `age`.",
      call. = FALSE
    )
  }
  age_table <- tryCatch(
    validate_age_table(spec$ages),
    error = function(e) {
      stop(
        "Cannot summarise by `age_band` because `spec$ages` is not a valid age-band table. ",
        "Use `age_bands()` or a data frame with age_start, age_end, and age_label.",
        call. = FALSE
      )
    }
  )
  if (nrow(age_table) == 0) {
    stop(
      "Cannot summarise by `age_band` because `spec$ages` has no age bands. ",
      "Use `age_bands()` when creating the `pmslt_spec()`.",
      call. = FALSE
    )
  }
  age_table$age_start <- suppressWarnings(as.numeric(age_table$age_start))
  age_table$age_end <- suppressWarnings(as.numeric(age_table$age_end))
  if (any(is.na(age_table$age_start)) || any(is.na(age_table$age_end))) {
    stop(
      "Cannot summarise by `age_band` because `spec$ages` has non-numeric age_start or age_end values. ",
      "Use `age_bands()` when creating the `pmslt_spec()`.",
      call. = FALSE
    )
  }
  age_table[order(age_table$age_start, age_table$age_end), , drop = FALSE]
}

require_summary_metrics <- function(data, metrics, label) {
  missing_metrics <- setdiff(metrics, names(data))
  if (length(missing_metrics) > 0) {
    stop("Cannot summarise `", label, "` because metric column `", missing_metrics[[1]], "` is missing.", call. = FALSE)
  }
  for (metric in metrics) {
    values <- suppressWarnings(as.numeric(data[[metric]]))
    if (any(is.na(values))) {
      stop("Cannot summarise metric `", metric, "` because it contains missing or non-numeric values.", call. = FALSE)
    }
  }
  invisible(TRUE)
}

summarise_numeric_columns <- function(data, group_cols, metric_cols) {
  for (metric in metric_cols) {
    data[[metric]] <- as.numeric(data[[metric]])
  }
  if (length(group_cols) == 0) {
    out <- as.data.frame(
      stats::setNames(as.list(colSums(data[metric_cols])), metric_cols),
      stringsAsFactors = FALSE
    )
  } else {
    out <- stats::aggregate(
      data[metric_cols],
      by = data[group_cols],
      FUN = sum
    )
  }
  out <- out[c(group_cols, metric_cols)]
  row.names(out) <- NULL
  as.data.frame(out, stringsAsFactors = FALSE)
}

validate_comparison_grouping <- function(by) {
  allowed <- c("overall", "time_step", "sex", "stratum", "age", "age_band")
  bad <- setdiff(by, allowed)
  if (length(bad) > 0) {
    stop(
      "Unknown comparison grouping variable: `", bad[[1]], "`. ",
      "Use one or more of: ", paste(allowed, collapse = ", "), ".",
      call. = FALSE
    )
  }
  if ("overall" %in% by && length(by) > 1) {
    stop("Use `by = \"overall\"` by itself, or choose specific grouping variables such as `time_step`, `sex`, `stratum`, `age`, or `age_band`.", call. = FALSE)
  }
  invisible(TRUE)
}

validate_pmslt_results_for_comparison <- function(results, label) {
  if (!is.data.frame(results) || !inherits(results, "pmslt_lifetable")) {
    stop(
      "`", label, "` must be a PMSLT result returned by `run_pmslt_lifetable_bau()` ",
      "or `integrate_disease_deltas()`.",
      call. = FALSE
    )
  }
  required <- c("time_step", "age", "sex", "stratum", "population", "deaths", "person_years")
  require_columns(results, required, label)
  validate_lifetable_age(results$age, label)
  time_step <- suppressWarnings(as.numeric(results$time_step))
  if (any(is.na(time_step)) ||
      any(abs(time_step - round(time_step)) > .Machine$double.eps^0.5)) {
    stop("`time_step` in `", label, "` must contain non-missing whole numbers.", call. = FALSE)
  }
  if (any(!stats::complete.cases(results[c("time_step", "age", "sex", "stratum")]))) {
    stop("`", label, "` has missing time_step, age, sex, or stratum values.", call. = FALSE)
  }
  duplicate_key <- duplicated(results[c("time_step", "age", "sex", "stratum")])
  if (any(duplicate_key)) {
    first <- results[which(duplicate_key)[[1]], c("time_step", "age", "sex", "stratum"), drop = FALSE]
    stop(
      "`", label, "` must have only one row per time_step, age, sex, and stratum. ",
      "First duplicate: age=", first$age[[1]],
      ", sex=", first$sex[[1]],
      ", stratum=", first$stratum[[1]],
      ", time_step=", first$time_step[[1]], ".",
      call. = FALSE
    )
  }
  metric_cols <- intersect(
    c("population", "deaths", "person_years", "yld", "total_disease_cases", "total_disease_deaths", "total_disease_yld"),
    names(results)
  )
  metric_cols <- c(metric_cols, reporting_cost_columns(results))
  require_summary_metrics(results, metric_cols, label)
  invisible(TRUE)
}

validate_comparison_structure <- function(bau_results, intervention_results) {
  keys <- c("time_step", "age", "sex", "stratum")
  bau_keys <- comparison_key_values(bau_results, keys)
  intervention_keys <- comparison_key_values(intervention_results, keys)
  missing_in_intervention <- bau_results[!bau_keys %in% intervention_keys, keys, drop = FALSE]
  if (nrow(missing_in_intervention) > 0) {
    stop(
      "`intervention_results` is missing a row found in `bau_results`. First missing key: ",
      format_comparison_key(missing_in_intervention[1, , drop = FALSE]),
      call. = FALSE
    )
  }
  extra_in_intervention <- intervention_results[!intervention_keys %in% bau_keys, keys, drop = FALSE]
  if (nrow(extra_in_intervention) > 0) {
    stop(
      "`intervention_results` has a row that is not in `bau_results`. First extra key: ",
      format_comparison_key(extra_in_intervention[1, , drop = FALSE]),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

validate_comparison_metrics <- function(bau_results, intervention_results) {
  optional_metrics <- c("yld", "total_disease_cases", "total_disease_deaths", "total_disease_yld")
  optional_metrics <- unique(c(optional_metrics, reporting_cost_columns(bau_results), reporting_cost_columns(intervention_results)))
  for (metric in optional_metrics) {
    in_bau <- metric %in% names(bau_results)
    in_intervention <- metric %in% names(intervention_results)
    if (!identical(in_bau, in_intervention)) {
      stop(
        "Cannot compare `", metric, "` because it is present in only one result. ",
        "Compare two BAU-style results or two results after the same reporting integration step.",
        call. = FALSE
      )
    }
  }
  invisible(TRUE)
}

validate_halys_input <- function(results, label) {
  if (!is.data.frame(results)) {
    stop(
      "`", label, "` must be a PMSLT result with `person_years` and `yld` columns.",
      call. = FALSE
    )
  }
  if (!"person_years" %in% names(results)) {
    stop(
      "Cannot calculate HALYs for `", label, "` because `person_years` is missing. ",
      "Use PMSLT lifetable output from `run_pmslt_lifetable_bau()` or `integrate_disease_deltas()`.",
      call. = FALSE
    )
  }
  if (!"yld" %in% names(results)) {
    stop(
      "Cannot calculate HALYs for `", label, "` because `yld` is missing. ",
      "HALYs are calculated as `person_years - yld`, so use PMSLT output that includes a `yld` column.",
      call. = FALSE
    )
  }
  require_summary_metrics(results, c("person_years", "yld"), label)
  invisible(TRUE)
}

require_haly_summary_metrics <- function(summary, label) {
  missing_metrics <- setdiff(c("person_years", "yld"), names(summary))
  if (length(missing_metrics) > 0) {
    stop(
      "Cannot calculate HALYs for `", label, "` because summary metric `",
      missing_metrics[[1]], "` is missing.",
      call. = FALSE
    )
  }
  require_summary_metrics(summary, c("person_years", "yld"), label)
  invisible(TRUE)
}

add_haly_column <- function(summary, by) {
  group_cols <- if (identical(by, "overall")) character() else by
  disease_total_cols <- intersect(
    c("total_disease_cases", "total_disease_deaths", "total_disease_yld"),
    names(summary)
  )

  summary$halys <- as.numeric(summary$person_years) - as.numeric(summary$yld)
  out_cols <- c(group_cols, "halys", "person_years", "yld", disease_total_cols)
  out <- summary[out_cols]
  row.names(out) <- NULL
  as.data.frame(out, stringsAsFactors = FALSE)
}

comparison_key_values <- function(data, keys) {
  do.call(paste, c(data[keys], sep = "\r"))
}

format_comparison_key <- function(data) {
  paste0(
    "age=", data$age[[1]],
    ", sex=", data$sex[[1]],
    ", stratum=", data$stratum[[1]],
    ", time_step=", data$time_step[[1]]
  )
}

compare_summary_tables <- function(bau_summary, intervention_summary, by) {
  group_cols <- if (identical(by, "overall")) character() else by
  metric_cols <- setdiff(names(bau_summary), group_cols)
  if (!identical(names(bau_summary), names(intervention_summary))) {
    stop("Cannot compare summaries because BAU and intervention summaries have different metric columns.", call. = FALSE)
  }
  if (length(group_cols) > 0) {
    bau_summary$.pmslt_group_key <- comparison_key_values(bau_summary, group_cols)
    intervention_summary$.pmslt_group_key <- comparison_key_values(intervention_summary, group_cols)
    missing_groups <- bau_summary[!bau_summary$.pmslt_group_key %in% intervention_summary$.pmslt_group_key, group_cols, drop = FALSE]
    if (nrow(missing_groups) > 0) {
      stop("Cannot compare summaries because an intervention summary group is missing.", call. = FALSE)
    }
    extra_groups <- intervention_summary[!intervention_summary$.pmslt_group_key %in% bau_summary$.pmslt_group_key, group_cols, drop = FALSE]
    if (nrow(extra_groups) > 0) {
      stop("Cannot compare summaries because an intervention summary group is not present in BAU.", call. = FALSE)
    }
    intervention_summary <- intervention_summary[
      match(bau_summary$.pmslt_group_key, intervention_summary$.pmslt_group_key),
      ,
      drop = FALSE
    ]
    bau_summary$.pmslt_group_key <- NULL
    intervention_summary$.pmslt_group_key <- NULL
  }

  out <- bau_summary[group_cols]
  for (metric in metric_cols) {
    out[[paste0(metric, "_difference")]] <-
      as.numeric(intervention_summary[[metric]]) - as.numeric(bau_summary[[metric]])
  }
  row.names(out) <- NULL
  as.data.frame(out, stringsAsFactors = FALSE)
}

prepare_lifetable_intervention_effects <- function(intervention_effects) {
  effects <- read_lifetable_input(intervention_effects, "intervention_effects")
  required <- c(
    "intervention", "time_step", "age", "sex", "stratum", "disease",
    "incidence_BAU", "incidence_Int",
    "disease_mortality_BAU", "disease_mortality_Int",
    "disease_morbidity_BAU", "disease_morbidity_Int",
    "delta_mortality", "delta_morbidity"
  )
  require_columns(effects, required, "intervention_effects")
  validate_lifetable_age(effects$age, "intervention_effects")

  effects$intervention <- as.character(effects$intervention)
  effects$time_step <- suppressWarnings(as.numeric(effects$time_step))
  if (any(is.na(effects$time_step)) ||
      any(abs(effects$time_step - round(effects$time_step)) > .Machine$double.eps^0.5)) {
    stop("`time_step` in intervention_effects must contain whole numbers.", call. = FALSE)
  }
  effects$time_step <- as.integer(effects$time_step)
  effects$age <- as.integer(as.numeric(effects$age))
  effects$sex <- as.character(effects$sex)
  effects$stratum <- as.character(effects$stratum)
  effects$disease <- as.character(effects$disease)

  if (any(is.na(effects$intervention) | !nzchar(effects$intervention))) {
    stop("`intervention_effects` must include non-empty intervention names.", call. = FALSE)
  }
  key_cols <- c("intervention", "time_step", "age", "sex", "stratum", "disease")
  if (any(!stats::complete.cases(effects[key_cols]))) {
    stop("`intervention_effects` has missing intervention, time_step, age, sex, stratum, or disease values.", call. = FALSE)
  }
  duplicated_row <- duplicated(effects[key_cols])
  if (any(duplicated_row)) {
    first <- effects[which(duplicated_row)[[1]], key_cols, drop = FALSE]
    stop(
      "`intervention_effects` must have one row per intervention, disease, time_step, age, sex, and stratum. ",
      "First duplicate: intervention=", first$intervention[[1]],
      ", disease=", first$disease[[1]],
      ", age=", first$age[[1]],
      ", sex=", first$sex[[1]],
      ", stratum=", first$stratum[[1]],
      ", time_step=", first$time_step[[1]], ".",
      call. = FALSE
    )
  }

  numeric_cols <- c(
    "incidence_BAU", "incidence_Int",
    "disease_mortality_BAU", "disease_mortality_Int",
    "disease_morbidity_BAU", "disease_morbidity_Int",
    "delta_mortality", "delta_morbidity"
  )
  for (col in numeric_cols) {
    effects[[col]] <- suppressWarnings(as.numeric(effects[[col]]))
    if (any(is.na(effects[[col]]))) {
      stop("`", col, "` in intervention_effects must be numeric and non-missing.", call. = FALSE)
    }
  }

  non_negative_cols <- c(
    "incidence_BAU", "incidence_Int",
    "disease_mortality_BAU", "disease_mortality_Int",
    "disease_morbidity_BAU", "disease_morbidity_Int"
  )
  for (col in non_negative_cols) {
    if (any(effects[[col]] < 0)) {
      stop("`", col, "` in intervention_effects must be non-negative.", call. = FALSE)
    }
  }
  effects
}

first_intervention_effects <- function(effects) {
  effects[effects$intervention == effects$intervention[[1]], , drop = FALSE]
}

run_one_intervention_lifetable <- function(population,
                                           mortality,
                                           morbidity,
                                           effects,
                                           intervention,
                                           horizon,
                                           spec) {
  delta_rates <- aggregate_intervention_delta_rates(effects)
  validate_intervention_effect_join(population, delta_rates, horizon, intervention)

  current_population <- population[c("age", "sex", "stratum")]
  current_population$population <- population$population
  rows <- vector("list", horizon)
  for (time_step in seq_len(horizon) - 1L) {
    cycle <- current_population
    cycle$time_step <- time_step
    cycle <- attach_lifetable_rate(cycle, mortality, "mortality_rate", "mortality")
    if (is.null(morbidity)) {
      cycle$morbidity_rate <- 0
    } else {
      cycle <- attach_lifetable_rate(cycle, morbidity, "morbidity_rate", "morbidity")
    }
    cycle <- attach_intervention_delta_rates(cycle, delta_rates, intervention)
    cycle$mortality_rate_BAU <- cycle$mortality_rate
    cycle$morbidity_rate_BAU <- cycle$morbidity_rate
    cycle$mortality_rate <- pmin(1, pmax(0, cycle$mortality_rate_BAU + cycle$total_delta_mortality))
    cycle$morbidity_rate <- pmax(0, cycle$morbidity_rate_BAU + cycle$total_delta_morbidity)
    cycle$deaths <- cycle$population * cycle$mortality_rate
    cycle$alive_end <- cycle$population - cycle$deaths
    cycle$person_years <- cycle$population - 0.5 * cycle$deaths
    cycle$yld_rate <- cycle$morbidity_rate
    cycle$yld <- cycle$person_years * cycle$morbidity_rate
    cycle$intervention <- intervention
    rows[[time_step + 1L]] <- cycle[c(
      "intervention", "time_step", "age", "sex", "stratum", "population",
      "mortality_rate_BAU", "total_delta_mortality", "mortality_rate",
      "deaths", "alive_end", "person_years",
      "morbidity_rate_BAU", "total_delta_morbidity", "morbidity_rate",
      "yld_rate", "yld"
    )]

    if (time_step < horizon - 1L) {
      current_population <- age_lifetable_population(cycle)
    }
  }

  out <- do.call(rbind, rows)
  row.names(out) <- NULL
  class(out) <- c("pmslt_lifetable", "data.frame")
  attr(out, "spec") <- spec
  attr(out, "ageing_rule") <- "open_ended_max_age"
  out <- attach_lifetable_disease_output(
    lifetable = out,
    effects = effects,
    scenario = intervention,
    use_intervention = TRUE
  )
  out
}

aggregate_intervention_delta_rates <- function(effects) {
  totals <- stats::aggregate(
    effects[c("delta_mortality", "delta_morbidity")],
    by = effects[c("intervention", "time_step", "age", "sex", "stratum")],
    FUN = sum
  )
  names(totals)[names(totals) == "delta_mortality"] <- "total_delta_mortality"
  names(totals)[names(totals) == "delta_morbidity"] <- "total_delta_morbidity"
  row.names(totals) <- NULL
  totals
}

validate_intervention_effect_join <- function(population, delta_rates, horizon, intervention) {
  keys <- c("age", "sex", "stratum")
  for (time_step in seq_len(horizon) - 1L) {
    cycle_rates <- delta_rates[delta_rates$time_step == time_step, , drop = FALSE]
    if (nrow(cycle_rates) == 0) {
      stop(
        "`intervention_effects` is missing all rows for intervention `",
        intervention,
        "` at time_step ",
        time_step,
        ".",
        call. = FALSE
      )
    }
    check_complete_lifetable_join(
      population,
      cycle_rates,
      keys,
      paste0("intervention_effects for `", intervention, "` at time_step ", time_step)
    )
  }
  invisible(TRUE)
}

attach_intervention_delta_rates <- function(cycle, delta_rates, intervention) {
  by_cols <- c("intervention", "time_step", "age", "sex", "stratum")
  cycle$intervention <- intervention
  out <- merge(
    cycle,
    delta_rates[c(by_cols, "total_delta_mortality", "total_delta_morbidity")],
    by = by_cols,
    all.x = TRUE,
    sort = FALSE
  )
  if (any(is.na(out$total_delta_mortality)) || any(is.na(out$total_delta_morbidity))) {
    stop("`intervention_effects` is missing a disease-delta rate during lifetable simulation.", call. = FALSE)
  }
  out[order(out$sex, out$stratum, out$age), , drop = FALSE]
}

attach_lifetable_disease_output <- function(lifetable, effects, scenario, use_intervention) {
  validate_disease_delta_lifetable(lifetable)
  required_cols <- c("time_step", "age", "sex", "stratum", "person_years", ".pmslt_row_id")
  lifetable_with_id <- lifetable
  lifetable_with_id$.pmslt_row_id <- seq_len(nrow(lifetable_with_id))
  effect_long <- effects
  if (isTRUE(use_intervention)) {
    effect_long$disease_cases <- effect_long$incidence_Int
    effect_long$disease_deaths <- effect_long$disease_mortality_Int
    effect_long$disease_yld <- effect_long$disease_morbidity_Int
  } else {
    effect_long$disease_cases <- effect_long$incidence_BAU
    effect_long$disease_deaths <- effect_long$disease_mortality_BAU
    effect_long$disease_yld <- effect_long$disease_morbidity_BAU
  }

  # Carry disease prevalence (a proportion) through when the upstream disease
  # lifetable provides it, so downstream costing can derive prevalent cases. The
  # scenario-appropriate column is used; it is left absent if not supplied.
  has_prevalence <- all(c("prevalence_BAU", "prevalence_Int") %in% names(effect_long))
  if (has_prevalence) {
    effect_long$disease_prevalence <- if (isTRUE(use_intervention)) {
      effect_long$prevalence_Int
    } else {
      effect_long$prevalence_BAU
    }
  }

  keys <- c("time_step", "age", "sex", "stratum")
  validate_complete_intervention_disease_join(lifetable_with_id, effect_long, keys, scenario)
  long <- merge(
    lifetable_with_id[required_cols],
    effect_long[c(
      keys, "intervention", "disease",
      "incidence_BAU", "incidence_Int",
      "disease_mortality_BAU", "disease_mortality_Int",
      "disease_morbidity_BAU", "disease_morbidity_Int",
      "delta_mortality", "delta_morbidity",
      "disease_cases", "disease_deaths", "disease_yld",
      if (has_prevalence) "disease_prevalence" else NULL
    )],
    by = keys,
    all.x = TRUE,
    sort = FALSE
  )
  long$scenario <- scenario
  long$disease_cases <- long$person_years * long$disease_cases
  long$disease_deaths <- long$person_years * long$disease_deaths
  long$disease_yld <- long$person_years * long$disease_yld
  validate_non_negative_disease_quantities(long)

  totals <- stats::aggregate(
    long[c("disease_cases", "disease_deaths", "disease_yld")],
    by = list(.pmslt_row_id = long$.pmslt_row_id),
    FUN = sum
  )
  names(totals)[names(totals) == "disease_cases"] <- "total_disease_cases"
  names(totals)[names(totals) == "disease_deaths"] <- "total_disease_deaths"
  names(totals)[names(totals) == "disease_yld"] <- "total_disease_yld"

  out <- merge(
    lifetable_with_id,
    totals,
    by = ".pmslt_row_id",
    all.x = TRUE,
    sort = FALSE
  )
  out <- out[order(out$.pmslt_row_id), , drop = FALSE]
  out$.pmslt_row_id <- NULL
  row.names(out) <- NULL
  class(out) <- class(lifetable)
  attr(out, "spec") <- attr(lifetable, "spec", exact = TRUE)
  attr(out, "ageing_rule") <- attr(lifetable, "ageing_rule", exact = TRUE)

  long <- long[order(long$.pmslt_row_id, long$disease), , drop = FALSE]
  long$.pmslt_row_id <- NULL
  row.names(long) <- NULL
  attr(out, "disease_deltas") <- long
  out
}

validate_complete_intervention_disease_join <- function(lifetable, effects, keys, scenario) {
  lifetable_keys <- unique(lifetable[keys])
  effect_keys <- unique(effects[keys])
  missing <- lifetable_keys[!disease_delta_key_in(lifetable_keys, effect_keys, keys), , drop = FALSE]
  if (nrow(missing) > 0) {
    first <- missing[1, , drop = FALSE]
    stop(
      "`intervention_effects` is missing disease rows for scenario `",
      scenario,
      "`. First missing lifetable key: age=",
      first$age[[1]],
      ", sex=",
      first$sex[[1]],
      ", stratum=",
      first$stratum[[1]],
      ", time_step=",
      first$time_step[[1]],
      ".",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

read_disease_delta_inputs <- function(disease_epi) {
  if (is.character(disease_epi) && length(disease_epi) == 1) {
    return(read_pmslt_disease_inputs(disease_epi))
  }
  if (!is.data.frame(disease_epi)) {
    stop("`disease_epi` must be a data frame or a CSV path to pmslt_disease_epi.csv.", call. = FALSE)
  }
  validate_pmslt_disease_inputs(disease_epi)
  disease_epi
}

validate_disease_delta_epi <- function(disease_epi) {
  keys <- c("time_step", "age", "sex", "stratum", "disease")
  if (any(!stats::complete.cases(disease_epi[keys]))) {
    stop("`disease_epi` has missing time_step, age, sex, stratum, or disease values.", call. = FALSE)
  }
  disease_epi$time_step <- as.integer(as.numeric(disease_epi$time_step))
  disease_epi$age <- as.integer(as.numeric(disease_epi$age))
  disease_epi$sex <- as.character(disease_epi$sex)
  disease_epi$stratum <- as.character(disease_epi$stratum)
  disease_epi$disease <- as.character(disease_epi$disease)

  duplicated_row <- duplicated(disease_epi[keys])
  if (any(duplicated_row)) {
    first <- disease_epi[which(duplicated_row)[[1]], keys, drop = FALSE]
    stop(
      "`disease_epi` must have one row per disease, time_step, age, sex, and stratum. ",
      "First duplicate: disease=", first$disease[[1]],
      ", age=", first$age[[1]],
      ", sex=", first$sex[[1]],
      ", stratum=", first$stratum[[1]],
      ", time_step=", first$time_step[[1]], ".",
      call. = FALSE
    )
  }

  value_cols <- c("incidence_BAU", "prevalence_initial", "case_fatality_BAU", "disability_weight")
  for (col in value_cols) {
    disease_epi[[col]] <- suppressWarnings(as.numeric(disease_epi[[col]]))
  }
  disease_epi
}

validate_complete_disease_delta_join <- function(lifetable, disease_epi, keys) {
  lifetable_keys <- unique(lifetable[keys])
  disease_keys <- unique(disease_epi[keys])
  missing <- lifetable_keys[!disease_delta_key_in(lifetable_keys, disease_keys, keys), , drop = FALSE]
  if (nrow(missing) > 0) {
    first <- missing[1, , drop = FALSE]
    stop(
      "`disease_epi` is missing disease rows for a lifetable row. First missing key: ",
      "age=", first$age[[1]],
      ", sex=", first$sex[[1]],
      ", stratum=", first$stratum[[1]],
      ", time_step=", first$time_step[[1]], ".",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

disease_delta_key_in <- function(left, right, keys) {
  do.call(paste, c(left[keys], sep = "\r")) %in%
    do.call(paste, c(right[keys], sep = "\r"))
}

validate_non_negative_disease_quantities <- function(long) {
  quantity_cols <- c("disease_cases", "disease_deaths", "disease_yld")
  for (col in quantity_cols) {
    if (any(is.na(long[[col]]))) {
      stop("Disease quantity `", col, "` could not be calculated because an input value is missing.", call. = FALSE)
    }
    if (any(long[[col]] < 0)) {
      stop("Disease quantity `", col, "` must be non-negative.", call. = FALSE)
    }
  }
  invisible(TRUE)
}

age_one_lifetable_group <- function(group) {
  group <- group[order(group$age), , drop = FALSE]
  ages <- group$age
  next_population <- numeric(length(ages))
  if (length(ages) > 1) {
    next_population[-1] <- group$alive_end[-length(ages)]
  }
  next_population[length(ages)] <- next_population[length(ages)] + group$alive_end[length(ages)]

  data.frame(
    age = ages,
    sex = group$sex[[1]],
    stratum = group$stratum[[1]],
    population = next_population,
    stringsAsFactors = FALSE
  )
}
