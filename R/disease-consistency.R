#' Solve disease parameter consistency and write PMSLT-ready disease inputs
#'
#' This is the beginner-facing bridge from checked raw disease inputs to the
#' canonical `pmslt_disease_epi.csv` file. `solver = "disbayes"` is the planned
#' primary real consistency solver and remains optional because it requires a
#' Stan-capable `disbayes` installation. `solver = "dismod_slove"` keeps the
#' package-native deterministic solver available for local workflows.
#'
#' @param input_dir Directory created by [draft_input_templates()].
#' @param output_dir Directory where solver outputs should be written.
#' @param solver Solver backend. `"disbayes"` requires the optional
#'   `disbayes` package. `"dismod_slove"` runs without optional dependencies.
#' @param output_file CSV path for the canonical PMSLT-ready disease input.
#' @param overwrite Logical. Should existing output files be overwritten?
#' @param horizon Optional simulation horizon. If `NULL`, inferred from
#'   `08_risk_factor_prevalence.csv` when available; otherwise 0.
#' @param ... Additional arguments passed to the selected solver.
#'
#' @return Invisibly returns a list containing solver outputs,
#'   `pmslt_disease_epi`, `output_dir`, `output_file`, and `solver`.
#' @export
#'
#' @examples
#' \dontrun{
#' solve_disease_consistency("inputs_raw")
#' solve_disease_consistency("inputs_raw", solver = "dismod_slove")
#' }
solve_disease_consistency <- function(input_dir = "pmslt_inputs_raw",
                                      output_dir = file.path(input_dir, "disease_consistency_results"),
                                      solver = c("disbayes", "dismod_slove"),
                                      output_file = file.path(output_dir, "pmslt_disease_epi.csv"),
                                      overwrite = FALSE,
                                      horizon = NULL,
                                      ...) {
  solver <- match.arg(solver)

  if (solver == "disbayes") {
    return(
      solve_disease_consistency_disbayes(
        input_dir = input_dir,
        output_dir = output_dir,
        output_file = output_file,
        overwrite = overwrite,
        horizon = horizon,
        ...
      )
    )
  }

  if (file.exists(output_file) && !isTRUE(overwrite)) {
    stop("File already exists: ", output_file, ". Use `overwrite = TRUE` to replace it.", call. = FALSE)
  }

  solved <- dismod_slove(
    input_dir = input_dir,
    output_dir = output_dir,
    overwrite = overwrite,
    ...
  )

  pmslt_disease_epi <- dismod_slove_to_pmslt_disease_epi(
    solved_wide = solved$solved_wide,
    input_dir = input_dir,
    horizon = horizon
  )

  if (!dir.exists(dirname(output_file))) {
    dir.create(dirname(output_file), recursive = TRUE)
  }
  utils::write.csv(pmslt_disease_epi, output_file, row.names = FALSE, na = "")
  message("PMSLT-ready disease inputs written to: ", normalizePath(output_file))

  out <- c(
    solved,
    list(
      pmslt_disease_epi = pmslt_disease_epi,
      output_dir = output_dir,
      output_file = output_file,
      solver = solver
    )
  )
  class(out) <- c("disease_consistency_result", class(out))
  invisible(out)
}

solve_disease_consistency_disbayes <- function(input_dir,
                                               output_dir,
                                               output_file,
                                               overwrite,
                                               horizon = NULL,
                                               fit_function = NULL,
                                               ...) {
  if (file.exists(output_file) && !isTRUE(overwrite)) {
    stop("File already exists: ", output_file, ". Use `overwrite = TRUE` to replace it.", call. = FALSE)
  }
  if (is.null(fit_function)) {
    check_disbayes_available()
  }

  prepared <- prepare_disbayes_evidence(input_dir = input_dir)
  stop_for_disbayes_preparation_diagnostics(prepared$diagnostics)
  fit_result <- fit_disbayes_groups(
    evidence = prepared$evidence,
    fit_function = fit_function,
    ...
  )
  solver_long <- tidy_disbayes_fits(fit_result$fits)
  pmslt_disease_epi <- disbayes_to_pmslt_disease_epi(
    solver_long = solver_long,
    prepared = prepared,
    input_dir = input_dir,
    horizon = horizon
  )

  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }
  write_disbayes_execution_outputs(
    output_dir = output_dir,
    output_file = output_file,
    pmslt_disease_epi = pmslt_disease_epi,
    solver_long = solver_long,
    fit_summary = fit_result$fit_summary,
    prepared = prepared,
    overwrite = overwrite
  )
  message("PMSLT-ready disease inputs written to: ", normalizePath(output_file))

  out <- list(
    pmslt_disease_epi = pmslt_disease_epi,
    solver_long = solver_long,
    fit_summary = fit_result$fit_summary,
    evidence = prepared$evidence,
    diagnostics = prepared$diagnostics,
    age_audit = prepared$age_audit,
    output_dir = output_dir,
    output_file = output_file,
    solver = "disbayes"
  )
  class(out) <- c("disease_consistency_result", class(out))
  invisible(out)
}

check_disbayes_available <- function() {
  if (requireNamespace("disbayes", quietly = TRUE)) {
    return(invisible(TRUE))
  }
  stop(
    "`solver = \"disbayes\"` is planned but not implemented on this machine ",
    "because the optional `disbayes` package is not installed. Install and ",
    "configure `disbayes` and its Stan backend, or run ",
    "`solve_disease_consistency(..., solver = \"dismod_slove\")`.",
    call. = FALSE
  )
}

dismod_slove_to_pmslt_disease_epi <- function(solved_wide, input_dir, horizon = NULL) {
  require_columns(
    solved_wide,
    c(
      "age_start", "age_end", "sex", "stratum", "disease",
      "incidence_rate", "prevalence", "remission_rate",
      "excess_mortality_rate", "case_fatality_rate"
    ),
    "dismod_slove solved_wide"
  )

  base <- data.frame(
    age = as.integer(as.numeric(solved_wide$age_start)),
    sex = as.character(solved_wide$sex),
    stratum = as.character(solved_wide$stratum),
    disease = as.character(solved_wide$disease),
    incidence_rate = as.numeric(solved_wide$incidence_rate),
    prevalence = as.numeric(solved_wide$prevalence),
    remission_rate = as.numeric(solved_wide$remission_rate),
    excess_mortality_rate = as.numeric(solved_wide$excess_mortality_rate),
    case_fatality_rate = as.numeric(solved_wide$case_fatality_rate),
    stringsAsFactors = FALSE
  )

  raw_path <- file.path(input_dir, "05_disease_epidemiology_raw.csv")
  if (file.exists(raw_path)) {
    raw <- utils::read.csv(raw_path, stringsAsFactors = FALSE, na.strings = c("", "NA"))
    if ("disability_weight" %in% names(raw)) {
      raw_dw <- expand_age_banded_values(
        unique(raw[c("age_start", "age_end", "sex", "stratum", "disease", "disability_weight")]),
        value_cols = "disability_weight"
      )
      base <- merge(base, raw_dw, by = c("age", "sex", "stratum", "disease"), all.x = TRUE, sort = FALSE)
    }
  }
  if (!"disability_weight" %in% names(base)) {
    base$disability_weight <- NA_real_
  }

  trend_path <- file.path(input_dir, "07_bau_trends.csv")
  if (file.exists(trend_path)) {
    trends <- utils::read.csv(trend_path, stringsAsFactors = FALSE, na.strings = c("", "NA"))
    keep <- intersect(c("disease", "incidence_apc", "cfr_apc", "prevalence_apc"), names(trends))
    if ("disease" %in% keep) {
      base <- merge(base, unique(trends[keep]), by = "disease", all.x = TRUE, sort = FALSE)
    }
  }
  for (col in c("incidence_apc", "cfr_apc", "prevalence_apc")) {
    if (!col %in% names(base)) {
      base[[col]] <- 0
    }
    base[[col]][is.na(base[[col]])] <- 0
  }

  if (is.null(horizon)) {
    horizon <- infer_disease_consistency_horizon(input_dir)
  }
  horizon <- validate_nonnegative_integer(horizon, "horizon")
  time_grid <- data.frame(time_step = seq.int(0, horizon), stringsAsFactors = FALSE)
  out <- merge(base, time_grid, all = TRUE)
  out$incidence_BAU <- out$incidence_rate * exp(out$incidence_apc * out$time_step)
  out$prevalence_initial <- ifelse(out$time_step == 0, out$prevalence, NA_real_)
  out$remission_rate <- out$remission_rate
  out$excess_mortality_BAU <- out$excess_mortality_rate * exp(out$cfr_apc * out$time_step)
  out$case_fatality_BAU <- out$case_fatality_rate * exp(out$cfr_apc * out$time_step)
  out$prevalence_BAU_reference <- out$prevalence * exp(out$prevalence_apc * out$time_step)
  out$input_source <- "solve_disease_consistency(solver = \"dismod_slove\")"

  ordered_cols <- pmslt_disease_epi_schema()$columns$column
  out <- out[ordered_cols]
  out <- out[order(out$disease, out$sex, out$stratum, out$age, out$time_step), ]
  row.names(out) <- NULL
  validate_pmslt_disease_inputs(out)
  out
}

validate_nonnegative_integer <- function(value, label) {
  value <- suppressWarnings(as.numeric(value))
  if (length(value) != 1 || is.na(value) || value < 0 ||
      abs(value - round(value)) > .Machine$double.eps^0.5) {
    stop("`", label, "` must be one non-negative whole number.", call. = FALSE)
  }
  as.integer(value)
}

infer_disease_consistency_horizon <- function(input_dir) {
  prevalence_path <- file.path(input_dir, "08_risk_factor_prevalence.csv")
  if (!file.exists(prevalence_path)) {
    return(0L)
  }
  prevalence <- utils::read.csv(prevalence_path, stringsAsFactors = FALSE, na.strings = c("", "NA"))
  if (!"time_step" %in% names(prevalence)) {
    return(0L)
  }
  max(as.integer(prevalence$time_step), na.rm = TRUE)
}

prepare_disbayes_evidence <- function(input_dir,
                                      require_uncertainty = TRUE) {
  if (!dir.exists(input_dir)) {
    stop("`input_dir` does not exist: ", input_dir, call. = FALSE)
  }

  wide_path <- file.path(input_dir, "05_disease_epidemiology_raw.csv")
  long_path <- file.path(input_dir, "06_dismod_input_skeleton.csv")
  if (!file.exists(wide_path) && !file.exists(long_path)) {
    stop(
      "`input_dir` must contain 05_disease_epidemiology_raw.csv or ",
      "06_dismod_input_skeleton.csv.",
      call. = FALSE
    )
  }

  wide <- read_optional_csv(wide_path)
  long <- read_optional_csv(long_path)
  target_grid <- dismod_target_grid(wide, long)
  target_ages <- unique(target_grid[c("age_start", "sex", "stratum", "disease")])
  names(target_ages)[names(target_ages) == "age_start"] <- "target_age"
  target_ages$target_age <- as.integer(as.numeric(target_ages$target_age))

  observations <- disbayes_observations(wide, long)
  groups <- unique(target_grid[c("sex", "stratum", "disease")])
  internal_grid <- disbayes_internal_grid(groups, target_ages)
  evidence <- expand_disbayes_observations(observations, internal_grid)
  evidence <- convert_disbayes_rates_to_probabilities(evidence)

  age_audit <- disbayes_age_audit(evidence)
  completeness <- disbayes_completeness_diagnostics(evidence)
  uncertainty <- disbayes_uncertainty_diagnostics(evidence, require_uncertainty = require_uncertainty)
  diagnostics <- rbind_diagnostics(completeness, uncertainty)

  list(
    evidence = evidence,
    diagnostics = diagnostics,
    age_audit = age_audit,
    completeness = completeness,
    uncertainty = uncertainty
  )
}

disbayes_observations <- function(wide, long) {
  rows <- list()
  if (!is.null(wide)) {
    rows[["raw"]] <- disbayes_wide_to_long_input(wide)
  }
  if (!is.null(long)) {
    rows[["long"]] <- disbayes_long_input(long)
  }
  out <- do.call(rbind, rows)
  out <- out[!is.na(out$mean_value), , drop = FALSE]
  numeric_cols <- c("age_start", "age_end", "mean_value", "lower_95", "upper_95", "sample_size")
  out[numeric_cols] <- lapply(out[numeric_cols], as.numeric)
  out
}

disbayes_wide_to_long_input <- function(wide) {
  param_map <- c(
    incidence_rate = "incidence",
    prevalence = "prevalence",
    remission_rate = "remission",
    disease_mortality_rate = "mortality",
    excess_mortality_rate = "excess_mortality",
    case_fatality_rate = "case_fatality"
  )
  grid_cols <- c("age_start", "age_end", "age_label", "sex", "stratum", "disease")
  require_columns(wide, c(grid_cols, names(param_map)), "05_disease_epidemiology_raw.csv")

  rows <- lapply(names(param_map), function(col) {
    data.frame(
      wide[grid_cols],
      parameter = unname(param_map[[col]]),
      mean_value = as.numeric(wide[[col]]),
      lower_95 = NA_real_,
      upper_95 = NA_real_,
      sample_size = NA_real_,
      input_source = "05_disease_epidemiology_raw.csv",
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

disbayes_long_input <- function(long) {
  grid_cols <- c("age_start", "age_end", "age_label", "sex", "stratum", "disease")
  require_columns(long, c(grid_cols, "parameter", "mean_value"), "06_dismod_input_skeleton.csv")
  lower <- if ("lower_95" %in% names(long)) as.numeric(long$lower_95) else NA_real_
  upper <- if ("upper_95" %in% names(long)) as.numeric(long$upper_95) else NA_real_
  sample_size <- if ("sample_size" %in% names(long)) as.numeric(long$sample_size) else NA_real_

  data.frame(
    long[grid_cols],
    parameter = normalize_dismod_parameter(long$parameter),
    mean_value = as.numeric(long$mean_value),
    lower_95 = lower,
    upper_95 = upper,
    sample_size = sample_size,
    input_source = "06_dismod_input_skeleton.csv",
    stringsAsFactors = FALSE
  )
}

disbayes_internal_grid <- function(groups, target_ages) {
  rows <- lapply(seq_len(nrow(groups)), function(i) {
    group <- groups[i, , drop = FALSE]
    group_target <- target_ages[
      target_ages$disease == group$disease &
        target_ages$sex == group$sex &
        target_ages$stratum == group$stratum,
      ,
      drop = FALSE
    ]
    max_age <- max(group_target$target_age, na.rm = TRUE)
    ages <- seq.int(0L, max_age)
    out <- group[rep(1, length(ages)), , drop = FALSE]
    out$age <- ages
    out$is_target_age <- ages %in% group_target$target_age
    row.names(out) <- NULL
    out
  })
  do.call(rbind, rows)
}

expand_disbayes_observations <- function(observations, internal_grid) {
  params <- c("incidence", "prevalence", "remission", "mortality", "excess_mortality", "case_fatality")
  target <- merge(internal_grid, data.frame(parameter = params, stringsAsFactors = FALSE), all = TRUE)
  target <- target[order(target$disease, target$sex, target$stratum, target$age, target$parameter), ]
  row.names(target) <- NULL

  rows <- lapply(seq_len(nrow(target)), function(i) {
    row <- target[i, , drop = FALSE]
    candidates <- observations[
      observations$disease == row$disease &
        observations$sex == row$sex &
        observations$stratum == row$stratum &
        observations$parameter == row$parameter,
      ,
      drop = FALSE
    ]
    match <- disbayes_age_match(row, candidates)
    data.frame(
      disease = row$disease,
      sex = row$sex,
      stratum = row$stratum,
      age = as.integer(row$age),
      parameter = row$parameter,
      mean_value = match$mean_value,
      lower_95 = match$lower_95,
      upper_95 = match$upper_95,
      sample_size = match$sample_size,
      input_source = match$input_source,
      age_status = match$age_status,
      source_age_start = match$source_age_start,
      source_age_end = match$source_age_end,
      is_target_age = row$is_target_age,
      is_padded_age = !isTRUE(row$is_target_age),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

disbayes_age_match <- function(target, candidates) {
  empty_match <- list(
    mean_value = NA_real_,
    lower_95 = NA_real_,
    upper_95 = NA_real_,
    sample_size = NA_real_,
    input_source = NA_character_,
    age_status = if (isTRUE(target$is_target_age)) "missing" else "padded",
    source_age_start = NA_real_,
    source_age_end = NA_real_
  )
  if (!isTRUE(target$is_target_age) || nrow(candidates) == 0) {
    return(empty_match)
  }

  candidates$age_start <- as.numeric(candidates$age_start)
  candidates$age_end <- as.numeric(candidates$age_end)
  candidates$age_end[is.infinite(candidates$age_end)] <- candidates$age_start[is.infinite(candidates$age_end)]
  candidates <- candidates[
    candidates$age_start <= target$age & candidates$age_end >= target$age,
    ,
    drop = FALSE
  ]
  if (nrow(candidates) == 0) {
    return(empty_match)
  }

  candidates$priority <- ifelse(candidates$age_start == target$age & candidates$age_end == target$age, 2L, 1L)
  candidates$source_priority <- ifelse(candidates$input_source == "06_dismod_input_skeleton.csv", 2L, 1L)
  candidates$band_width <- candidates$age_end - candidates$age_start
  candidates <- candidates[order(-candidates$priority, -candidates$source_priority, candidates$band_width), , drop = FALSE]
  best <- candidates[1, , drop = FALSE]

  list(
    mean_value = best$mean_value,
    lower_95 = best$lower_95,
    upper_95 = best$upper_95,
    sample_size = best$sample_size,
    input_source = best$input_source,
    age_status = if (best$priority == 2L) "exact" else "expanded_constant",
    source_age_start = best$age_start,
    source_age_end = best$age_end
  )
}

convert_disbayes_rates_to_probabilities <- function(evidence) {
  rate_parameters <- c("incidence", "remission", "mortality", "excess_mortality", "case_fatality")
  evidence$value_scale <- ifelse(evidence$parameter %in% rate_parameters, "annual_probability", "proportion")
  evidence$mean_probability <- evidence$mean_value
  evidence$lower_probability <- evidence$lower_95
  evidence$upper_probability <- evidence$upper_95

  rate_rows <- evidence$parameter %in% rate_parameters
  evidence$mean_probability[rate_rows] <- rate_to_probability(evidence$mean_value[rate_rows])
  evidence$lower_probability[rate_rows] <- rate_to_probability(evidence$lower_95[rate_rows])
  evidence$upper_probability[rate_rows] <- rate_to_probability(evidence$upper_95[rate_rows])
  evidence
}

rate_to_probability <- function(rate) {
  rate <- as.numeric(rate)
  out <- rep(NA_real_, length(rate))
  ok <- !is.na(rate)
  out[ok] <- 1 - exp(-rate[ok])
  out
}

disbayes_age_audit <- function(evidence) {
  unique(evidence[c(
    "disease", "sex", "stratum", "age", "parameter", "age_status",
    "source_age_start", "source_age_end", "input_source", "is_target_age",
    "is_padded_age"
  )])
}

disbayes_completeness_diagnostics <- function(evidence) {
  groups <- unique(evidence[c("disease", "sex", "stratum")])
  rows <- lapply(seq_len(nrow(groups)), function(i) {
    group <- groups[i, , drop = FALSE]
    target <- evidence[
      evidence$disease == group$disease &
        evidence$sex == group$sex &
        evidence$stratum == group$stratum &
        evidence$is_target_age,
      ,
      drop = FALSE
    ]
    present <- unique(target$parameter[!is.na(target$mean_value)])
    missing <- character()
    if (!"mortality" %in% present) missing <- c(missing, "mortality")
    if (!any(c("incidence", "prevalence") %in% present)) missing <- c(missing, "incidence or prevalence")
    if (length(missing) == 0) {
      return(NULL)
    }
    data.frame(
      group,
      diagnostic_type = "missing_evidence",
      parameter = paste(missing, collapse = "; "),
      severity = "error",
      message = paste0(
        "Disbayes preparation needs mortality plus at least one of incidence or prevalence for ",
        group$disease, ", ", group$sex, ", ", group$stratum, ". Missing: ",
        paste(missing, collapse = "; "), "."
      ),
      suggested_fix = paste0(
        "Add explicit disease-specific mortality evidence using `parameter = \"mortality\"` ",
        "or `disease_mortality_rate`, and add incidence or prevalence evidence. ",
        "Do not copy `excess_mortality_rate` into mortality unless that is a documented source assumption."
      ),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows[!vapply(rows, is.null, logical(1))])
  if (is.null(out)) empty_disbayes_diagnostic()
  else out
}

disbayes_uncertainty_diagnostics <- function(evidence, require_uncertainty) {
  if (!isTRUE(require_uncertainty)) {
    return(empty_disbayes_diagnostic())
  }
  observed <- evidence[!is.na(evidence$mean_value) & evidence$is_target_age, , drop = FALSE]
  if (nrow(observed) == 0) {
    return(empty_disbayes_diagnostic())
  }
  observed$has_bounds <- !is.na(observed$lower_95) & !is.na(observed$upper_95) &
    observed$lower_95 <= observed$mean_value & observed$upper_95 >= observed$mean_value &
    observed$upper_95 > observed$lower_95
  observed$has_sample_size <- !is.na(observed$sample_size) & observed$sample_size > 0
  missing <- observed[!(observed$has_bounds | observed$has_sample_size), , drop = FALSE]
  if (nrow(missing) == 0) {
    return(empty_disbayes_diagnostic())
  }
  unique_missing <- unique(missing[c("disease", "sex", "stratum", "parameter")])
  data.frame(
    unique_missing[c("disease", "sex", "stratum")],
    diagnostic_type = "insufficient_uncertainty",
    parameter = unique_missing$parameter,
    severity = "error",
    message = paste0(
      "Point-estimate-only evidence is not enough for disbayes preparation: ",
      unique_missing$parameter, " for ", unique_missing$disease, ", ",
      unique_missing$sex, ", ", unique_missing$stratum, "."
    ),
    suggested_fix = paste0(
      "Provide lower_95/upper_95 or sample_size in `06_dismod_input_skeleton.csv`, ",
      "or use `solver = \"dismod_slove\"` for a deterministic preparation path."
    ),
    stringsAsFactors = FALSE
  )
}

empty_disbayes_diagnostic <- function() {
  data.frame(
    disease = character(),
    sex = character(),
    stratum = character(),
    diagnostic_type = character(),
    parameter = character(),
    severity = character(),
    message = character(),
    suggested_fix = character(),
    stringsAsFactors = FALSE
  )
}

rbind_diagnostics <- function(...) {
  pieces <- list(...)
  pieces <- pieces[vapply(pieces, nrow, integer(1)) > 0]
  if (length(pieces) == 0) {
    return(empty_disbayes_diagnostic())
  }
  do.call(rbind, pieces)
}

write_disbayes_preparation_outputs <- function(output_dir, prepared, overwrite) {
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }
  outputs <- list(
    "disbayes_evidence_prepared.csv" = prepared$evidence,
    "disbayes_preparation_diagnostics.csv" = prepared$diagnostics,
    "disbayes_age_audit.csv" = prepared$age_audit,
    "disbayes_uncertainty_audit.csv" = prepared$uncertainty
  )
  for (name in names(outputs)) {
    path <- file.path(output_dir, name)
    if (file.exists(path) && !isTRUE(overwrite)) {
      stop(
        "File already exists: ", path,
        ". Use `overwrite = TRUE` to replace it.",
        call. = FALSE
      )
    }
    utils::write.csv(outputs[[name]], path, row.names = FALSE, na = "")
  }
}

stop_for_disbayes_preparation_diagnostics <- function(diagnostics) {
  errors <- diagnostics[diagnostics$severity == "error", , drop = FALSE]
  if (nrow(errors) == 0) {
    return(invisible(TRUE))
  }
  first <- errors[1, , drop = FALSE]
  stop(
    "Disbayes evidence is incomplete for disease = ", first$disease,
    ", sex = ", first$sex,
    ", stratum = ", first$stratum,
    ": ", first$message,
    " Suggested fix: ", first$suggested_fix,
    call. = FALSE
  )
}

fit_disbayes_groups <- function(evidence, fit_function = NULL, ...) {
  if (is.null(fit_function)) {
    check_disbayes_available()
    fit_function <- getExportedValue("disbayes", "disbayes")
  }
  fit_data <- disbayes_fit_data(evidence)
  groups <- unique(fit_data[c("disease", "sex", "stratum")])
  fits <- vector("list", nrow(groups))
  summary <- vector("list", nrow(groups))
  dots <- list(...)
  for (i in seq_len(nrow(groups))) {
    group <- groups[i, , drop = FALSE]
    data <- fit_data[
      fit_data$disease == group$disease &
        fit_data$sex == group$sex &
        fit_data$stratum == group$stratum,
      ,
      drop = FALSE
    ]
    fit_args <- c(
      list(
        data = data,
        inc_prob = "inc_prob",
        inc_lower = "inc_lower",
        inc_upper = "inc_upper",
        prev_prob = "prev_prob",
        prev_lower = "prev_lower",
        prev_upper = "prev_upper",
        mort_prob = "mort_prob",
        mort_lower = "mort_lower",
        mort_upper = "mort_upper",
        rem_prob = "rem_prob",
        rem_lower = "rem_lower",
        rem_upper = "rem_upper",
        age = "age"
      ),
      dots
    )
    if (is.null(fit_args$eqage)) {
      fit_args$eqage <- min(30L, max(data$age, na.rm = TRUE))
    }
    fit <- do.call(fit_function, fit_args)
    fits[[i]] <- list(group = group, fit = fit)
    summary[[i]] <- data.frame(
      group,
      n_evidence_rows = nrow(data),
      fit_status = "ok",
      fit_message = "",
      stringsAsFactors = FALSE
    )
  }
  list(fits = fits, fit_summary = do.call(rbind, summary))
}

disbayes_fit_data <- function(evidence) {
  parameter_map <- c(incidence = "inc", prevalence = "prev", remission = "rem", mortality = "mort")
  keep <- evidence$parameter %in% names(parameter_map)
  data <- evidence[keep & !is.na(evidence$mean_probability), , drop = FALSE]
  keys <- unique(data[c("age", "sex", "stratum", "disease")])
  keys <- keys[order(keys$disease, keys$sex, keys$stratum, keys$age), , drop = FALSE]

  for (prefix in unique(unname(parameter_map))) {
    keys[[paste0(prefix, "_prob")]] <- NA_real_
    keys[[paste0(prefix, "_lower")]] <- NA_real_
    keys[[paste0(prefix, "_upper")]] <- NA_real_
  }

  for (i in seq_len(nrow(data))) {
    prefix <- unname(parameter_map[data$parameter[i]])
    row <- keys$age == data$age[i] &
      keys$sex == data$sex[i] &
      keys$stratum == data$stratum[i] &
      keys$disease == data$disease[i]
    keys[[paste0(prefix, "_prob")]][row] <- data$mean_probability[i]
    keys[[paste0(prefix, "_lower")]][row] <- data$lower_probability[i]
    keys[[paste0(prefix, "_upper")]][row] <- data$upper_probability[i]
  }

  row.names(keys) <- NULL
  keys
}

tidy_disbayes_fits <- function(fits) {
  rows <- lapply(fits, function(item) {
    group <- item$group
    fit <- disbayes_fit_table(item$fit)
    require_columns(fit, c("age", "inc", "rem", "cf", "prev_prob"), "disbayes fit output")
    data.frame(
      group[rep(1, nrow(fit)), , drop = FALSE],
      age = as.integer(as.numeric(fit$age)),
      inc = as.numeric(fit$inc),
      rem = as.numeric(fit$rem),
      cf = as.numeric(fit$cf),
      prev_prob = as.numeric(fit$prev_prob),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  out <- out[order(out$disease, out$sex, out$stratum, out$age), ]
  row.names(out) <- NULL
  out
}

disbayes_fit_table <- function(fit) {
  if (is.data.frame(fit)) {
    return(fit)
  }
  if (inherits(fit, "disbayes")) {
    return(disbayes_tidy_fit_table(fit))
  }
  if (is.list(fit) && is.data.frame(fit$summary)) {
    return(fit$summary)
  }
  if (is.list(fit) && is.data.frame(fit$estimates)) {
    return(fit$estimates)
  }
  out <- tryCatch(as.data.frame(fit), error = function(e) NULL)
  if (is.null(out)) {
    stop(
      "Could not convert disbayes fit output to a data frame. ",
      "The adapter assumes a data frame, `$summary`, or `$estimates` with ",
      "columns age, inc, rem, cf, and prev_prob.",
      call. = FALSE
    )
  }
  out
}

disbayes_tidy_fit_table <- function(fit) {
  tidy_fun <- getExportedValue("disbayes", "tidy")
  tidy <- tidy_fun(fit)
  estimate_col <- intersect(c("mode", "mean", "median", "estimate"), names(tidy))[1]
  if (is.na(estimate_col)) {
    stop("Could not find an estimate column in `disbayes::tidy()` output.", call. = FALSE)
  }

  keep_estimate <- function(var) {
    rows <- tidy[tidy$var == var, , drop = FALSE]
    if ("bias" %in% names(rows)) {
      rows <- rows[is.na(rows$bias) | rows$bias == 1, , drop = FALSE]
    }
    rows[c("age", estimate_col)]
  }

  inc <- keep_estimate("inc_prob")
  rem <- keep_estimate("rem_prob")
  cf <- keep_estimate("cf_prob")
  prev <- keep_estimate("prev_prob")
  names(inc)[names(inc) == estimate_col] <- "inc"
  names(rem)[names(rem) == estimate_col] <- "rem"
  names(cf)[names(cf) == estimate_col] <- "cf"
  names(prev)[names(prev) == estimate_col] <- "prev_prob"

  out <- merge(inc, rem, by = "age", all = TRUE, sort = FALSE)
  out <- merge(out, cf, by = "age", all = TRUE, sort = FALSE)
  out <- merge(out, prev, by = "age", all = TRUE, sort = FALSE)
  out[order(out$age), , drop = FALSE]
}

disbayes_to_pmslt_disease_epi <- function(solver_long, prepared, input_dir, horizon = NULL) {
  target_ages <- unique(prepared$evidence[prepared$evidence$is_target_age, c("age", "sex", "stratum", "disease")])
  base <- merge(
    target_ages,
    solver_long,
    by = c("age", "sex", "stratum", "disease"),
    all.x = TRUE,
    sort = FALSE
  )
  require_columns(base, c("inc", "rem", "cf", "prev_prob"), "disbayes mapped output")
  base$incidence_rate <- probability_to_rate(base$inc)
  base$remission_rate <- probability_to_rate(base$rem)
  base$case_fatality_rate <- probability_to_rate(base$cf)
  base$prevalence <- as.numeric(base$prev_prob)
  base <- join_explicit_excess_mortality(base, prepared$evidence)
  base <- join_raw_disability_weight(base, input_dir)
  base <- join_disease_trends(base, input_dir)

  for (col in c("incidence_apc", "cfr_apc", "prevalence_apc")) {
    if (!col %in% names(base)) {
      base[[col]] <- 0
    }
    base[[col]][is.na(base[[col]])] <- 0
  }
  if (!"disability_weight" %in% names(base)) {
    base$disability_weight <- NA_real_
  }

  if (is.null(horizon)) {
    horizon <- infer_disease_consistency_horizon(input_dir)
  }
  horizon <- validate_nonnegative_integer(horizon, "horizon")
  time_grid <- data.frame(time_step = seq.int(0, horizon), stringsAsFactors = FALSE)
  out <- merge(base, time_grid, all = TRUE)
  out$incidence_BAU <- out$incidence_rate * exp(out$incidence_apc * out$time_step)
  out$prevalence_initial <- ifelse(out$time_step == 0, out$prevalence, NA_real_)
  out$remission_rate <- out$remission_rate
  out$excess_mortality_BAU <- out$excess_mortality_rate * exp(out$cfr_apc * out$time_step)
  out$case_fatality_BAU <- out$case_fatality_rate * exp(out$cfr_apc * out$time_step)
  out$prevalence_BAU_reference <- out$prevalence * exp(out$prevalence_apc * out$time_step)
  out$input_source <- ifelse(
    is.na(out$excess_mortality_rate),
    paste0(
      "solve_disease_consistency(solver = \"disbayes\"); ",
      "excess_mortality_BAU missing because no explicit excess_mortality_rate was supplied"
    ),
    "solve_disease_consistency(solver = \"disbayes\")"
  )

  ordered_cols <- pmslt_disease_epi_schema()$columns$column
  out <- out[ordered_cols]
  out <- out[order(out$disease, out$sex, out$stratum, out$age, out$time_step), ]
  row.names(out) <- NULL
  validate_pmslt_disease_inputs(out)
  out
}

probability_to_rate <- function(x) {
  x <- as.numeric(x)
  out <- rep(NA_real_, length(x))
  ok <- !is.na(x)
  out[ok] <- -log(pmax(1 - x[ok], .Machine$double.eps))
  out
}

join_explicit_excess_mortality <- function(base, evidence) {
  excess <- evidence[
    evidence$parameter == "excess_mortality" &
      evidence$is_target_age &
      !is.na(evidence$mean_value),
    ,
    drop = FALSE
  ]
  if (nrow(excess) == 0) {
    base$excess_mortality_rate <- NA_real_
    return(base)
  }
  excess <- unique(excess[c("age", "sex", "stratum", "disease", "mean_value")])
  names(excess)[names(excess) == "mean_value"] <- "excess_mortality_rate"
  merge(
    base,
    excess,
    by = c("age", "sex", "stratum", "disease"),
    all.x = TRUE,
    sort = FALSE
  )
}

join_raw_disability_weight <- function(base, input_dir) {
  raw_path <- file.path(input_dir, "05_disease_epidemiology_raw.csv")
  if (!file.exists(raw_path)) {
    base$disability_weight <- NA_real_
    return(base)
  }
  raw <- utils::read.csv(raw_path, stringsAsFactors = FALSE, na.strings = c("", "NA"))
  if (!"disability_weight" %in% names(raw)) {
    base$disability_weight <- NA_real_
    return(base)
  }
  raw_dw <- expand_age_banded_values(
    unique(raw[c("age_start", "age_end", "sex", "stratum", "disease", "disability_weight")]),
    value_cols = "disability_weight"
  )
  merge(base, raw_dw, by = c("age", "sex", "stratum", "disease"), all.x = TRUE, sort = FALSE)
}

join_disease_trends <- function(base, input_dir) {
  trend_path <- file.path(input_dir, "07_bau_trends.csv")
  if (!file.exists(trend_path)) {
    return(base)
  }
  trends <- utils::read.csv(trend_path, stringsAsFactors = FALSE, na.strings = c("", "NA"))
  keep <- intersect(c("disease", "incidence_apc", "cfr_apc", "prevalence_apc"), names(trends))
  if ("disease" %in% keep) {
    base <- merge(base, unique(trends[keep]), by = "disease", all.x = TRUE, sort = FALSE)
  }
  base
}

write_disbayes_execution_outputs <- function(output_dir,
                                             output_file,
                                             pmslt_disease_epi,
                                             solver_long,
                                             fit_summary,
                                             prepared,
                                             overwrite) {
  outputs <- list(
    pmslt_disease_epi,
    solver_long,
    fit_summary,
    prepared$evidence,
    prepared$age_audit,
    prepared$diagnostics
  )
  names(outputs) <- c(
    output_file,
    file.path(output_dir, "disbayes_solver_long.csv"),
    file.path(output_dir, "disbayes_fit_summary.csv"),
    file.path(output_dir, "disbayes_rate_conversion_audit.csv"),
    file.path(output_dir, "disbayes_evidence_audit.csv"),
    file.path(output_dir, "disbayes_group_diagnostics.csv")
  )
  for (path in names(outputs)) {
    if (file.exists(path) && !isTRUE(overwrite)) {
      stop(
        "File already exists: ", path,
        ". Use `overwrite = TRUE` to replace it.",
        call. = FALSE
      )
    }
    utils::write.csv(outputs[[path]], path, row.names = FALSE, na = "")
  }
}
