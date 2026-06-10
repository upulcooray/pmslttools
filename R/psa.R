#' Describe the PSA parameter-draw schema
#'
#' Defines the stable schema-backed input fields that the PSA layer can draw
#' from. Fields without uncertainty bounds are retained as point estimates so
#' the deterministic workflow contract remains unchanged.
#'
#' @return A data frame describing PSA parameter groups and source columns.
#' @export
psa_parameter_draw_schema <- function() {
  data.frame(
    parameter_group = c(
      "solver_evidence", "relative_risk", "disease_epi",
      "direct_effect", "cost"
    ),
    source_file = c(
      "06_dismod_input_skeleton.csv",
      "09_relative_risks.csv",
      "pmslt_disease_epi.csv",
      "10_direct_intervention_effects.csv",
      "12_costs.csv"
    ),
    source_stage = c(
      "solver", "raw_intervention", "pmslt_ready",
      "raw_intervention", "raw_cost"
    ),
    key_columns = c(
      "age_start; age_end; sex; stratum; disease; parameter",
      "age_start; sex; stratum; risk_factor; disease; risk_category",
      "age; sex; stratum; disease; time_step",
      "age_start; age_end; sex; stratum; disease; intervention",
      "age_start; age_end; sex; stratum; disease"
    ),
    mean_column = c(
      "mean_value", "rr", "schema numeric columns",
      "incidence_rr; cfr_rr; morbidity_rr; coverage",
      "disease_cost; background_cost"
    ),
    lower_column = c("lower_95", "rr_lower", NA_character_, NA_character_, NA_character_),
    upper_column = c("upper_95", "rr_upper", NA_character_, NA_character_, NA_character_),
    distribution = c(
      "lognormal for positive bounded parameters; otherwise truncated normal",
      "lognormal when rr_lower and rr_upper are available",
      "point",
      "point",
      "point"
    ),
    deterministic_consumer = c(
      "disease consistency solver inputs",
      "calculate_pif_from_inputs(); run_pmslt_interventions()",
      "run_pmslt_interventions()",
      "run_pmslt_interventions()",
      "future deterministic cost module"
    ),
    stringsAsFactors = FALSE
  )
}

#' Draw PSA parameters from schema-backed PMSLT inputs
#'
#' Samples only from uncertainty fields that already exist in stable package
#' schemas. Inputs without uncertainty bounds are copied as point estimates for
#' every draw.
#'
#' @param draws Number of PSA draws.
#' @param seed Optional random seed for reproducible draws.
#' @param solver_evidence Optional `06_dismod_input_skeleton.csv` data frame or
#'   path.
#' @param disease_epi Optional PMSLT-ready disease epidemiology data frame or
#'   path.
#' @param relative_risks Optional `09_relative_risks.csv` data frame or path.
#' @param direct_effects Optional `10_direct_intervention_effects.csv` data
#'   frame or path.
#' @param costs Optional `12_costs.csv` data frame or path.
#'
#' @return A data frame with one row per draw and schema-backed parameter.
#' @export
draw_psa_parameters <- function(draws,
                                seed = NULL,
                                solver_evidence = NULL,
                                disease_epi = NULL,
                                relative_risks = NULL,
                                direct_effects = NULL,
                                costs = NULL) {
  draws <- validate_psa_draw_count(draws)
  old_seed <- set_psa_seed(seed)
  on.exit(restore_psa_seed(old_seed), add = TRUE)

  rows <- list()
  if (!is.null(solver_evidence)) {
    rows[[length(rows) + 1L]] <- draw_solver_evidence_parameters(solver_evidence, draws)
  }
  if (!is.null(disease_epi)) {
    rows[[length(rows) + 1L]] <- draw_disease_epi_parameters(disease_epi, draws)
  }
  if (!is.null(relative_risks)) {
    rows[[length(rows) + 1L]] <- draw_relative_risk_parameters(relative_risks, draws)
  }
  if (!is.null(direct_effects)) {
    rows[[length(rows) + 1L]] <- draw_direct_effect_parameters(direct_effects, draws)
  }
  if (!is.null(costs)) {
    rows[[length(rows) + 1L]] <- draw_cost_parameters(costs, draws)
  }

  if (length(rows) == 0) {
    return(empty_psa_parameter_draws())
  }
  out <- do.call(rbind, rows)
  row.names(out) <- NULL
  out
}

#' Run PSA over deterministic PMSLT intervention workflows
#'
#' Repeats [run_pmslt_interventions()] across schema-backed PSA draws. This
#' function does not change deterministic function arguments or internals.
#'
#' @param disease_epi PMSLT-ready disease epidemiology data frame or path.
#' @param risk_prevalence Optional `08_risk_factor_prevalence.csv` data frame or
#'   path.
#' @param relative_risks Optional `09_relative_risks.csv` data frame or path.
#' @param direct_effects Optional `10_direct_intervention_effects.csv` data
#'   frame or path.
#' @param interventions Optional intervention arms passed to
#'   [run_pmslt_interventions()].
#' @param draws Number of PSA draws.
#' @param seed Optional random seed for reproducible draws.
#' @param cohort_size Radix cohort size for each disease lifetable.
#' @param interval_width Uncertainty interval width. Defaults to 0.95.
#'
#' @return A list with draw-level outputs, parameter draws, interval summaries,
#'   and draw failures.
#' @export
run_psa_interventions <- function(disease_epi,
                                  risk_prevalence = NULL,
                                  relative_risks = NULL,
                                  direct_effects = NULL,
                                  interventions = NULL,
                                  draws = 100,
                                  seed = NULL,
                                  cohort_size = 1000,
                                  interval_width = 0.95) {
  draws <- validate_psa_draw_count(draws)
  validate_psa_interval_width(interval_width)

  disease_epi <- read_psa_disease_epi(disease_epi)
  risk_prevalence <- if (is.null(risk_prevalence)) NULL else read_psa_raw_table(risk_prevalence, "08_risk_factor_prevalence")
  relative_risks <- if (is.null(relative_risks)) NULL else read_psa_raw_table(relative_risks, "09_relative_risks")
  direct_effects <- if (is.null(direct_effects)) NULL else read_psa_raw_table(direct_effects, "10_direct_intervention_effects")

  if (is.null(risk_prevalence) != is.null(relative_risks)) {
    stop("Supply both `risk_prevalence` and `relative_risks` for PIF-based PSA.", call. = FALSE)
  }

  parameter_draws <- draw_psa_parameters(
    draws = draws,
    seed = seed,
    disease_epi = disease_epi,
    relative_risks = relative_risks,
    direct_effects = direct_effects
  )

  old_seed <- set_psa_seed(seed)
  on.exit(restore_psa_seed(old_seed), add = TRUE)

  output_rows <- list()
  failure_rows <- list()
  for (draw in seq_len(draws)) {
    rr_draw <- if (is.null(relative_risks)) NULL else apply_relative_risk_draw(relative_risks, parameter_draws, draw)
    direct_draw <- direct_effects
    result <- tryCatch(
      run_pmslt_interventions(
        disease_epi = disease_epi,
        risk_prevalence = risk_prevalence,
        relative_risks = rr_draw,
        direct_effects = direct_draw,
        interventions = interventions,
        cohort_size = cohort_size
      ),
      error = function(error) error
    )

    if (inherits(result, "error")) {
      failure_rows[[length(failure_rows) + 1L]] <- data.frame(
        draw = draw,
        parameter_group = "intervention_workflow",
        message = conditionMessage(result),
        stringsAsFactors = FALSE
      )
    } else {
      result$draw <- draw
      output_rows[[length(output_rows) + 1L]] <- result
    }
  }

  draw_outputs <- if (length(output_rows) == 0) {
    data.frame()
  } else {
    out <- do.call(rbind, output_rows)
    row.names(out) <- NULL
    out
  }
  failures <- if (length(failure_rows) == 0) {
    empty_psa_failures()
  } else {
    out <- do.call(rbind, failure_rows)
    row.names(out) <- NULL
    out
  }

  list(
    draw_outputs = draw_outputs,
    parameter_draws = parameter_draws,
    summary = summarise_psa_draws(draw_outputs, interval_width = interval_width),
    failures = failures
  )
}

#' Summarise PSA draw-level outputs
#'
#' @param draw_outputs Data frame returned in the `draw_outputs` element from a
#'   PSA runner.
#' @param by Grouping columns for interval summaries.
#' @param interval_width Uncertainty interval width.
#'
#' @return A data frame with mean and lower/upper interval columns.
#' @export
summarise_psa_draws <- function(draw_outputs,
                                by = "intervention",
                                interval_width = 0.95) {
  validate_psa_interval_width(interval_width)
  if (!is.data.frame(draw_outputs) || nrow(draw_outputs) == 0) {
    return(data.frame())
  }
  require_columns(draw_outputs, "draw", "draw_outputs")

  by <- as.character(by)
  missing_by <- setdiff(by, names(draw_outputs))
  if (length(missing_by) > 0) {
    stop("`draw_outputs` is missing PSA summary grouping column `", missing_by[[1]], "`.", call. = FALSE)
  }

  metric_cols <- intersect(
    c(
      "delta_mortality", "delta_morbidity", "disease_mortality_BAU",
      "disease_mortality_Int", "disease_morbidity_BAU",
      "disease_morbidity_Int"
    ),
    names(draw_outputs)
  )
  if (length(metric_cols) == 0) {
    return(unique(draw_outputs[by]))
  }

  draw_summary <- stats::aggregate(
    draw_outputs[metric_cols],
    by = draw_outputs[c("draw", by)],
    FUN = sum,
    na.rm = TRUE
  )
  group_key <- interaction(draw_summary[by], drop = TRUE, sep = "\r")
  groups <- split(draw_summary, group_key)
  probs <- c((1 - interval_width) / 2, 1 - (1 - interval_width) / 2)

  rows <- lapply(groups, function(group) {
    first <- group[1, by, drop = FALSE]
    for (metric in metric_cols) {
      values <- as.numeric(group[[metric]])
      qs <- stats::quantile(values, probs = probs, na.rm = TRUE, names = FALSE, type = 8)
      first[[paste0(metric, "_mean")]] <- mean(values, na.rm = TRUE)
      first[[paste0(metric, "_lower")]] <- qs[[1]]
      first[[paste0(metric, "_upper")]] <- qs[[2]]
    }
    first
  })

  out <- do.call(rbind, rows)
  row.names(out) <- NULL
  out
}

empty_psa_parameter_draws <- function() {
  data.frame(
    draw = integer(),
    parameter_group = character(),
    source_file = character(),
    row_id = integer(),
    parameter = character(),
    mean_value = numeric(),
    lower_95 = numeric(),
    upper_95 = numeric(),
    draw_value = numeric(),
    distribution = character(),
    stringsAsFactors = FALSE
  )
}

empty_psa_failures <- function() {
  data.frame(
    draw = integer(),
    parameter_group = character(),
    message = character(),
    stringsAsFactors = FALSE
  )
}

draw_solver_evidence_parameters <- function(solver_evidence, draws) {
  data <- read_psa_raw_table(solver_evidence, "06_dismod_input_skeleton")
  require_columns(data, c("parameter", "mean_value", "lower_95", "upper_95"), "06_dismod_input_skeleton.csv")
  draw_numeric_rows(
    data = data,
    draws = draws,
    parameter_group = "solver_evidence",
    source_file = "06_dismod_input_skeleton.csv",
    parameter_col = "parameter",
    mean_col = "mean_value",
    lower_col = "lower_95",
    upper_col = "upper_95",
    point_distribution = "point"
  )
}

draw_relative_risk_parameters <- function(relative_risks, draws) {
  data <- read_psa_raw_table(relative_risks, "09_relative_risks")
  require_columns(data, c("rr", "rr_lower", "rr_upper"), "09_relative_risks.csv")
  draw_numeric_rows(
    data = data,
    draws = draws,
    parameter_group = "relative_risk",
    source_file = "09_relative_risks.csv",
    parameter_col = NULL,
    mean_col = "rr",
    lower_col = "rr_lower",
    upper_col = "rr_upper",
    point_distribution = "point"
  )
}

draw_disease_epi_parameters <- function(disease_epi, draws) {
  data <- read_psa_disease_epi(disease_epi)
  cols <- intersect(
    c(
      "incidence_BAU", "prevalence_initial", "remission_rate",
      "excess_mortality_BAU", "case_fatality_BAU", "disability_weight"
    ),
    names(data)
  )
  draw_point_columns(data, draws, "disease_epi", "pmslt_disease_epi.csv", cols)
}

draw_direct_effect_parameters <- function(direct_effects, draws) {
  data <- read_psa_raw_table(direct_effects, "10_direct_intervention_effects")
  cols <- intersect(c("incidence_rr", "cfr_rr", "morbidity_rr", "coverage"), names(data))
  draw_point_columns(data, draws, "direct_effect", "10_direct_intervention_effects.csv", cols)
}

draw_cost_parameters <- function(costs, draws) {
  data <- read_psa_raw_table(costs, "12_costs")
  cols <- intersect(c("disease_cost", "background_cost"), names(data))
  draw_point_columns(data, draws, "cost", "12_costs.csv", cols)
}

draw_point_columns <- function(data, draws, parameter_group, source_file, cols) {
  if (length(cols) == 0 || nrow(data) == 0) {
    return(empty_psa_parameter_draws())
  }
  rows <- lapply(cols, function(col) {
    values <- suppressWarnings(as.numeric(data[[col]]))
    keep <- !is.na(values)
    if (!any(keep)) {
      return(empty_psa_parameter_draws())
    }
    expand_parameter_rows(
      row_ids = which(keep),
      draws = draws,
      parameter_group = parameter_group,
      source_file = source_file,
      parameter = col,
      mean_value = values[keep],
      lower_95 = NA_real_,
      upper_95 = NA_real_,
      draw_value = rep(values[keep], each = draws),
      distribution = "point"
    )
  })
  out <- do.call(rbind, rows)
  row.names(out) <- NULL
  out
}

draw_numeric_rows <- function(data,
                              draws,
                              parameter_group,
                              source_file,
                              parameter_col,
                              mean_col,
                              lower_col,
                              upper_col,
                              point_distribution) {
  mean_value <- suppressWarnings(as.numeric(data[[mean_col]]))
  lower_95 <- suppressWarnings(as.numeric(data[[lower_col]]))
  upper_95 <- suppressWarnings(as.numeric(data[[upper_col]]))
  keep <- !is.na(mean_value)
  if (!any(keep)) {
    return(empty_psa_parameter_draws())
  }

  row_ids <- which(keep)
  parameter <- if (is.null(parameter_col)) mean_col else as.character(data[[parameter_col]][keep])
  draw_values <- numeric(length(row_ids) * draws)
  distributions <- character(length(row_ids))
  offset <- 0L
  for (i in seq_along(row_ids)) {
    row <- row_ids[[i]]
    sampled <- sample_psa_value(mean_value[[row]], lower_95[[row]], upper_95[[row]], draws)
    draw_values[(offset + 1L):(offset + draws)] <- sampled$value
    distributions[[i]] <- sampled$distribution
    offset <- offset + draws
  }

  expand_parameter_rows(
    row_ids = row_ids,
    draws = draws,
    parameter_group = parameter_group,
    source_file = source_file,
    parameter = parameter,
    mean_value = mean_value[keep],
    lower_95 = lower_95[keep],
    upper_95 = upper_95[keep],
    draw_value = draw_values,
    distribution = distributions
  )
}

expand_parameter_rows <- function(row_ids,
                                  draws,
                                  parameter_group,
                                  source_file,
                                  parameter,
                                  mean_value,
                                  lower_95,
                                  upper_95,
                                  draw_value,
                                  distribution) {
  data.frame(
    draw = rep(seq_len(draws), times = length(row_ids)),
    parameter_group = parameter_group,
    source_file = source_file,
    row_id = rep(row_ids, each = draws),
    parameter = rep(parameter, each = draws),
    mean_value = rep(mean_value, each = draws),
    lower_95 = rep(lower_95, each = draws),
    upper_95 = rep(upper_95, each = draws),
    draw_value = draw_value,
    distribution = rep(distribution, each = draws),
    stringsAsFactors = FALSE
  )
}

sample_psa_value <- function(mean_value, lower_95, upper_95, draws) {
  if (is.na(lower_95) || is.na(upper_95) || lower_95 == upper_95) {
    return(list(value = rep(mean_value, draws), distribution = "point"))
  }
  if (lower_95 > upper_95) {
    stop("PSA uncertainty bounds must have `lower_95` less than or equal to `upper_95`.", call. = FALSE)
  }

  if (mean_value > 0 && lower_95 > 0 && upper_95 > 0) {
    sdlog <- (log(upper_95) - log(lower_95)) / (2 * stats::qnorm(0.975))
    value <- stats::rlnorm(draws, meanlog = log(mean_value), sdlog = sdlog)
    return(list(value = value, distribution = "lognormal_95ci"))
  }

  sd <- (upper_95 - lower_95) / (2 * stats::qnorm(0.975))
  value <- stats::rnorm(draws, mean = mean_value, sd = sd)
  value <- pmin(pmax(value, lower_95), upper_95)
  list(value = value, distribution = "truncated_normal_95ci")
}

apply_relative_risk_draw <- function(relative_risks, parameter_draws, draw) {
  rr <- relative_risks
  rows <- parameter_draws[
    parameter_draws$draw == draw &
      parameter_draws$parameter_group == "relative_risk" &
      parameter_draws$parameter == "rr",
    ,
    drop = FALSE
  ]
  if (nrow(rows) == 0) {
    return(rr)
  }
  rr$rr[rows$row_id] <- rows$draw_value
  rr
}

read_psa_raw_table <- function(x, template_name) {
  data <- read_if_path(x, template_name)
  schema <- pmslt_input_schemas()[[template_name]]
  if (is.null(schema)) {
    stop("Unknown PSA input schema `", template_name, "`.", call. = FALSE)
  }
  require_columns(data, schema$columns$column, schema$file)
  data
}

read_psa_disease_epi <- function(x) {
  if (is.character(x) && length(x) == 1) {
    x <- read_pmslt_disease_inputs(x)
  } else {
    validate_pmslt_disease_inputs(x)
  }
  x
}

validate_psa_draw_count <- function(draws) {
  value <- suppressWarnings(as.numeric(draws))
  if (length(value) != 1 || is.na(value) || value <= 0 ||
      abs(value - round(value)) > .Machine$double.eps^0.5) {
    stop("`draws` must be one positive whole number.", call. = FALSE)
  }
  as.integer(value)
}

validate_psa_interval_width <- function(interval_width) {
  value <- suppressWarnings(as.numeric(interval_width))
  if (length(value) != 1 || is.na(value) || value <= 0 || value >= 1) {
    stop("`interval_width` must be a number greater than 0 and less than 1.", call. = FALSE)
  }
  invisible(TRUE)
}

set_psa_seed <- function(seed) {
  old_seed <- if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
    get(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  } else {
    NULL
  }
  if (!is.null(seed)) {
    set.seed(seed)
  }
  old_seed
}

restore_psa_seed <- function(old_seed) {
  if (is.null(old_seed)) {
    if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
      rm(".Random.seed", envir = .GlobalEnv)
    }
  } else {
    assign(".Random.seed", old_seed, envir = .GlobalEnv)
  }
  invisible(TRUE)
}
