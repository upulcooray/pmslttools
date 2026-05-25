#' Prepare external DisMod-MR input files
#'
#' Converts raw PMSLT disease evidence into explicit CSV files for an external
#' DisMod-MR workflow. This function prepares file contracts only: it does not
#' run DisMod-MR and it does not create the canonical PMSLT-ready
#' `pmslt_disease_epi.csv`.
#'
#' The exporter reads `05_disease_epidemiology_raw.csv` and, when present,
#' `06_dismod_input_skeleton.csv`. Direct data-frame or CSV-path overrides can
#' be supplied with `disease_raw` and `dismod_skeleton`. When both sources
#' contain the same disease, sex, stratum, age group, and parameter, the
#' skeleton row is kept and the raw row is recorded in the omissions audit as
#' superseded.
#'
#' The function writes four files:
#' `dismod_mr_input_long.csv`, `dismod_mr_target_grid.csv`,
#' `dismod_mr_input_omissions.csv`, and `dismod_mr_input_summary.csv`.
#'
#' @param input_dir Directory containing raw PMSLT disease CSV files. Required
#'   unless direct overrides are supplied for `disease_raw` or
#'   `dismod_skeleton`.
#' @param output_dir Directory where DisMod-MR preparation files should be
#'   written.
#' @param spec Optional `pmslt_spec` object. When supplied, exact target ages
#'   are derived from `spec$ages`.
#' @param disease_raw Optional raw disease evidence as a data frame or a path to
#'   `05_disease_epidemiology_raw.csv`.
#' @param dismod_skeleton Optional long-format DisMod skeleton evidence as a
#'   data frame or a path to `06_dismod_input_skeleton.csv`.
#' @param overwrite Logical. Should existing output files be overwritten?
#'
#' @return A list with prepared `evidence`, `target_grid`, `omissions`,
#'   `summary`, and `files`. The object has class
#'   `dismod_mr_input_preparation`.
#' @export
#'
#' @examples
#' \donttest{
#' input_dir <- file.path(tempdir(), "pmslt_raw_inputs")
#' output_dir <- file.path(tempdir(), "dismod_mr_inputs")
#' dir.create(input_dir, showWarnings = FALSE)
#' disease_raw <- data.frame(
#'   disease = "ihd",
#'   sex = "female",
#'   stratum = "total",
#'   age_start = 45,
#'   age_end = 49,
#'   age_label = "45-49",
#'   incidence_rate = 0.01,
#'   prevalence = 0.05,
#'   remission_rate = 0.02,
#'   excess_mortality_rate = 0.10,
#'   case_fatality_rate = 0.03
#' )
#' utils::write.csv(
#'   disease_raw,
#'   file.path(input_dir, "05_disease_epidemiology_raw.csv"),
#'   row.names = FALSE
#' )
#' prep <- prepare_dismod_mr_inputs(input_dir, output_dir, overwrite = TRUE)
#' prep$files
#' }
prepare_dismod_mr_inputs <- function(input_dir = NULL,
                                     output_dir,
                                     spec = NULL,
                                     disease_raw = NULL,
                                     dismod_skeleton = NULL,
                                     overwrite = FALSE) {
  if (missing(output_dir) || !is_single_nonempty_string(output_dir)) {
    stop("`output_dir` must be a single folder path.", call. = FALSE)
  }
  if (!is.null(input_dir) && !is_single_nonempty_string(input_dir)) {
    stop("`input_dir` must be a single folder path, or NULL when direct overrides are supplied.", call. = FALSE)
  }
  if (is.null(input_dir) && is.null(disease_raw) && is.null(dismod_skeleton)) {
    stop(
      "Could not prepare DisMod-MR inputs because `input_dir` was not supplied ",
      "and no direct disease evidence was provided.",
      call. = FALSE
    )
  }
  if (!is.null(input_dir) && !dir.exists(input_dir)) {
    stop("Could not prepare DisMod-MR inputs because `input_dir` does not exist: ", input_dir, call. = FALSE)
  }
  if (!is.null(spec)) {
    validate_spec(spec)
  }

  files <- dismod_mr_input_output_files(output_dir)
  existing <- unlist(files, use.names = FALSE)[file.exists(unlist(files, use.names = FALSE))]
  if (length(existing) > 0 && !isTRUE(overwrite)) {
    stop(
      "Cannot prepare DisMod-MR inputs because output file(s) already exist: ",
      paste(existing, collapse = ", "),
      ". Set `overwrite = TRUE` or choose a different `output_dir`.",
      call. = FALSE
    )
  }

  skeleton_file_exists <- !is.null(input_dir) && file.exists(file.path(input_dir, "06_dismod_input_skeleton.csv"))
  raw_source <- dismod_mr_read_input_source(
    override = disease_raw,
    input_dir = input_dir,
    filename = "05_disease_epidemiology_raw.csv",
    required = is.null(dismod_skeleton) && !skeleton_file_exists
  )
  skeleton_source <- dismod_mr_read_input_source(
    override = dismod_skeleton,
    input_dir = input_dir,
    filename = "06_dismod_input_skeleton.csv",
    required = FALSE
  )

  raw_prepared <- dismod_mr_prepare_raw_source(raw_source)
  skeleton_prepared <- dismod_mr_prepare_skeleton_source(skeleton_source)

  precedence <- dismod_mr_apply_input_precedence(
    raw_prepared$evidence,
    skeleton_prepared$evidence
  )
  evidence <- precedence$evidence
  omissions <- dismod_mr_bind_rows(
    list(raw_prepared$omissions, skeleton_prepared$omissions, precedence$omissions),
    dismod_mr_input_omission_columns()
  )
  source_rows <- dismod_mr_bind_rows(
    list(raw_prepared$source_rows, skeleton_prepared$source_rows),
    dismod_mr_source_row_columns()
  )

  if (nrow(evidence) == 0) {
    stop(
      "Could not prepare DisMod-MR inputs because no usable disease evidence was found. ",
      "Check 05_disease_epidemiology_raw.csv or 06_dismod_input_skeleton.csv.",
      call. = FALSE
    )
  }

  target_grid <- dismod_mr_build_target_grid(evidence, source_rows, spec)
  summary <- dismod_mr_build_input_summary(evidence, target_grid, omissions)

  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }
  utils::write.csv(evidence, files$evidence, row.names = FALSE, na = "")
  utils::write.csv(target_grid, files$target_grid, row.names = FALSE, na = "")
  utils::write.csv(omissions, files$omissions, row.names = FALSE, na = "")
  utils::write.csv(summary, files$summary, row.names = FALSE, na = "")

  structure(
    list(
      evidence = evidence,
      input_long = evidence,
      target_grid = target_grid,
      omissions = omissions,
      summary = summary,
      files = files,
      output_dir = output_dir
    ),
    class = "dismod_mr_input_preparation"
  )
}

#' @export
print.dismod_mr_input_preparation <- function(x, ...) {
  cat("DisMod-MR input preparation\n")
  cat("Output directory: ", x$output_dir, "\n", sep = "")
  cat("Files:\n")
  for (name in names(x$files)) {
    cat("- ", name, ": ", x$files[[name]], "\n", sep = "")
  }
  cat("Evidence rows: ", nrow(x$evidence), "\n", sep = "")
  cat("Target grid rows: ", nrow(x$target_grid), "\n", sep = "")
  cat("Omitted rows: ", nrow(x$omissions), "\n", sep = "")
  cat("Next step: Run DisMod-MR outside R, then read the modelled outputs with read_dismod_mr_outputs().\n")
  invisible(x)
}

dismod_mr_parameters <- function() {
  c("incidence", "prevalence", "remission", "excess_mortality", "case_fatality")
}

dismod_mr_evidence_parameters <- function() {
  c(dismod_mr_parameters(), "disability_weight")
}

dismod_mr_raw_parameter_map <- function() {
  c(
    incidence = "incidence",
    incidence_rate = "incidence",
    prevalence = "prevalence",
    prevalence_initial = "prevalence",
    remission = "remission",
    remission_rate = "remission",
    excess_mortality = "excess_mortality",
    excess_mortality_rate = "excess_mortality",
    case_fatality = "case_fatality",
    case_fatality_rate = "case_fatality",
    disability_weight = "disability_weight"
  )
}

dismod_mr_input_output_files <- function(output_dir) {
  list(
    evidence = file.path(output_dir, "dismod_mr_input_long.csv"),
    target_grid = file.path(output_dir, "dismod_mr_target_grid.csv"),
    omissions = file.path(output_dir, "dismod_mr_input_omissions.csv"),
    summary = file.path(output_dir, "dismod_mr_input_summary.csv")
  )
}

is_single_nonempty_string <- function(x) {
  is.character(x) && length(x) == 1 && !is.na(x) && nzchar(x)
}

dismod_mr_read_input_source <- function(override, input_dir, filename, required) {
  if (!is.null(override)) {
    if (is.data.frame(override)) {
      return(list(data = as.data.frame(override, stringsAsFactors = FALSE), source_file = filename))
    }
    if (is_single_nonempty_string(override)) {
      if (!file.exists(override)) {
        stop("Could not prepare DisMod-MR inputs because input file does not exist: ", override, call. = FALSE)
      }
      return(list(
        data = utils::read.csv(override, stringsAsFactors = FALSE, na.strings = c("", "NA")),
        source_file = basename(override)
      ))
    }
    stop("Direct input overrides must be data frames or single CSV file paths.", call. = FALSE)
  }

  if (is.null(input_dir)) {
    if (isTRUE(required)) {
      stop(
        "Could not prepare DisMod-MR inputs because no usable disease evidence was provided. ",
        "Supply `input_dir`, `disease_raw`, or `dismod_skeleton`.",
        call. = FALSE
      )
    }
    return(NULL)
  }

  path <- file.path(input_dir, filename)
  if (!file.exists(path)) {
    if (isTRUE(required)) {
      stop("Could not prepare DisMod-MR inputs because `", filename, "` was not found in input_dir.", call. = FALSE)
    }
    return(NULL)
  }
  list(
    data = utils::read.csv(path, stringsAsFactors = FALSE, na.strings = c("", "NA")),
    source_file = filename
  )
}

dismod_mr_prepare_raw_source <- function(source) {
  if (is.null(source)) {
    return(dismod_mr_empty_prepared_source())
  }

  raw <- dismod_mr_normalize_age_columns(source$data)
  require_columns(raw, c("disease", "sex", "stratum", "age_start", "age_end"), source$source_file)
  raw$age_label <- dismod_mr_age_label(raw)

  source_rows <- dismod_mr_source_rows(raw, source$source_file)
  parameter_map <- dismod_mr_raw_parameter_map()
  value_columns <- intersect(names(parameter_map), names(raw))
  evidence <- list()
  omissions <- list()

  for (row in seq_len(nrow(raw))) {
    for (column in value_columns) {
      parameter <- unname(parameter_map[[column]])
      value_check <- dismod_mr_parse_observed_value(raw[[column]][[row]])
      entry <- dismod_mr_evidence_row(
        raw[row, , drop = FALSE],
        parameter = parameter,
        mean_value = value_check$value,
        source_file = source$source_file,
        source_row = row,
        input_source = "05_disease_epidemiology_raw.csv"
      )
      reason <- dismod_mr_invalid_evidence_reason(entry, value_check)
      if (is.na(reason)) {
        evidence[[length(evidence) + 1L]] <- entry
      } else {
        omissions[[length(omissions) + 1L]] <- dismod_mr_omission_row(entry, reason)
      }
    }
  }

  list(
    evidence = dismod_mr_sort_evidence(dismod_mr_bind_rows(evidence, dismod_mr_input_evidence_columns())),
    omissions = dismod_mr_sort_omissions(dismod_mr_bind_rows(omissions, dismod_mr_input_omission_columns())),
    source_rows = source_rows
  )
}

dismod_mr_prepare_skeleton_source <- function(source) {
  if (is.null(source)) {
    return(dismod_mr_empty_prepared_source())
  }

  skeleton <- dismod_mr_normalize_age_columns(source$data)
  require_columns(
    skeleton,
    c("disease", "sex", "stratum", "age_start", "age_end", "parameter", "mean_value"),
    source$source_file
  )
  skeleton$age_label <- dismod_mr_age_label(skeleton)

  source_rows <- dismod_mr_source_rows(skeleton, source$source_file)
  evidence <- list()
  omissions <- list()

  for (row in seq_len(nrow(skeleton))) {
    parameter <- normalize_dismod_parameter(skeleton$parameter[[row]])
    value_check <- dismod_mr_parse_observed_value(skeleton$mean_value[[row]])
    entry <- dismod_mr_evidence_row(
      skeleton[row, , drop = FALSE],
      parameter = parameter,
      mean_value = value_check$value,
      source_file = source$source_file,
      source_row = row,
      input_source = "06_dismod_input_skeleton.csv"
    )
    reason <- dismod_mr_invalid_evidence_reason(entry, value_check)
    if (!parameter %in% dismod_mr_evidence_parameters()) {
      reason <- "unsupported_parameter"
    }
    if (is.na(reason)) {
      evidence[[length(evidence) + 1L]] <- entry
    } else {
      omissions[[length(omissions) + 1L]] <- dismod_mr_omission_row(entry, reason)
    }
  }

  list(
    evidence = dismod_mr_sort_evidence(dismod_mr_bind_rows(evidence, dismod_mr_input_evidence_columns())),
    omissions = dismod_mr_sort_omissions(dismod_mr_bind_rows(omissions, dismod_mr_input_omission_columns())),
    source_rows = source_rows
  )
}

dismod_mr_empty_prepared_source <- function() {
  list(
    evidence = dismod_mr_bind_rows(list(), dismod_mr_input_evidence_columns()),
    omissions = dismod_mr_bind_rows(list(), dismod_mr_input_omission_columns()),
    source_rows = dismod_mr_bind_rows(list(), dismod_mr_source_row_columns())
  )
}

dismod_mr_parse_observed_value <- function(value) {
  text <- trimws(as.character(value))
  if (length(value) == 0 || is.na(value) || !nzchar(text)) {
    return(list(value = NA_real_, problem = "missing_value"))
  }
  parsed <- suppressWarnings(as.numeric(value))
  if (is.na(parsed)) {
    return(list(value = NA_real_, problem = "non_numeric_value"))
  }
  list(value = parsed, problem = NA_character_)
}

dismod_mr_invalid_evidence_reason <- function(row, value_check) {
  identifiers <- c(row$disease, row$sex, row$stratum, row$age_start, row$age_end, row$age_label, row$parameter)
  if (any(is.na(identifiers)) || any(!nzchar(as.character(identifiers)))) {
    return("missing_required_identifier")
  }
  if (is.na(row$age_start) || is.na(row$age_end) || row$age_end < row$age_start) {
    return("invalid_age_group")
  }
  if (!row$parameter %in% dismod_mr_evidence_parameters()) {
    return("unsupported_parameter")
  }
  if (!is.na(value_check$problem)) {
    return(value_check$problem)
  }
  if (row$mean_value < 0) {
    return("negative_value")
  }
  NA_character_
}

dismod_mr_evidence_row <- function(data, parameter, mean_value, source_file, source_row, input_source) {
  out <- data.frame(
    disease = as.character(data$disease),
    sex = as.character(data$sex),
    stratum = as.character(data$stratum),
    age_start = suppressWarnings(as.numeric(data$age_start)),
    age_end = suppressWarnings(as.numeric(data$age_end)),
    age_label = dismod_mr_age_label(data),
    parameter = as.character(parameter),
    mean_value = mean_value,
    source_file = source_file,
    lower_95 = dismod_mr_optional_numeric(data, "lower_95"),
    upper_95 = dismod_mr_optional_numeric(data, "upper_95"),
    time_step = dismod_mr_optional_numeric(data, "time_step"),
    input_source = input_source,
    source_row = as.integer(source_row),
    stringsAsFactors = FALSE
  )
  out[, dismod_mr_input_evidence_columns(), drop = FALSE]
}

dismod_mr_omission_row <- function(row, reason) {
  data.frame(
    disease = row$disease,
    sex = row$sex,
    stratum = row$stratum,
    age_start = row$age_start,
    age_end = row$age_end,
    age_label = row$age_label,
    parameter = row$parameter,
    reason = reason,
    source_file = row$source_file,
    source_row = row$source_row,
    stringsAsFactors = FALSE
  )
}

dismod_mr_apply_input_precedence <- function(raw_evidence, skeleton_evidence) {
  if (nrow(skeleton_evidence) == 0) {
    return(list(
      evidence = raw_evidence,
      omissions = dismod_mr_bind_rows(list(), dismod_mr_input_omission_columns())
    ))
  }

  skeleton_keys <- dismod_mr_evidence_key(skeleton_evidence)
  superseded <- raw_evidence[dismod_mr_evidence_key(raw_evidence) %in% skeleton_keys, , drop = FALSE]
  kept_raw <- raw_evidence[!dismod_mr_evidence_key(raw_evidence) %in% skeleton_keys, , drop = FALSE]
  superseded_omissions <- lapply(seq_len(nrow(superseded)), function(row) {
    dismod_mr_omission_row(superseded[row, , drop = FALSE], "superseded_by_dismod_input_skeleton")
  })

  list(
    evidence = dismod_mr_sort_evidence(
      dismod_mr_bind_rows(list(kept_raw, skeleton_evidence), dismod_mr_input_evidence_columns())
    ),
    omissions = dismod_mr_sort_omissions(
      dismod_mr_bind_rows(superseded_omissions, dismod_mr_input_omission_columns())
    )
  )
}

dismod_mr_build_target_grid <- function(evidence, source_rows, spec) {
  groups <- unique(source_rows[c("disease", "sex", "stratum")])
  ages <- dismod_mr_target_ages(source_rows, spec)
  rows <- list()
  for (group_row in seq_len(nrow(groups))) {
    group <- groups[group_row, , drop = FALSE]
    for (parameter in dismod_mr_parameters()) {
      coverage <- evidence[
        evidence$disease == group$disease &
          evidence$sex == group$sex &
          evidence$stratum == group$stratum &
          evidence$parameter == parameter,
        c("age_start", "age_end"),
        drop = FALSE
      ]
      for (age in ages) {
        rows[[length(rows) + 1L]] <- data.frame(
          disease = group$disease,
          sex = group$sex,
          stratum = group$stratum,
          age = as.integer(age),
          parameter = parameter,
          requires_extrapolation = dismod_mr_requires_extrapolation(age, coverage),
          stringsAsFactors = FALSE
        )
      }
    }
  }
  out <- unique(dismod_mr_bind_rows(rows, dismod_mr_target_grid_columns()))
  out[order(out$disease, out$sex, out$stratum, out$parameter, out$age), , drop = FALSE]
}

dismod_mr_target_ages <- function(source_rows, spec) {
  if (!is.null(spec)) {
    age_rows <- dismod_mr_normalize_age_columns(spec$ages)
  } else {
    age_rows <- source_rows[c("age_start", "age_end")]
  }
  age_rows$age_start <- suppressWarnings(as.numeric(age_rows$age_start))
  age_rows$age_end <- suppressWarnings(as.numeric(age_rows$age_end))
  age_rows <- age_rows[!is.na(age_rows$age_start) & !is.na(age_rows$age_end), , drop = FALSE]
  if (nrow(age_rows) == 0) {
    stop("Could not prepare DisMod-MR target grid because no valid age coverage was found.", call. = FALSE)
  }

  ages <- unlist(lapply(seq_len(nrow(age_rows)), function(row) {
    start <- as.integer(round(age_rows$age_start[[row]]))
    end <- age_rows$age_end[[row]]
    if (is.infinite(end)) {
      return(start)
    }
    seq.int(start, as.integer(round(end)))
  }))
  sort(unique(as.integer(ages)))
}

dismod_mr_requires_extrapolation <- function(age, coverage) {
  if (nrow(coverage) == 0) {
    return(TRUE)
  }
  !any(age >= coverage$age_start & age <= coverage$age_end)
}

dismod_mr_build_input_summary <- function(evidence, target_grid, omissions) {
  groups <- unique(target_grid[c("disease", "sex", "stratum", "parameter")])
  rows <- lapply(seq_len(nrow(groups)), function(row) {
    group <- groups[row, , drop = FALSE]
    evidence_rows <- evidence[
      evidence$disease == group$disease &
        evidence$sex == group$sex &
        evidence$stratum == group$stratum &
        evidence$parameter == group$parameter,
      ,
      drop = FALSE
    ]
    omitted_rows <- omissions[
      omissions$disease == group$disease &
        omissions$sex == group$sex &
        omissions$stratum == group$stratum &
        omissions$parameter == group$parameter,
      ,
      drop = FALSE
    ]
    target_rows <- target_grid[
      target_grid$disease == group$disease &
        target_grid$sex == group$sex &
        target_grid$stratum == group$stratum &
        target_grid$parameter == group$parameter,
      ,
      drop = FALSE
    ]
    data.frame(
      disease = group$disease,
      sex = group$sex,
      stratum = group$stratum,
      parameter = group$parameter,
      n_evidence_rows = nrow(evidence_rows),
      min_age_start = if (nrow(evidence_rows) == 0) NA_real_ else min(evidence_rows$age_start, na.rm = TRUE),
      max_age_end = if (nrow(evidence_rows) == 0) NA_real_ else max(evidence_rows$age_end, na.rm = TRUE),
      n_omitted_rows = nrow(omitted_rows),
      n_target_ages = length(unique(target_rows$age)),
      n_extrapolation_targets = sum(target_rows$requires_extrapolation),
      stringsAsFactors = FALSE
    )
  })
  dismod_mr_bind_rows(rows, dismod_mr_summary_columns())
}

dismod_mr_source_rows <- function(data, source_file) {
  out <- data.frame(
    disease = as.character(data$disease),
    sex = as.character(data$sex),
    stratum = as.character(data$stratum),
    age_start = suppressWarnings(as.numeric(data$age_start)),
    age_end = suppressWarnings(as.numeric(data$age_end)),
    age_label = dismod_mr_age_label(data),
    source_file = source_file,
    stringsAsFactors = FALSE
  )
  out[!is.na(out$age_start) & !is.na(out$age_end) & out$age_end >= out$age_start, , drop = FALSE]
}

dismod_mr_normalize_age_columns <- function(data) {
  if (!"age_start" %in% names(data) && "age" %in% names(data)) {
    data$age_start <- data$age
  }
  if (!"age_end" %in% names(data) && "age" %in% names(data)) {
    data$age_end <- data$age
  }
  data
}

dismod_mr_age_label <- function(data) {
  if ("age_label" %in% names(data)) {
    label <- as.character(data$age_label)
    missing_label <- is.na(label) | !nzchar(trimws(label))
  } else {
    label <- rep(NA_character_, nrow(data))
    missing_label <- rep(TRUE, nrow(data))
  }
  starts <- suppressWarnings(as.numeric(data$age_start))
  ends <- suppressWarnings(as.numeric(data$age_end))
  label[missing_label & !is.na(starts) & !is.na(ends)] <- ifelse(
    is.infinite(ends[missing_label & !is.na(starts) & !is.na(ends)]),
    paste0(starts[missing_label & !is.na(starts) & !is.na(ends)], "+"),
    paste0(starts[missing_label & !is.na(starts) & !is.na(ends)], "-", ends[missing_label & !is.na(starts) & !is.na(ends)])
  )
  label
}

dismod_mr_optional_numeric <- function(data, column) {
  if (!column %in% names(data)) {
    return(NA_real_)
  }
  suppressWarnings(as.numeric(data[[column]]))
}

dismod_mr_evidence_key <- function(data) {
  paste(data$disease, data$sex, data$stratum, data$age_start, data$age_end, data$age_label, data$parameter, sep = "\r")
}

dismod_mr_input_evidence_columns <- function() {
  c(
    "disease", "sex", "stratum", "age_start", "age_end", "age_label",
    "parameter", "mean_value", "source_file", "lower_95", "upper_95",
    "time_step", "input_source", "source_row"
  )
}

dismod_mr_input_omission_columns <- function() {
  c("disease", "sex", "stratum", "age_start", "age_end", "age_label", "parameter", "reason", "source_file", "source_row")
}

dismod_mr_target_grid_columns <- function() {
  c("disease", "sex", "stratum", "age", "parameter", "requires_extrapolation")
}

dismod_mr_summary_columns <- function() {
  c(
    "disease", "sex", "stratum", "parameter", "n_evidence_rows",
    "min_age_start", "max_age_end", "n_omitted_rows", "n_target_ages",
    "n_extrapolation_targets"
  )
}

dismod_mr_source_row_columns <- function() {
  c("disease", "sex", "stratum", "age_start", "age_end", "age_label", "source_file")
}

dismod_mr_bind_rows <- function(rows, columns = NULL) {
  rows <- rows[!vapply(rows, is.null, logical(1))]
  if (length(rows) == 0) {
    return(as.data.frame(stats::setNames(rep(list(logical()), length(columns)), columns), stringsAsFactors = FALSE))
  }
  out <- do.call(rbind, rows)
  row.names(out) <- NULL
  if (!is.null(columns)) {
    out <- out[, columns, drop = FALSE]
  }
  out
}

dismod_mr_sort_evidence <- function(data) {
  if (nrow(data) == 0) {
    return(data)
  }
  data[order(data$disease, data$sex, data$stratum, data$parameter, data$age_start, data$age_end, data$source_file, data$source_row), , drop = FALSE]
}

dismod_mr_sort_omissions <- function(data) {
  if (nrow(data) == 0) {
    return(data)
  }
  data[order(data$disease, data$sex, data$stratum, data$parameter, data$age_start, data$age_end, data$source_file, data$source_row, data$reason), , drop = FALSE]
}
