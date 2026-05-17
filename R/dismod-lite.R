#' Solve simple DisMod-style epidemiological consistency equations
#'
#' Reads a PMSLT `input_raw` directory, expands coarse disease age groups to the
#' template age grid, and fills missing values where they can be identified from
#' simple steady-state illness-death equations. This is intentionally a small
#' deterministic helper, not a replacement for full DisMod-MR.
#'
#' @param input_dir Directory created by [draft_input_templates()].
#' @param output_dir Directory where solved CSV files should be written.
#' @param overwrite Logical. Should existing output files be overwritten?
#' @param consistency_tolerance Relative tolerance used when flagging supplied
#'   values that do not agree with the steady-state equations.
#' @param uncertainty Logical. If `TRUE`, propagate uncertainty by Monte Carlo
#'   sampling from rows with `lower_95` and `upper_95` values.
#' @param draws Number of Monte Carlo draws when `uncertainty = TRUE`.
#' @param seed Optional random seed for reproducible uncertainty intervals.
#'
#' @return Invisibly returns a list containing solved wide results, solved long
#'   results, and diagnostics.
#' @export
solve_dismod_lite <- function(input_dir = "pmslt_inputs_raw",
                              output_dir = file.path(input_dir, "dismod_lite_results"),
                              overwrite = FALSE,
                              consistency_tolerance = 0.15,
                              uncertainty = FALSE,
                              draws = 2000,
                              seed = NULL) {
  if (!dir.exists(input_dir)) {
    stop("`input_dir` does not exist: ", input_dir, call. = FALSE)
  }
  consistency_tolerance <- validate_nonnegative_number(consistency_tolerance, "consistency_tolerance")
  draws <- validate_positive_integer(draws, "draws")
  if (!is.null(seed)) {
    set.seed(seed)
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
  observations <- dismod_observations(wide, long)

  expanded <- expand_dismod_observations(observations, target_grid)
  solved_wide <- solve_dismod_rows(
    expanded = expanded,
    consistency_tolerance = consistency_tolerance,
    uncertainty = isTRUE(uncertainty),
    draws = draws
  )
  solved_long <- dismod_wide_to_long_results(solved_wide)
  diagnostics <- dismod_diagnostics(solved_wide)

  write_dismod_lite_outputs(
    output_dir = output_dir,
    solved_wide = solved_wide,
    solved_long = solved_long,
    diagnostics = diagnostics,
    overwrite = overwrite
  )

  message("DisMod-lite outputs written to: ", normalizePath(output_dir))
  invisible(list(
    solved_wide = solved_wide,
    solved_long = solved_long,
    diagnostics = diagnostics
  ))
}

read_optional_csv <- function(path) {
  if (!file.exists(path)) {
    return(NULL)
  }
  utils::read.csv(path, stringsAsFactors = FALSE, na.strings = c("", "NA"))
}

dismod_target_grid <- function(wide, long) {
  grid_cols <- c("age_start", "age_end", "age_label", "sex", "stratum", "disease")
  if (!is.null(long)) {
    require_columns(long, c(grid_cols, "parameter"), "06_dismod_input_skeleton.csv")
    return(unique(long[grid_cols]))
  }
  require_columns(wide, grid_cols, "05_disease_epidemiology_raw.csv")
  unique(wide[grid_cols])
}

dismod_observations <- function(wide, long) {
  rows <- list()
  if (!is.null(wide)) {
    rows[["raw"]] <- dismod_wide_to_long_input(wide)
  }
  if (!is.null(long)) {
    rows[["long"]] <- dismod_long_input(long)
  }
  out <- do.call(rbind, rows)
  out <- out[!is.na(out$mean_value), , drop = FALSE]
  numeric_cols <- c("age_start", "age_end", "mean_value", "lower_95", "upper_95")
  out[numeric_cols] <- lapply(out[numeric_cols], as.numeric)
  out
}

dismod_wide_to_long_input <- function(wide) {
  param_map <- c(
    incidence_rate = "incidence",
    prevalence = "prevalence",
    remission_rate = "remission",
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
      input_source = "05_disease_epidemiology_raw.csv",
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

dismod_long_input <- function(long) {
  grid_cols <- c("age_start", "age_end", "age_label", "sex", "stratum", "disease")
  require_columns(long, c(grid_cols, "parameter", "mean_value"), "06_dismod_input_skeleton.csv")
  lower <- if ("lower_95" %in% names(long)) as.numeric(long$lower_95) else NA_real_
  upper <- if ("upper_95" %in% names(long)) as.numeric(long$upper_95) else NA_real_

  data.frame(
    long[grid_cols],
    parameter = normalize_dismod_parameter(long$parameter),
    mean_value = as.numeric(long$mean_value),
    lower_95 = lower,
    upper_95 = upper,
    input_source = "06_dismod_input_skeleton.csv",
    stringsAsFactors = FALSE
  )
}

normalize_dismod_parameter <- function(x) {
  aliases <- c(
    incidence_rate = "incidence",
    prevalence_rate = "prevalence",
    remission_rate = "remission",
    excess_mortality_rate = "excess_mortality",
    case_fatality_rate = "case_fatality"
  )
  x <- as.character(x)
  ifelse(x %in% names(aliases), unname(aliases[x]), x)
}

expand_dismod_observations <- function(observations, target_grid) {
  params <- c("incidence", "prevalence", "remission", "excess_mortality", "case_fatality")
  target <- merge(target_grid, data.frame(parameter = params, stringsAsFactors = FALSE), all = TRUE)
  target$.row_id <- seq_len(nrow(target))

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
    match <- best_age_match(row, candidates)
    data.frame(
      row[c("age_start", "age_end", "age_label", "sex", "stratum", "disease", "parameter")],
      mean_value = match$mean_value,
      lower_95 = match$lower_95,
      upper_95 = match$upper_95,
      value_source = match$value_source,
      age_source = match$age_source,
      source_age_start = match$source_age_start,
      source_age_end = match$source_age_end,
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

best_age_match <- function(target, candidates) {
  empty_match <- list(
    mean_value = NA_real_,
    lower_95 = NA_real_,
    upper_95 = NA_real_,
    value_source = NA_character_,
    age_source = "missing",
    source_age_start = NA_real_,
    source_age_end = NA_real_
  )
  if (nrow(candidates) == 0) {
    return(empty_match)
  }

  candidates$overlap <- age_overlap(
    target$age_start,
    target$age_end,
    candidates$age_start,
    candidates$age_end
  )
  candidates <- candidates[candidates$overlap > 0, , drop = FALSE]
  if (nrow(candidates) == 0) {
    return(empty_match)
  }

  candidates$priority <- ifelse(
    candidates$age_start == target$age_start & candidates$age_end == target$age_end,
    3L,
    ifelse(candidates$age_start <= target$age_start & candidates$age_end >= target$age_end, 2L, 1L)
  )
  candidates$source_priority <- ifelse(candidates$input_source == "06_dismod_input_skeleton.csv", 2L, 1L)
  candidates <- candidates[order(-candidates$priority, -candidates$source_priority, -candidates$overlap), , drop = FALSE]
  best <- candidates[1, , drop = FALSE]

  age_source <- switch(
    as.character(best$priority),
    "3" = "exact",
    "2" = "disaggregated_constant",
    "partial_overlap"
  )
  list(
    mean_value = best$mean_value,
    lower_95 = best$lower_95,
    upper_95 = best$upper_95,
    value_source = best$input_source,
    age_source = age_source,
    source_age_start = best$age_start,
    source_age_end = best$age_end
  )
}

age_overlap <- function(target_start, target_end, source_start, source_end) {
  target_end <- ifelse(is.infinite(target_end), 200, target_end)
  source_end <- ifelse(is.infinite(source_end), 200, source_end)
  pmax(0, pmin(target_end, source_end) - pmax(target_start, source_start) + 1)
}

solve_dismod_rows <- function(expanded, consistency_tolerance, uncertainty, draws) {
  keys <- unique(expanded[c("age_start", "age_end", "age_label", "sex", "stratum", "disease")])
  rows <- lapply(seq_len(nrow(keys)), function(i) {
    key <- keys[i, , drop = FALSE]
    values <- expanded[
      expanded$age_start == key$age_start &
        expanded$age_end == key$age_end &
        expanded$sex == key$sex &
        expanded$stratum == key$stratum &
        expanded$disease == key$disease,
      ,
      drop = FALSE
    ]
    solve_one_dismod_row(key, values, consistency_tolerance, uncertainty, draws)
  })
  do.call(rbind, rows)
}

solve_one_dismod_row <- function(key, values, consistency_tolerance, uncertainty, draws) {
  get_param <- function(parameter, column) {
    value <- values[values$parameter == parameter, column]
    if (length(value) == 0) {
      return(NA)
    }
    value[[1]]
  }
  incidence <- as.numeric(get_param("incidence", "mean_value"))
  prevalence <- as.numeric(get_param("prevalence", "mean_value"))
  remission <- as.numeric(get_param("remission", "mean_value"))
  excess_mortality <- as.numeric(get_param("excess_mortality", "mean_value"))
  case_fatality <- as.numeric(get_param("case_fatality", "mean_value"))

  sources <- stats::setNames(
    vapply(c("incidence", "prevalence", "remission", "excess_mortality", "case_fatality"), function(parameter) {
      source <- get_param(parameter, "age_source")
      if (is.na(source)) "missing" else source
    }, character(1)),
    c("incidence", "prevalence", "remission", "excess_mortality", "case_fatality")
  )
  warnings <- character()

  if (is.na(excess_mortality) && !is.na(case_fatality)) {
    excess_mortality <- case_fatality
    sources[["excess_mortality"]] <- "derived_from_case_fatality"
  }
  if (is.na(case_fatality) && !is.na(excess_mortality)) {
    case_fatality <- excess_mortality
    sources[["case_fatality"]] <- "derived_from_excess_mortality"
  }

  solved <- solve_illness_death_values(
    incidence = incidence,
    prevalence = prevalence,
    remission = remission,
    excess_mortality = excess_mortality
  )
  incidence <- solved$incidence
  prevalence <- solved$prevalence
  remission <- solved$remission
  excess_mortality <- solved$excess_mortality
  if (!is.na(solved$solved_parameter)) {
    sources[[solved$solved_parameter]] <- "solved"
    if (solved$solved_parameter == "excess_mortality" && is.na(case_fatality)) {
      case_fatality <- excess_mortality
      sources[["case_fatality"]] <- "derived_from_excess_mortality"
    }
  }
  if (!is.na(solved$warning)) {
    warnings <- c(warnings, solved$warning)
  }

  consistency <- illness_death_residual(incidence, prevalence, remission, excess_mortality)
  if (!is.na(consistency$relative_difference) &&
      consistency$relative_difference > consistency_tolerance) {
    warnings <- c(warnings, paste0(
      "Supplied values are not steady-state consistent; relative difference = ",
      signif(consistency$relative_difference, 3)
    ))
  }
  if (!is.na(case_fatality) && !is.na(excess_mortality) &&
      abs(case_fatality - excess_mortality) > consistency_tolerance * max(abs(excess_mortality), 1e-12)) {
    warnings <- c(warnings, "case_fatality and excess_mortality differ; both retained")
  }

  intervals <- if (isTRUE(uncertainty)) {
    monte_carlo_dismod_intervals(values, draws)
  } else {
    empty_dismod_intervals()
  }

  invalid <- invalid_dismod_values(incidence, prevalence, remission, excess_mortality, case_fatality)
  warnings <- c(warnings, invalid)
  if (isTRUE(uncertainty) && !is.na(intervals$warning)) {
    warnings <- c(warnings, intervals$warning)
  }

  data.frame(
    key,
    incidence_rate = incidence,
    incidence_rate_lower_95 = intervals$incidence_lower_95,
    incidence_rate_upper_95 = intervals$incidence_upper_95,
    prevalence = prevalence,
    prevalence_lower_95 = intervals$prevalence_lower_95,
    prevalence_upper_95 = intervals$prevalence_upper_95,
    remission_rate = remission,
    remission_rate_lower_95 = intervals$remission_lower_95,
    remission_rate_upper_95 = intervals$remission_upper_95,
    excess_mortality_rate = excess_mortality,
    excess_mortality_rate_lower_95 = intervals$excess_mortality_lower_95,
    excess_mortality_rate_upper_95 = intervals$excess_mortality_upper_95,
    case_fatality_rate = case_fatality,
    case_fatality_rate_lower_95 = intervals$case_fatality_lower_95,
    case_fatality_rate_upper_95 = intervals$case_fatality_upper_95,
    incidence_source = sources[["incidence"]],
    prevalence_source = sources[["prevalence"]],
    remission_source = sources[["remission"]],
    excess_mortality_source = sources[["excess_mortality"]],
    case_fatality_source = sources[["case_fatality"]],
    consistency_relative_difference = consistency$relative_difference,
    solver_status = if (length(warnings) == 0) "ok" else "check",
    solver_notes = paste(unique(warnings), collapse = " | "),
    stringsAsFactors = FALSE
  )
}

solve_illness_death_values <- function(incidence, prevalence, remission, excess_mortality) {
  supplied <- !is.na(c(
    incidence = incidence,
    prevalence = prevalence,
    remission = remission,
    excess_mortality = excess_mortality
  ))
  if (sum(supplied) < 3) {
    return(list(
      incidence = incidence,
      prevalence = prevalence,
      remission = remission,
      excess_mortality = excess_mortality,
      solved_parameter = NA_character_,
      warning = NA_character_
    ))
  }

  solved_parameter <- NA_character_
  warning <- NA_character_
  if (is.na(prevalence) && !is.na(incidence) && !is.na(remission) && !is.na(excess_mortality)) {
    prevalence <- incidence / (incidence + remission + excess_mortality)
    solved_parameter <- "prevalence"
  } else if (is.na(incidence) && !is.na(prevalence) && !is.na(remission) && !is.na(excess_mortality)) {
    incidence <- prevalence * (remission + excess_mortality) / (1 - prevalence)
    solved_parameter <- "incidence"
  } else if (is.na(remission) && !is.na(incidence) && !is.na(prevalence) && !is.na(excess_mortality)) {
    remission <- incidence * (1 - prevalence) / prevalence - excess_mortality
    solved_parameter <- "remission"
  } else if (is.na(excess_mortality) && !is.na(incidence) && !is.na(prevalence) && !is.na(remission)) {
    excess_mortality <- incidence * (1 - prevalence) / prevalence - remission
    solved_parameter <- "excess_mortality"
  }

  values <- c(incidence, prevalence, remission, excess_mortality)
  if (any(!is.na(values) & !is.finite(values)) || any(!is.na(values) & values < 0)) {
    warning <- "Equation produced an invalid negative or non-finite value"
  }

  list(
    incidence = incidence,
    prevalence = prevalence,
    remission = remission,
    excess_mortality = excess_mortality,
    solved_parameter = solved_parameter,
    warning = warning
  )
}

monte_carlo_dismod_intervals <- function(values, draws) {
  params <- c("incidence", "prevalence", "remission", "excess_mortality", "case_fatality")
  observed <- lapply(params, function(parameter) {
    row <- values[values$parameter == parameter, , drop = FALSE]
    if (nrow(row) == 0) {
      return(list(mean = NA_real_, lower = NA_real_, upper = NA_real_))
    }
    list(
      mean = as.numeric(row$mean_value[[1]]),
      lower = as.numeric(row$lower_95[[1]]),
      upper = as.numeric(row$upper_95[[1]])
    )
  })
  names(observed) <- params

  has_any_interval <- any(vapply(observed, has_sampling_interval, logical(1)))
  if (!has_any_interval) {
    out <- empty_dismod_intervals()
    out$warning <- "uncertainty = TRUE but no usable lower_95/upper_95 bounds were available"
    return(out)
  }

  samples <- lapply(names(observed), function(parameter) {
    sample_dismod_parameter(
      mean = observed[[parameter]]$mean,
      lower = observed[[parameter]]$lower,
      upper = observed[[parameter]]$upper,
      parameter = parameter,
      draws = draws
    )
  })
  names(samples) <- params

  solved <- data.frame(
    incidence = samples$incidence,
    prevalence = samples$prevalence,
    remission = samples$remission,
    excess_mortality = samples$excess_mortality,
    case_fatality = samples$case_fatality
  )

  if (all(is.na(solved$excess_mortality)) && any(!is.na(solved$case_fatality))) {
    solved$excess_mortality <- solved$case_fatality
  }
  if (all(is.na(solved$case_fatality)) && any(!is.na(solved$excess_mortality))) {
    solved$case_fatality <- solved$excess_mortality
  }

  solved_rows <- lapply(seq_len(draws), function(i) {
    row <- solve_illness_death_values(
      incidence = solved$incidence[[i]],
      prevalence = solved$prevalence[[i]],
      remission = solved$remission[[i]],
      excess_mortality = solved$excess_mortality[[i]]
    )
    c(
      incidence = row$incidence,
      prevalence = row$prevalence,
      remission = row$remission,
      excess_mortality = row$excess_mortality
    )
  })
  solved_matrix <- do.call(rbind, solved_rows)
  solved$incidence <- solved_matrix[, "incidence"]
  solved$prevalence <- solved_matrix[, "prevalence"]
  solved$remission <- solved_matrix[, "remission"]
  solved$excess_mortality <- solved_matrix[, "excess_mortality"]
  if (all(is.na(samples$case_fatality)) && any(!is.na(solved$excess_mortality))) {
    solved$case_fatality <- solved$excess_mortality
  }

  valid <- is.finite(solved$incidence) | is.na(solved$incidence)
  valid <- valid & (is.finite(solved$prevalence) | is.na(solved$prevalence))
  valid <- valid & (is.finite(solved$remission) | is.na(solved$remission))
  valid <- valid & (is.finite(solved$excess_mortality) | is.na(solved$excess_mortality))
  valid <- valid & (is.finite(solved$case_fatality) | is.na(solved$case_fatality))
  valid <- valid & (is.na(solved$incidence) | solved$incidence >= 0)
  valid <- valid & (is.na(solved$prevalence) | (solved$prevalence >= 0 & solved$prevalence < 1))
  valid <- valid & (is.na(solved$remission) | solved$remission >= 0)
  valid <- valid & (is.na(solved$excess_mortality) | solved$excess_mortality >= 0)
  valid <- valid & (is.na(solved$case_fatality) | solved$case_fatality >= 0)
  solved <- solved[valid, , drop = FALSE]

  out <- empty_dismod_intervals()
  if (nrow(solved) == 0) {
    out$warning <- "Monte Carlo uncertainty propagation produced no valid draws"
    return(out)
  }

  for (parameter in params) {
    interval <- quantile_interval(solved[[parameter]])
    out[[paste0(parameter, "_lower_95")]] <- interval[["lower"]]
    out[[paste0(parameter, "_upper_95")]] <- interval[["upper"]]
  }
  if (nrow(solved) < draws) {
    out$warning <- paste0(draws - nrow(solved), " invalid Monte Carlo draws were discarded")
  }
  out
}

has_sampling_interval <- function(x) {
  !is.na(x$mean) &&
    !is.na(x$lower) &&
    !is.na(x$upper) &&
    is.finite(x$mean) &&
    is.finite(x$lower) &&
    is.finite(x$upper) &&
    x$upper > x$lower
}

sample_dismod_parameter <- function(mean, lower, upper, parameter, draws) {
  if (is.na(mean)) {
    return(rep(NA_real_, draws))
  }
  if (!has_sampling_interval(list(mean = mean, lower = lower, upper = upper))) {
    return(rep(mean, draws))
  }

  if (parameter == "prevalence") {
    if (lower > 0 && upper < 1 && mean > 0 && mean < 1) {
      mu <- stats::qlogis(mean)
      sigma <- (stats::qlogis(upper) - stats::qlogis(lower)) / (2 * 1.96)
      return(stats::plogis(stats::rnorm(draws, mean = mu, sd = sigma)))
    }
    return(stats::runif(draws, min = max(0, lower), max = min(1, upper)))
  }

  if (lower > 0 && mean > 0) {
    mu <- log(mean)
    sigma <- (log(upper) - log(lower)) / (2 * 1.96)
    return(stats::rlnorm(draws, meanlog = mu, sdlog = sigma))
  }
  stats::runif(draws, min = max(0, lower), max = max(0, upper))
}

quantile_interval <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) == 0) {
    return(c(lower = NA_real_, upper = NA_real_))
  }
  out <- stats::quantile(x, probs = c(0.025, 0.975), names = FALSE, type = 8)
  c(lower = out[[1]], upper = out[[2]])
}

empty_dismod_intervals <- function() {
  list(
    incidence_lower_95 = NA_real_,
    incidence_upper_95 = NA_real_,
    prevalence_lower_95 = NA_real_,
    prevalence_upper_95 = NA_real_,
    remission_lower_95 = NA_real_,
    remission_upper_95 = NA_real_,
    excess_mortality_lower_95 = NA_real_,
    excess_mortality_upper_95 = NA_real_,
    case_fatality_lower_95 = NA_real_,
    case_fatality_upper_95 = NA_real_,
    warning = NA_character_
  )
}

illness_death_residual <- function(incidence, prevalence, remission, excess_mortality) {
  if (any(is.na(c(incidence, prevalence, remission, excess_mortality)))) {
    return(list(relative_difference = NA_real_))
  }
  implied <- incidence / (incidence + remission + excess_mortality)
  list(relative_difference = abs(prevalence - implied) / max(abs(implied), 1e-12))
}

invalid_dismod_values <- function(incidence, prevalence, remission, excess_mortality, case_fatality) {
  values <- c(
    incidence_rate = incidence,
    prevalence = prevalence,
    remission_rate = remission,
    excess_mortality_rate = excess_mortality,
    case_fatality_rate = case_fatality
  )
  warnings <- names(values)[!is.na(values) & values < 0]
  out <- if (length(warnings) > 0) {
    paste("Negative values:", paste(warnings, collapse = ", "))
  } else {
    character()
  }
  if (!is.na(prevalence) && prevalence >= 1) {
    out <- c(out, "prevalence must be less than 1 for equation solving")
  }
  out
}

dismod_wide_to_long_results <- function(wide) {
  param_map <- c(
    incidence_rate = "incidence",
    prevalence = "prevalence",
    remission_rate = "remission",
    excess_mortality_rate = "excess_mortality",
    case_fatality_rate = "case_fatality"
  )
  grid_cols <- c("age_start", "age_end", "age_label", "sex", "stratum", "disease")
  rows <- lapply(names(param_map), function(col) {
    parameter <- unname(param_map[[col]])
    source_col <- paste0(parameter, "_source")
    lower_col <- paste0(col, "_lower_95")
    upper_col <- paste0(col, "_upper_95")
    data.frame(
      wide[grid_cols],
      parameter = parameter,
      mean_value = wide[[col]],
      lower_95 = wide[[lower_col]],
      upper_95 = wide[[upper_col]],
      value_source = wide[[source_col]],
      solver_status = wide$solver_status,
      solver_notes = wide$solver_notes,
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

dismod_diagnostics <- function(wide) {
  data.frame(
    wide[c("age_start", "age_end", "age_label", "sex", "stratum", "disease")],
    solver_status = wide$solver_status,
    consistency_relative_difference = wide$consistency_relative_difference,
    solver_notes = wide$solver_notes,
    stringsAsFactors = FALSE
  )
}

write_dismod_lite_outputs <- function(output_dir, solved_wide, solved_long, diagnostics, overwrite) {
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }
  outputs <- list(
    "dismod_lite_solved_wide.csv" = solved_wide,
    "dismod_lite_solved_long.csv" = solved_long,
    "dismod_lite_diagnostics.csv" = diagnostics
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

require_columns <- function(data, required, label) {
  missing <- setdiff(required, names(data))
  if (length(missing) > 0) {
    stop("`", label, "` is missing: ", paste(missing, collapse = ", "), call. = FALSE)
  }
}
