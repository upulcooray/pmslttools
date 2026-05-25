#' Prepare external DisMod-MR input files
#'
#' Converts package raw disease evidence into clean CSV files for an external
#' DisMod-MR workflow. This function does not run DisMod-MR and does not create
#' `pmslt_disease_epi.csv`; it only prepares package-side input and audit files.
#'
#' @param input_dir Directory containing `05_disease_epidemiology_raw.csv` and
#'   optionally `06_dismod_input_skeleton.csv`.
#' @param output_dir Directory where DisMod-MR preparation files should be
#'   written. If `NULL`, files are written to `dismod_mr_inputs` under
#'   `input_dir`.
#' @param spec Optional `pmslt_spec` object. It is validated when supplied, but
#'   this adapter keeps the target grid anchored to the source CSV rows.
#' @param overwrite Logical. Should existing output files be overwritten?
#'
#' @return An object of class `dismod_mr_input_preparation` containing the
#'   prepared input data, target grid, omissions audit, summary, file paths, and
#'   output directory.
#' @export
#'
#' @examples
#' \dontrun{
#' prep <- prepare_dismod_mr_inputs("path/to/raw_inputs")
#' prep
#' }
prepare_dismod_mr_inputs <- function(input_dir,
                                      output_dir = NULL,
                                      spec = NULL,
                                      overwrite = FALSE) {
  if (!is.character(input_dir) || length(input_dir) != 1 || is.na(input_dir)) {
    stop("`input_dir` must be a single folder path.", call. = FALSE)
  }
  if (!dir.exists(input_dir)) {
    stop("Cannot prepare DisMod-MR inputs because `input_dir` does not exist: ", input_dir, call. = FALSE)
  }
  if (!is.null(spec)) {
    validate_spec(spec)
  }
  if (is.null(output_dir)) {
    output_dir <- file.path(input_dir, "dismod_mr_inputs")
  }
  if (!is.character(output_dir) || length(output_dir) != 1 || is.na(output_dir)) {
    stop("`output_dir` must be a single folder path.", call. = FALSE)
  }

  raw_file <- "05_disease_epidemiology_raw.csv"
  skeleton_file <- "06_dismod_input_skeleton.csv"
  raw_path <- file.path(input_dir, raw_file)
  skeleton_path <- file.path(input_dir, skeleton_file)
  if (!file.exists(raw_path)) {
    stop(
      "Cannot prepare DisMod-MR inputs because `05_disease_epidemiology_raw.csv` ",
      "was not found in input_dir.",
      call. = FALSE
    )
  }

  files <- dismod_mr_output_files(output_dir)
  existing <- unlist(files, use.names = FALSE)[file.exists(unlist(files, use.names = FALSE))]
  if (length(existing) > 0 && !isTRUE(overwrite)) {
    stop(
      "Cannot prepare DisMod-MR inputs because output file(s) already exist: ",
      paste(existing, collapse = ", "),
      ". Set `overwrite = TRUE` or choose a different `output_dir`.",
      call. = FALSE
    )
  }
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  raw <- read_optional_csv(raw_path)
  skeleton <- read_optional_csv(skeleton_path)
  raw_prepared <- dismod_mr_raw_to_long(raw, raw_file)
  skeleton_prepared <- dismod_mr_skeleton_to_long(skeleton, skeleton_file)

  active <- dismod_mr_apply_skeleton_precedence(
    raw_prepared$input,
    skeleton_prepared$input
  )
  input_long <- active$input
  omissions <- dismod_mr_bind_rows(list(
    raw_prepared$omissions,
    skeleton_prepared$omissions,
    active$omissions
  ))
  target_grid <- dismod_mr_target_grid(raw, skeleton)
  summary <- dismod_mr_summary(input_long, target_grid, omissions, !is.null(skeleton), output_dir)

  utils::write.csv(input_long, files$input_long, row.names = FALSE, na = "")
  utils::write.csv(target_grid, files$target_grid, row.names = FALSE, na = "")
  utils::write.csv(omissions, files$omissions, row.names = FALSE, na = "")
  utils::write.csv(summary, files$summary, row.names = FALSE, na = "")

  structure(
    list(
      input_long = input_long,
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
  cat("Input rows: ", nrow(x$input_long), "\n", sep = "")
  cat("Target grid rows: ", nrow(x$target_grid), "\n", sep = "")
  cat("Omitted rows: ", nrow(x$omissions), "\n", sep = "")
  cat("Next step: Run external DisMod-MR using these files, then use the future DisMod-MR output reader to import modelled results.\n")
  invisible(x)
}

dismod_mr_parameters <- function() {
  c("incidence", "prevalence", "remission", "excess_mortality", "case_fatality")
}

dismod_mr_raw_parameter_map <- function() {
  c(
    incidence = "incidence",
    incidence_raw = "incidence",
    incidence_rate = "incidence",
    prevalence = "prevalence",
    prevalence_raw = "prevalence",
    prevalence_rate = "prevalence",
    remission = "remission",
    remission_rate = "remission",
    excess_mortality = "excess_mortality",
    excess_mortality_rate = "excess_mortality",
    case_fatality = "case_fatality",
    case_fatality_rate = "case_fatality"
  )
}

dismod_mr_output_files <- function(output_dir) {
  list(
    input_long = file.path(output_dir, "dismod_mr_input_long.csv"),
    target_grid = file.path(output_dir, "dismod_mr_target_grid.csv"),
    omissions = file.path(output_dir, "dismod_mr_input_omissions.csv"),
    summary = file.path(output_dir, "dismod_mr_input_summary.csv")
  )
}

dismod_mr_raw_to_long <- function(raw, source_file) {
  required <- c("disease", "age_start", "age_end", "sex", "stratum")
  require_columns(raw, required, source_file)

  param_map <- dismod_mr_raw_parameter_map()
  value_columns <- intersect(names(param_map), names(raw))
  rows <- list()
  omissions <- list()
  unknown <- setdiff(names(raw), c(required, "age", "age_label", "source", "notes", names(param_map)))

  for (i in seq_len(nrow(raw))) {
    for (column in value_columns) {
      parameter <- unname(param_map[[column]])
      value <- suppressWarnings(as.numeric(raw[[column]][[i]]))
      entry <- dismod_mr_long_row(raw[i, , drop = FALSE], parameter, value, source_file, i, FALSE)
      reason <- dismod_mr_omission_reason(entry)
      if (is.na(reason)) {
        rows[[length(rows) + 1L]] <- entry
      } else {
        omissions[[length(omissions) + 1L]] <- dismod_mr_omission_row(entry, reason)
      }
    }
    for (column in unknown) {
      if (!is.na(raw[[column]][[i]]) && nzchar(as.character(raw[[column]][[i]]))) {
        entry <- dismod_mr_long_row(raw[i, , drop = FALSE], column, NA_real_, source_file, i, FALSE)
        omissions[[length(omissions) + 1L]] <- dismod_mr_omission_row(entry, "unsupported parameter")
      }
    }
  }

  list(
    input = dismod_mr_sort_input(dismod_mr_bind_rows(rows, dismod_mr_input_columns())),
    omissions = dismod_mr_sort_omissions(dismod_mr_bind_rows(omissions, dismod_mr_omission_columns()))
  )
}

dismod_mr_skeleton_to_long <- function(skeleton, source_file) {
  if (is.null(skeleton)) {
    return(list(
      input = dismod_mr_bind_rows(list(), dismod_mr_input_columns()),
      omissions = dismod_mr_bind_rows(list(), dismod_mr_omission_columns())
    ))
  }
  skeleton <- dismod_mr_normalize_age_columns(skeleton)
  required <- c("disease", "age_start", "age_end", "sex", "stratum", "parameter", "mean_value")
  require_columns(skeleton, required, source_file)

  rows <- list()
  omissions <- list()
  for (i in seq_len(nrow(skeleton))) {
    parameter <- normalize_dismod_parameter(skeleton$parameter[[i]])
    value <- suppressWarnings(as.numeric(skeleton$mean_value[[i]]))
    entry <- dismod_mr_long_row(skeleton[i, , drop = FALSE], parameter, value, source_file, i, TRUE)
    reason <- dismod_mr_omission_reason(entry)
    if (!parameter %in% dismod_mr_parameters()) {
      reason <- "unsupported parameter"
    }
    if (is.na(reason)) {
      rows[[length(rows) + 1L]] <- entry
    } else {
      omissions[[length(omissions) + 1L]] <- dismod_mr_omission_row(entry, reason)
    }
  }

  list(
    input = dismod_mr_sort_input(dismod_mr_bind_rows(rows, dismod_mr_input_columns())),
    omissions = dismod_mr_sort_omissions(dismod_mr_bind_rows(omissions, dismod_mr_omission_columns()))
  )
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

dismod_mr_long_row <- function(data, parameter, value, source_file, source_row, is_skeleton_value) {
  data.frame(
    disease = as.character(data$disease),
    parameter = as.character(parameter),
    age_start = suppressWarnings(as.numeric(data$age_start)),
    age_end = suppressWarnings(as.numeric(data$age_end)),
    sex = as.character(data$sex),
    stratum = as.character(data$stratum),
    mean_value = value,
    source_file = source_file,
    source_row = as.integer(source_row),
    is_skeleton_value = isTRUE(is_skeleton_value),
    stringsAsFactors = FALSE
  )
}

dismod_mr_omission_reason <- function(row) {
  identifiers <- c(row$disease, row$age_start, row$age_end, row$sex, row$stratum)
  if (any(is.na(identifiers)) || any(!nzchar(as.character(identifiers)))) {
    return("missing required identifier")
  }
  if (!row$parameter %in% dismod_mr_parameters()) {
    return("unsupported parameter")
  }
  if (is.na(row$mean_value)) {
    return("missing value")
  }
  if (row$mean_value < 0) {
    return("negative value")
  }
  NA_character_
}

dismod_mr_omission_row <- function(row, reason) {
  data.frame(
    source_file = row$source_file,
    source_row = row$source_row,
    disease = row$disease,
    parameter = row$parameter,
    age_start = row$age_start,
    age_end = row$age_end,
    sex = row$sex,
    stratum = row$stratum,
    reason = reason,
    stringsAsFactors = FALSE
  )
}

dismod_mr_apply_skeleton_precedence <- function(raw_input, skeleton_input) {
  if (nrow(skeleton_input) == 0) {
    return(list(input = raw_input, omissions = dismod_mr_bind_rows(list(), dismod_mr_omission_columns())))
  }
  skeleton_keys <- dismod_mr_key(skeleton_input)
  overridden <- raw_input[dismod_mr_key(raw_input) %in% skeleton_keys, , drop = FALSE]
  kept_raw <- raw_input[!dismod_mr_key(raw_input) %in% skeleton_keys, , drop = FALSE]
  omissions <- if (nrow(overridden) > 0) {
    dismod_mr_bind_rows(
      lapply(seq_len(nrow(overridden)), function(i) {
        dismod_mr_omission_row(overridden[i, , drop = FALSE], "skeleton value overrides raw value")
      }),
      dismod_mr_omission_columns()
    )
  } else {
    dismod_mr_bind_rows(list(), dismod_mr_omission_columns())
  }
  list(
    input = dismod_mr_sort_input(dismod_mr_bind_rows(list(kept_raw, skeleton_input), dismod_mr_input_columns())),
    omissions = dismod_mr_sort_omissions(omissions)
  )
}

dismod_mr_key <- function(data) {
  paste(data$disease, data$parameter, data$age_start, data$age_end, data$sex, data$stratum, sep = "\r")
}

dismod_mr_target_grid <- function(raw, skeleton) {
  source <- if (!is.null(skeleton)) dismod_mr_normalize_age_columns(skeleton) else raw
  required <- c("disease", "age_start", "age_end", "sex", "stratum")
  require_columns(source, required, if (!is.null(skeleton)) "06_dismod_input_skeleton.csv" else "05_disease_epidemiology_raw.csv")
  groups <- unique(source[required])
  rows <- lapply(seq_len(nrow(groups)), function(i) {
    row <- groups[i, , drop = FALSE]
    raw_age_end <- suppressWarnings(as.numeric(row$age_end))
    age_start <- suppressWarnings(as.integer(as.numeric(row$age_start)))
    age_end <- suppressWarnings(as.integer(raw_age_end))
    if (is.na(age_start) || is.na(age_end)) {
      if (is.infinite(raw_age_end) && !is.na(age_start)) {
        age_end <- age_start
      } else {
        return(NULL)
      }
    }
    ages <- seq.int(age_start, age_end)
    expand.grid(
      disease = row$disease,
      age = ages,
      sex = row$sex,
      stratum = row$stratum,
      parameter = dismod_mr_parameters(),
      stringsAsFactors = FALSE
    )
  })
  out <- unique(dismod_mr_bind_rows(rows, c("disease", "age", "sex", "stratum", "parameter")))
  out[order(out$disease, out$sex, out$stratum, out$parameter, out$age), , drop = FALSE]
}

dismod_mr_summary <- function(input_long, target_grid, omissions, skeleton_present, output_dir) {
  values <- c(
    length(unique(input_long$disease)),
    length(unique(input_long$sex)),
    length(unique(input_long$stratum)),
    nrow(input_long),
    nrow(target_grid),
    nrow(omissions),
    as.character(isTRUE(skeleton_present)),
    output_dir
  )
  data.frame(
    metric = c(
      "number of diseases",
      "number of sexes",
      "number of strata",
      "number of input rows written",
      "number of target grid rows written",
      "number of omitted rows",
      "whether skeleton file was present",
      "output directory path"
    ),
    value = as.character(values),
    stringsAsFactors = FALSE
  )
}

dismod_mr_input_columns <- function() {
  c("disease", "parameter", "age_start", "age_end", "sex", "stratum", "mean_value", "source_file", "source_row", "is_skeleton_value")
}

dismod_mr_omission_columns <- function() {
  c("source_file", "source_row", "disease", "parameter", "age_start", "age_end", "sex", "stratum", "reason")
}

dismod_mr_bind_rows <- function(rows, columns = NULL) {
  rows <- rows[!vapply(rows, is.null, logical(1))]
  if (length(rows) == 0) {
    out <- as.data.frame(stats::setNames(rep(list(logical()), length(columns)), columns), stringsAsFactors = FALSE)
    return(out)
  }
  out <- do.call(rbind, rows)
  row.names(out) <- NULL
  if (!is.null(columns)) {
    out <- out[, columns, drop = FALSE]
  }
  out
}

dismod_mr_sort_input <- function(data) {
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
