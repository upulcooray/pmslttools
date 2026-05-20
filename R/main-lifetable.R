#' Initialize a one-step PMSLT all-cause lifetable
#'
#' Creates the business-as-usual starting state for the main all-cause PMSLT
#' lifetable. This first slice only runs one deterministic time step. It does
#' not age the population forward, apply disease deltas, model interventions,
#' add costs, or run PSA.
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
                                       spec = NULL) {
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
  mortality <- check_lifetable_keys(mortality, keys, "mortality")
  check_complete_lifetable_join(population, mortality, keys, "mortality")

  population$.pmslt_row_id <- seq_len(nrow(population))
  out <- merge(
    population[c(keys, "population", ".pmslt_row_id")],
    mortality[c(keys, "mortality_rate")],
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
    morbidity <- check_lifetable_keys(morbidity, keys, "morbidity")
    check_complete_lifetable_join(population, morbidity, keys, "morbidity")
    out <- merge(
      out,
      morbidity[c(keys, "morbidity_rate")],
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

  out <- out[c(
    "time_step", "age", "sex", "stratum", "population",
    "mortality_rate", "deaths", "alive_end", "person_years",
    "morbidity_rate", "yld_rate"
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
#' deltas, intervention effects, costs, equity disaggregation, or PSA.
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
                                    spec = NULL) {
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
      "morbidity_rate", "yld_rate", "yld"
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
integrate_disease_deltas <- function(lifetable, disease_epi) {
  validate_disease_delta_lifetable(lifetable)
  disease_epi <- read_disease_delta_inputs(disease_epi)
  disease_epi <- validate_disease_delta_epi(disease_epi)

  keys <- c("time_step", "age", "sex", "stratum")
  lifetable_with_id <- lifetable
  lifetable_with_id$.pmslt_row_id <- seq_len(nrow(lifetable_with_id))

  validate_complete_disease_delta_join(lifetable_with_id, disease_epi, keys)
  long <- merge(
    lifetable_with_id[c(keys, "person_years", ".pmslt_row_id")],
    disease_epi[c(
      keys, "disease", "incidence_BAU", "prevalence_initial",
      "case_fatality_BAU", "disability_weight"
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
#' package's exact single-year age internally; age-band reporting is a later
#' layer and is not applied here.
#'
#' @param results Output from [run_pmslt_lifetable_bau()] or
#'   [integrate_disease_deltas()].
#' @param by Character vector of grouping variables. Use `"overall"` for one
#'   ungrouped summary row, or any combination of `"time_step"`, `"sex"`,
#'   `"stratum"`, and `"age"`. Include `"disease"` to summarise the
#'   disease-specific long output stored by [integrate_disease_deltas()].
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
#' bau <- run_pmslt_lifetable_bau(population, mortality, horizon = 1)
#' summarise_pmslt_results(bau)
#' summarise_pmslt_results(bau, by = "age")
summarise_pmslt_results <- function(results,
                                    by = c("overall", "time_step", "sex", "stratum", "age", "disease")) {
  if (missing(by)) {
    by <- "overall"
  }
  if (!is.data.frame(results)) {
    stop("`results` must be a data frame returned by `run_pmslt_lifetable_bau()` or `integrate_disease_deltas()`.", call. = FALSE)
  }

  allowed <- c("overall", "time_step", "sex", "stratum", "age", "disease")
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
    stop("Use `by = \"overall\"` by itself, or choose specific grouping variables such as `time_step`, `sex`, `stratum`, `age`, or `disease`.", call. = FALSE)
  }

  if ("disease" %in% by) {
    return(summarise_disease_delta_results(results, by))
  }
  summarise_all_cause_results(results, by)
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
  out <- merge(
    cycle,
    cycle_rates[c(by_cols, value_col)],
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
  missing_groups <- setdiff(group_cols, names(disease_deltas))
  if (length(missing_groups) > 0) {
    stop("Cannot summarise by `", missing_groups[[1]], "` because that column is not in the disease-delta output.", call. = FALSE)
  }
  metric_cols <- c("disease_cases", "disease_deaths", "disease_yld")
  require_summary_metrics(disease_deltas, metric_cols, "disease_deltas")
  summarise_numeric_columns(disease_deltas, group_cols, metric_cols)
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
