#' Read PMSLT-ready disease epidemiology inputs
#'
#' Reads the post-DisMod disease epidemiology file used by downstream PMSLT
#' disease lifetable modules. This is the canonical disease input after DisMod
#' processing, not the raw `05_disease_epidemiology_raw.csv` file.
#'
#' @param path CSV path. Defaults to `pmslt_disease_epi.csv`.
#' @param validate Logical. Should required columns and basic values be checked?
#'
#' @return A data frame containing PMSLT-ready disease epidemiology inputs.
#' @export
read_pmslt_disease_inputs <- function(path = "pmslt_disease_epi.csv",
                                      validate = TRUE) {
  if (!file.exists(path)) {
    stop("Missing PMSLT-ready disease input file: ", path, call. = FALSE)
  }
  data <- utils::read.csv(path, stringsAsFactors = FALSE, na.strings = c("", "NA"))
  if (isTRUE(validate)) {
    validate_pmslt_disease_inputs(data)
  }
  data
}

#' Validate PMSLT-ready disease epidemiology inputs
#'
#' Checks the post-DisMod disease input structure expected by downstream PMSLT
#' disease modules.
#'
#' @param data Data frame, usually read from `pmslt_disease_epi.csv`.
#'
#' @return Invisibly returns `TRUE` if valid.
#' @export
validate_pmslt_disease_inputs <- function(data) {
  required <- c(
    "age_start", "age_end", "age_label", "sex", "stratum", "disease",
    "time_step", "incidence_BAU", "prevalence_initial", "remission_rate",
    "excess_mortality_BAU", "case_fatality_BAU", "disability_weight"
  )
  require_columns(data, required, "pmslt_disease_epi.csv")

  numeric_cols <- c(
    "age_start", "age_end", "time_step", "incidence_BAU",
    "prevalence_initial", "remission_rate", "excess_mortality_BAU",
    "case_fatality_BAU", "disability_weight"
  )
  for (col in numeric_cols) {
    data[[col]] <- as.numeric(data[[col]])
  }

  non_negative_cols <- c(
    "incidence_BAU", "remission_rate", "excess_mortality_BAU",
    "case_fatality_BAU", "disability_weight"
  )
  for (col in non_negative_cols) {
    bad <- !is.na(data[[col]]) & data[[col]] < 0
    if (any(bad)) {
      stop("`", col, "` must be non-negative in pmslt_disease_epi.csv.", call. = FALSE)
    }
  }

  prev <- data$prevalence_initial
  if (any(!is.na(prev) & (prev < 0 | prev > 1))) {
    stop("`prevalence_initial` must be between 0 and 1 when supplied.", call. = FALSE)
  }
  if (any(!is.na(data$disability_weight) & data$disability_weight > 1)) {
    stop("`disability_weight` should be between 0 and 1.", call. = FALSE)
  }

  keys <- unique(data[c("age_start", "sex", "stratum", "disease")])
  missing_initial <- vapply(seq_len(nrow(keys)), function(i) {
    rows <- data[
      data$age_start == keys$age_start[[i]] &
        data$sex == keys$sex[[i]] &
        data$stratum == keys$stratum[[i]] &
        data$disease == keys$disease[[i]] &
        data$time_step == 0,
      ,
      drop = FALSE
    ]
    nrow(rows) == 0 || all(is.na(rows$prevalence_initial))
  }, logical(1))
  if (any(missing_initial)) {
    stop("Every age/sex/stratum/disease group must have `prevalence_initial` at time_step 0.", call. = FALSE)
  }

  invisible(TRUE)
}

#' Run a PMSLT disease lifetable from post-DisMod inputs
#'
#' This is the first downstream module after DisMod. It consumes
#' `pmslt_disease_epi.csv` directly and returns disease-specific mortality,
#' morbidity, and intervention deltas. It is intentionally narrow: main
#' all-cause lifetable integration is a later module.
#'
#' @param disease_epi Data frame from [read_pmslt_disease_inputs()] or path to
#'   `pmslt_disease_epi.csv`.
#' @param pif_data Optional data frame with `age_start`, `sex`, `stratum`,
#'   `disease`, `time_step`, and `pif`. If omitted, intervention equals BAU.
#' @param cohort_size Radix cohort size for each disease lifetable.
#'
#' @return A data frame with BAU/intervention disease lifetable outputs and
#'   deltas.
#' @export
run_pmslt_disease_lifetable <- function(disease_epi,
                                        pif_data = NULL,
                                        cohort_size = 1000) {
  if (is.character(disease_epi) && length(disease_epi) == 1) {
    disease_epi <- read_pmslt_disease_inputs(disease_epi)
  } else {
    validate_pmslt_disease_inputs(disease_epi)
  }
  cohort_size <- validate_positive_number(cohort_size, "cohort_size")

  data <- disease_epi
  if (is.null(pif_data)) {
    data$pif <- 0
  } else {
    require_columns(pif_data, c("age_start", "sex", "stratum", "disease", "time_step", "pif"), "pif_data")
    data <- merge(
      data,
      pif_data[c("age_start", "sex", "stratum", "disease", "time_step", "pif")],
      by = c("age_start", "sex", "stratum", "disease", "time_step"),
      all.x = TRUE,
      sort = FALSE
    )
    data$pif[is.na(data$pif)] <- 0
  }
  data$pif <- pmax(-Inf, pmin(1, as.numeric(data$pif)))
  data$incidence_Int <- data$incidence_BAU * (1 - data$pif)

  split_key <- paste(data$disease, data$age_start, data$sex, data$stratum, sep = "\r")
  groups <- split(data, split_key)
  rows <- lapply(groups, function(group) run_one_disease_group(group, cohort_size))
  out <- do.call(rbind, rows)
  row.names(out) <- NULL
  out[order(out$disease, out$sex, out$stratum, out$age_start, out$time_step), ]
}

run_one_disease_group <- function(group, cohort_size) {
  group <- group[order(group$time_step), ]
  n <- nrow(group)
  s_bau <- c_bau <- d_bau <- s_int <- c_int <- d_int <- numeric(n)

  initial_prev <- group$prevalence_initial[group$time_step == 0][[1]]
  s_bau[[1]] <- cohort_size * (1 - initial_prev)
  c_bau[[1]] <- cohort_size * initial_prev
  d_bau[[1]] <- 0
  s_int[[1]] <- s_bau[[1]]
  c_int[[1]] <- c_bau[[1]]
  d_int[[1]] <- 0

  if (n > 1) {
    for (i in 2:n) {
      bau <- transition_disease_cycle(
        susceptible = s_bau[[i - 1]],
        diseased = c_bau[[i - 1]],
        dead = d_bau[[i - 1]],
        incidence = group$incidence_BAU[[i]],
        remission = group$remission_rate[[i]],
        fatality = group$case_fatality_BAU[[i]]
      )
      int <- transition_disease_cycle(
        susceptible = s_int[[i - 1]],
        diseased = c_int[[i - 1]],
        dead = d_int[[i - 1]],
        incidence = group$incidence_Int[[i]],
        remission = group$remission_rate[[i]],
        fatality = group$case_fatality_BAU[[i]]
      )
      s_bau[[i]] <- bau$susceptible
      c_bau[[i]] <- bau$diseased
      d_bau[[i]] <- bau$dead
      s_int[[i]] <- int$susceptible
      c_int[[i]] <- int$diseased
      d_int[[i]] <- int$dead
    }
  }

  alive_bau <- s_bau + c_bau
  alive_int <- s_int + c_int
  deaths_bau <- c(0, diff(d_bau))
  deaths_int <- c(0, diff(d_int))
  prev_bau <- ifelse(alive_bau > 0, c_bau / alive_bau, NA_real_)
  prev_int <- ifelse(alive_int > 0, c_int / alive_int, NA_real_)
  mort_bau <- ifelse(alive_bau > 0, deaths_bau / alive_bau, 0)
  mort_int <- ifelse(alive_int > 0, deaths_int / alive_int, 0)
  morb_bau <- prev_bau * group$disability_weight
  morb_int <- prev_int * group$disability_weight

  data.frame(
    group[c("age_start", "age_end", "age_label", "sex", "stratum", "disease", "time_step")],
    incidence_BAU = group$incidence_BAU,
    incidence_Int = group$incidence_Int,
    pif = group$pif,
    susceptible_BAU = s_bau,
    diseased_BAU = c_bau,
    dead_BAU = d_bau,
    susceptible_Int = s_int,
    diseased_Int = c_int,
    dead_Int = d_int,
    prevalence_BAU = prev_bau,
    prevalence_Int = prev_int,
    disease_mortality_BAU = mort_bau,
    disease_mortality_Int = mort_int,
    disease_morbidity_BAU = morb_bau,
    disease_morbidity_Int = morb_int,
    delta_mortality = mort_int - mort_bau,
    delta_morbidity = morb_int - morb_bau,
    stringsAsFactors = FALSE
  )
}

transition_disease_cycle <- function(susceptible, diseased, dead, incidence, remission, fatality) {
  incidence_prob <- 1 - exp(-incidence)
  remission_prob <- 1 - exp(-remission)
  fatality_prob <- 1 - exp(-fatality)

  incident <- susceptible * incidence_prob
  remitted <- diseased * remission_prob
  deaths <- diseased * fatality_prob
  susceptible_next <- susceptible - incident + remitted
  diseased_next <- diseased + incident - remitted - deaths
  dead_next <- dead + deaths

  list(
    susceptible = max(0, susceptible_next),
    diseased = max(0, diseased_next),
    dead = max(0, dead_next)
  )
}
