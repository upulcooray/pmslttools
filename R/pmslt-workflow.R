#' Read PMSLT-ready disease epidemiology inputs
#'
#' Reads the post-DisMod disease epidemiology file used by downstream PMSLT
#' disease lifetable modules. This is the canonical disease input after DisMod
#' processing, not the raw `05_disease_epidemiology_raw.csv` file and not an
#' intermediate DisMod-lite diagnostic output. It uses exact single-year integer
#' `age`; age-banded inputs belong upstream or in reporting summaries.
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
#' disease modules. The required columns come from the central
#' `pmslt_disease_epi.csv` schema. The canonical PMSLT-ready file uses exact
#' single-year integer `age`; age-banded raw inputs should be checked with
#' [validate_raw_inputs()] before DisMod processing.
#'
#' @param data Data frame, usually read from `pmslt_disease_epi.csv`.
#'
#' @return Invisibly returns `TRUE` if valid.
#' @export
validate_pmslt_disease_inputs <- function(data) {
  schema <- pmslt_disease_epi_schema()
  age_band_cols <- intersect(c("age_start", "age_end", "age_label"), names(data))
  if (length(age_band_cols) > 0) {
    stop(
      schema$file,
      " must use exact single-year `age`, not age-band columns: ",
      paste(age_band_cols, collapse = ", "),
      ". Raw age-banded disease inputs belong in 05_disease_epidemiology_raw.csv; run solve_disease_consistency() before using this PMSLT-ready file.",
      call. = FALSE
    )
  }
  required <- schema$columns$column[schema$columns$requirement == "required"]
  require_columns(data, required, schema$file)

  numeric_cols <- intersect(
    c(
      "age", "time_step",
      schema$columns$column[schema$columns$validation_type %in% c(
        "non_negative_rate", "proportion_0_1", "annual_proportional_change"
      )]
    ),
    names(data)
  )
  for (col in numeric_cols) {
    original <- data[[col]]
    present <- !(is.na(original) | !nzchar(trimws(as.character(original))))
    numeric_value <- suppressWarnings(as.numeric(original))
    if (any(present & is.na(numeric_value))) {
      stop(
        "`", col, "` must be numeric in ", schema$file, ".",
        call. = FALSE
      )
    }
    data[[col]] <- numeric_value
  }

  missing_age <- is.na(data$age)
  bad_age <- missing_age |
    abs(data$age - round(data$age)) > .Machine$double.eps^0.5
  if (any(bad_age)) {
    stop("`age` must contain non-missing whole-number single-year ages in ", schema$file, ".", call. = FALSE)
  }

  if ("time_step" %in% names(data)) {
    bad_time <- !is.na(data$time_step) &
      abs(data$time_step - round(data$time_step)) > .Machine$double.eps^0.5
    if (any(bad_time)) {
      stop("`time_step` must contain whole numbers in ", schema$file, ".", call. = FALSE)
    }
  }

  non_negative_cols <- c(
    "incidence_BAU", "remission_rate", "excess_mortality_BAU",
    "case_fatality_BAU", "disability_weight"
  )
  for (col in non_negative_cols) {
    bad <- !is.na(data[[col]]) & data[[col]] < 0
    if (any(bad)) {
      stop("`", col, "` must be non-negative in ", schema$file, ".", call. = FALSE)
    }
  }

  prev <- data$prevalence_initial
  if (any(!is.na(prev) & (prev < 0 | prev > 1))) {
    stop("`prevalence_initial` must be between 0 and 1 when supplied.", call. = FALSE)
  }
  if (any(!is.na(data$disability_weight) & data$disability_weight > 1)) {
    stop("`disability_weight` should be between 0 and 1.", call. = FALSE)
  }
  if ("prevalence_BAU_reference" %in% names(data)) {
    ref_prev <- data$prevalence_BAU_reference
    if (any(!is.na(ref_prev) & (ref_prev < 0 | ref_prev > 1))) {
      stop("`prevalence_BAU_reference` must be between 0 and 1 when supplied.", call. = FALSE)
    }
  }

  keys <- unique(data[c("age", "sex", "stratum", "disease")])
  missing_initial <- vapply(seq_len(nrow(keys)), function(i) {
    rows <- data[
      data$age == keys$age[[i]] &
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
#' @param pif_data Optional data frame with `age`, `sex`, `stratum`,
#'   `disease`, `time_step`, and `pif`. If omitted, intervention equals BAU.
#' @param direct_effect_data Optional data frame with direct disease effects.
#'   Expected columns are `age`, `sex`, `stratum`, `disease`, `incidence_rr`,
#'   `cfr_rr`, `morbidity_rr`, and `coverage`. Age-banded direct-effect rows
#'   from raw templates are expanded to exact ages before merging. If an
#'   `intervention` column is present, use `intervention` to select one arm.
#' @param intervention Optional intervention arm name used to filter PIF and
#'   direct-effect data when those inputs contain multiple scenarios.
#' @param cohort_size Radix cohort size for each disease lifetable.
#'
#' @return A data frame with BAU/intervention disease lifetable outputs and
#'   deltas.
#' @export
run_pmslt_disease_lifetable <- function(disease_epi,
                                        pif_data = NULL,
                                        direct_effect_data = NULL,
                                        intervention = NULL,
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
    pif_data <- filter_intervention_rows(pif_data, intervention, "pif_data")
    pif_data <- align_age_banded_effects(
      effects = pif_data,
      disease_epi = data,
      value_cols = "pif",
      time_varying = TRUE,
      label = "pif_data"
    )
    data <- merge(
      data,
      pif_data[c("age", "sex", "stratum", "disease", "time_step", "pif")],
      by = c("age", "sex", "stratum", "disease", "time_step"),
      all.x = TRUE,
      sort = FALSE
    )
    data$pif[is.na(data$pif)] <- 0
  }
  data$pif <- pmax(-Inf, pmin(1, as.numeric(data$pif)))
  data <- apply_direct_disease_effects(data, direct_effect_data, intervention)
  data$incidence_Int <- data$incidence_BAU * (1 - data$pif) * data$incidence_multiplier
  data$case_fatality_Int <- data$case_fatality_BAU * data$cfr_multiplier
  data$disability_weight_Int <- data$disability_weight * data$morbidity_multiplier

  split_key <- paste(data$disease, data$age, data$sex, data$stratum, sep = "\r")
  groups <- split(data, split_key)
  rows <- lapply(groups, function(group) run_one_disease_group(group, cohort_size))
  out <- do.call(rbind, rows)
  row.names(out) <- NULL
  out <- out[order(out$disease, out$sex, out$stratum, out$age, out$time_step), ]
  row.names(out) <- NULL
  out
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
        fatality = group$case_fatality_Int[[i]]
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
  morb_int <- prev_int * group$disability_weight_Int

  data.frame(
    group[c("age", "sex", "stratum", "disease", "time_step")],
    incidence_BAU = group$incidence_BAU,
    incidence_Int = group$incidence_Int,
    pif = group$pif,
    incidence_multiplier = group$incidence_multiplier,
    cfr_multiplier = group$cfr_multiplier,
    morbidity_multiplier = group$morbidity_multiplier,
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

#' Calculate population impact fractions from raw template inputs
#'
#' This converts `08_risk_factor_prevalence.csv` and `09_relative_risks.csv`
#' into the compact PIF table used by the disease lifetable. It supports
#' multiple intervention arms in the same prevalence file. When there is more
#' than one risk factor, PIFs are calculated separately by risk factor and then
#' combined as `1 - prod(1 - pif)`, an independence-style approximation.
#'
#' @param risk_prevalence Data frame or CSV path for
#'   `08_risk_factor_prevalence.csv`.
#' @param relative_risks Data frame or CSV path for `09_relative_risks.csv`.
#'
#' @return A data frame with one PIF per intervention, age, sex, stratum,
#'   disease, and time step.
#' @export
calculate_pif_from_inputs <- function(risk_prevalence, relative_risks) {
  risk_prevalence <- read_if_path(risk_prevalence, "risk_prevalence")
  relative_risks <- read_if_path(relative_risks, "relative_risks")

  validate_risk_prevalence_inputs(risk_prevalence)
  require_columns(
    risk_prevalence,
    c(
      "age_start", "age_end", "age_label", "sex", "stratum", "time_step",
      "intervention", "risk_factor", "risk_category", "prevalence_BAU",
      "prevalence_intervention"
    ),
    "08_risk_factor_prevalence.csv"
  )
  require_columns(
    relative_risks,
    c("age_start", "sex", "stratum", "risk_factor", "risk_category", "disease", "rr"),
    "09_relative_risks.csv"
  )

  join_cols <- c("age_start", "sex", "stratum", "risk_factor", "risk_category")
  joined <- merge(
    risk_prevalence,
    relative_risks[c(join_cols, "disease", "rr")],
    by = join_cols,
    all.x = TRUE,
    sort = FALSE
  )

  missing_rr <- is.na(joined$rr)
  if (any(missing_rr)) {
    examples <- unique(joined[missing_rr, join_cols, drop = FALSE])
    stop(
      "Missing relative risk rows for ",
      nrow(examples),
      " risk prevalence combination(s). Check risk_factor and risk_category labels.",
      call. = FALSE
    )
  }

  joined$prevalence_BAU <- as.numeric(joined$prevalence_BAU)
  joined$prevalence_intervention <- as.numeric(joined$prevalence_intervention)
  joined$rr <- as.numeric(joined$rr)
  if (any(is.na(joined$prevalence_BAU) | is.na(joined$prevalence_intervention) | is.na(joined$rr))) {
    stop("PIF calculation needs complete prevalence_BAU, prevalence_intervention, and rr values.", call. = FALSE)
  }

  output_cols <- c(
    "intervention", "age_start", "age_end", "age_label", "sex", "stratum",
    "disease", "time_step"
  )
  risk_factor_cols <- c(output_cols, "risk_factor")
  risk_factor_key <- do.call(paste, c(joined[risk_factor_cols], sep = "\r"))
  risk_factor_groups <- split(joined, risk_factor_key)

  risk_factor_pifs <- lapply(risk_factor_groups, function(group) {
    bau_weighted <- sum(group$prevalence_BAU * group$rr)
    int_weighted <- sum(group$prevalence_intervention * group$rr)
    pif <- if (bau_weighted > 0) (bau_weighted - int_weighted) / bau_weighted else 0
    data.frame(
      group[1, risk_factor_cols, drop = FALSE],
      pif = pif,
      stringsAsFactors = FALSE
    )
  })
  risk_factor_pifs <- do.call(rbind, risk_factor_pifs)

  output_key <- do.call(paste, c(risk_factor_pifs[output_cols], sep = "\r"))
  groups <- split(risk_factor_pifs, output_key)
  rows <- lapply(groups, function(group) {
    combined_pif <- 1 - prod(1 - group$pif)
    data.frame(
      group[1, output_cols, drop = FALSE],
      pif = combined_pif,
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  row.names(out) <- NULL
  out <- out[order(out$intervention, out$disease, out$sex, out$stratum, out$age_start, out$time_step), ]
  row.names(out) <- NULL
  out
}

#' Validate risk-factor prevalence distributions
#'
#' Checks that every risk-factor category distribution in
#' `08_risk_factor_prevalence.csv` sums to 1. This is a focused validation used
#' before PIF calculation.
#'
#' @param risk_prevalence Data frame or CSV path for
#'   `08_risk_factor_prevalence.csv`.
#' @param tolerance Maximum allowed absolute difference from 1.
#' @param stop_on_error Logical. If `TRUE`, stop when invalid sums are found.
#'   If `FALSE`, return an issue table.
#'
#' @return Invisibly returns an issue table when `stop_on_error = TRUE`; returns
#'   the issue table directly when `stop_on_error = FALSE`.
#' @export
validate_risk_prevalence_inputs <- function(risk_prevalence,
                                            tolerance = 0.001,
                                            stop_on_error = TRUE) {
  risk_prevalence <- read_if_path(risk_prevalence, "risk_prevalence")
  tolerance <- validate_nonnegative_number(tolerance, "tolerance")
  require_columns(
    risk_prevalence,
    c(
      "age_start", "sex", "stratum", "time_step", "intervention",
      "risk_factor", "risk_category", "prevalence_BAU",
      "prevalence_intervention"
    ),
    "08_risk_factor_prevalence.csv"
  )

  risk_prevalence$prevalence_BAU <- as.numeric(risk_prevalence$prevalence_BAU)
  risk_prevalence$prevalence_intervention <- as.numeric(risk_prevalence$prevalence_intervention)
  if (any(is.na(risk_prevalence$prevalence_BAU) | is.na(risk_prevalence$prevalence_intervention))) {
    stop("Risk prevalence validation needs complete prevalence_BAU and prevalence_intervention values.", call. = FALSE)
  }

  group_cols <- c("intervention", "age_start", "sex", "stratum", "time_step", "risk_factor")
  bau <- prevalence_sum_issues(
    risk_prevalence,
    value_col = "prevalence_BAU",
    prevalence_type = "BAU",
    group_cols = group_cols,
    tolerance = tolerance
  )
  intervention <- prevalence_sum_issues(
    risk_prevalence,
    value_col = "prevalence_intervention",
    prevalence_type = "intervention",
    group_cols = group_cols,
    tolerance = tolerance
  )
  issues <- rbind(bau, intervention)
  row.names(issues) <- NULL

  if (nrow(issues) > 0 && isTRUE(stop_on_error)) {
    first <- issues[1, , drop = FALSE]
    stop(
      "Risk-factor prevalence categories must sum to 1 within each intervention, age, sex, stratum, time_step, and risk_factor. ",
      "First problem: ", first$prevalence_type, " prevalence for intervention `", first$intervention,
      "`, risk factor `", first$risk_factor, "`, age_start ", first$age_start,
      ", sex `", first$sex, "`, stratum `", first$stratum, "`, time_step ",
      first$time_step, " sums to ", round(first$prevalence_sum, 6), ".",
      call. = FALSE
    )
  }

  if (isTRUE(stop_on_error)) {
    invisible(issues)
  } else {
    issues
  }
}

#' Run PMSLT disease lifetables for one or more intervention arms
#'
#' This is the beginner-facing intervention runner. It accepts post-DisMod
#' exact-age disease inputs, optional raw risk-factor prevalence plus relative
#' risks, and optional direct disease effects. Risk-factor inputs are converted
#' to PIFs automatically. Direct effects can be used alone or alongside PIFs.
#' Age-banded intervention rows are expanded to the exact ages present in
#' `pmslt_disease_epi.csv` where that expansion is intentional.
#'
#' @param disease_epi Data frame from [read_pmslt_disease_inputs()] or path to
#'   `pmslt_disease_epi.csv`.
#' @param risk_prevalence Optional data frame or CSV path for
#'   `08_risk_factor_prevalence.csv`.
#' @param relative_risks Optional data frame or CSV path for
#'   `09_relative_risks.csv`.
#' @param direct_effects Optional data frame or CSV path for
#'   `10_direct_intervention_effects.csv`.
#' @param interventions Optional character vector of intervention arms to run.
#'   Defaults to every arm found in PIF or direct-effect inputs.
#' @param cohort_size Radix cohort size for each disease lifetable.
#'
#' @return A data frame of disease lifetable outputs with an `intervention`
#'   column.
#' @export
run_pmslt_interventions <- function(disease_epi,
                                    risk_prevalence = NULL,
                                    relative_risks = NULL,
                                    direct_effects = NULL,
                                    interventions = NULL,
                                    cohort_size = 1000) {
  pif_data <- NULL
  if (!is.null(risk_prevalence) || !is.null(relative_risks)) {
    if (is.null(risk_prevalence) || is.null(relative_risks)) {
      stop("Supply both `risk_prevalence` and `relative_risks` to calculate PIFs.", call. = FALSE)
    }
    pif_data <- calculate_pif_from_inputs(risk_prevalence, relative_risks)
  }
  if (!is.null(direct_effects)) {
    direct_effects <- read_if_path(direct_effects, "direct_effects")
  }

  if (is.null(interventions)) {
    interventions <- unique(c(
      if (!is.null(pif_data) && "intervention" %in% names(pif_data)) pif_data$intervention else NULL,
      if (!is.null(direct_effects) && "intervention" %in% names(direct_effects)) direct_effects$intervention else NULL
    ))
    interventions <- interventions[!is.na(interventions) & nzchar(interventions)]
  }
  if (length(interventions) == 0) {
    interventions <- "No intervention"
  }

  rows <- lapply(interventions, function(arm) {
    out <- run_pmslt_disease_lifetable(
      disease_epi = disease_epi,
      pif_data = pif_data,
      direct_effect_data = direct_effects,
      intervention = arm,
      cohort_size = cohort_size
    )
    data.frame(intervention = arm, out, stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, rows)
  row.names(out) <- NULL
  out
}

apply_direct_disease_effects <- function(data, direct_effect_data, intervention) {
  data$incidence_multiplier <- 1
  data$cfr_multiplier <- 1
  data$morbidity_multiplier <- 1
  if (is.null(direct_effect_data)) {
    return(data)
  }

  direct_effect_data <- filter_intervention_rows(direct_effect_data, intervention, "direct_effect_data")
  direct_effect_data <- align_age_banded_effects(
    effects = direct_effect_data,
    disease_epi = data,
    value_cols = c("incidence_rr", "cfr_rr", "morbidity_rr", "coverage"),
    time_varying = FALSE,
    label = "direct_effect_data"
  )

  direct_effect_data$coverage <- ifelse(is.na(as.numeric(direct_effect_data$coverage)), 0, as.numeric(direct_effect_data$coverage))
  direct_effect_data$incidence_rr <- default_numeric(direct_effect_data$incidence_rr, 1)
  direct_effect_data$cfr_rr <- default_numeric(direct_effect_data$cfr_rr, 1)
  direct_effect_data$morbidity_rr <- default_numeric(direct_effect_data$morbidity_rr, 1)

  # Coverage scales the direct effect from the treated group to the whole
  # modelled population. Example: RR 0.80 at 50% coverage becomes 0.90 overall.
  direct_effect_data$incidence_multiplier <- 1 - direct_effect_data$coverage * (1 - direct_effect_data$incidence_rr)
  direct_effect_data$cfr_multiplier <- 1 - direct_effect_data$coverage * (1 - direct_effect_data$cfr_rr)
  direct_effect_data$morbidity_multiplier <- 1 - direct_effect_data$coverage * (1 - direct_effect_data$morbidity_rr)

  keep <- c("age", "sex", "stratum", "disease", "incidence_multiplier", "cfr_multiplier", "morbidity_multiplier")
  data <- merge(
    data,
    direct_effect_data[keep],
    by = c("age", "sex", "stratum", "disease"),
    all.x = TRUE,
    sort = FALSE,
    suffixes = c("", "_direct")
  )
  for (name in c("incidence_multiplier", "cfr_multiplier", "morbidity_multiplier")) {
    direct_name <- paste0(name, "_direct")
    data[[name]] <- ifelse(is.na(data[[direct_name]]), data[[name]], data[[direct_name]])
    data[[direct_name]] <- NULL
  }
  data
}

align_age_banded_effects <- function(effects, disease_epi, value_cols, time_varying, label) {
  key_cols <- c("sex", "stratum", "disease")
  required <- c(key_cols, value_cols)
  if (isTRUE(time_varying)) {
    required <- c(required, "time_step")
  }
  require_columns(effects, required, label)

  if ("age" %in% names(effects)) {
    keep <- c("age", key_cols, if (isTRUE(time_varying)) "time_step", value_cols)
    out <- effects[keep]
    out$age <- as.numeric(out$age)
    return(out)
  }

  require_columns(effects, c("age_start", "age_end"), label)
  effect_rows <- effects
  effect_rows$.effect_row <- seq_len(nrow(effect_rows))
  epi_keys <- unique(disease_epi[c("age", key_cols, if (isTRUE(time_varying)) "time_step")])

  joined <- merge(
    epi_keys,
    effect_rows,
    by = c(key_cols, if (isTRUE(time_varying)) "time_step"),
    all.x = FALSE,
    sort = FALSE
  )
  joined <- joined[
    joined$age >= as.numeric(joined$age_start) &
      joined$age <= as.numeric(joined$age_end),
    ,
    drop = FALSE
  ]
  keep <- c("age", key_cols, if (isTRUE(time_varying)) "time_step", value_cols)
  out <- joined[keep]
  row.names(out) <- NULL
  out
}

filter_intervention_rows <- function(data, intervention, label) {
  if (!is.null(intervention) && "intervention" %in% names(data)) {
    data <- data[data$intervention == intervention, , drop = FALSE]
    if (nrow(data) == 0) {
      warning("No rows for intervention `", intervention, "` in ", label, ". Assuming no effect.", call. = FALSE)
    }
  }
  data
}

default_numeric <- function(x, default) {
  x <- as.numeric(x)
  ifelse(is.na(x), default, x)
}

prevalence_sum_issues <- function(data, value_col, prevalence_type, group_cols, tolerance) {
  sums <- stats::aggregate(
    data[[value_col]],
    data[group_cols],
    sum
  )
  names(sums)[names(sums) == "x"] <- "prevalence_sum"
  sums$difference <- sums$prevalence_sum - 1
  bad <- abs(sums$difference) > tolerance
  if (!any(bad)) {
    return(data.frame(
      prevalence_type = character(),
      sums[FALSE, , drop = FALSE],
      message = character(),
      stringsAsFactors = FALSE
    ))
  }
  issues <- sums[bad, , drop = FALSE]
  data.frame(
    prevalence_type = prevalence_type,
    issues,
    message = paste0(prevalence_type, " prevalence sums to ", round(issues$prevalence_sum, 6), ", not 1."),
    stringsAsFactors = FALSE
  )
}

read_if_path <- function(x, label) {
  if (is.character(x) && length(x) == 1) {
    if (!file.exists(x)) {
      stop("Missing ", label, " file: ", x, call. = FALSE)
    }
    return(utils::read.csv(x, stringsAsFactors = FALSE, na.strings = c("", "NA")))
  }
  x
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
