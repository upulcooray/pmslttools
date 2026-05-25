#' Read external DisMod-MR output results
#'
#' Reads a simple long-format CSV produced after an analyst has run DisMod-MR
#' outside the package. This function validates the modelled output contract but
#' does not convert the results into `pmslt_disease_epi.csv`.
#'
#' @param path Path to one DisMod-MR output CSV file.
#' @param target_grid Optional target grid used to check that every requested
#'   disease, age, sex, stratum, and parameter combination is present. Supply
#'   either a data frame or a path to `dismod_mr_target_grid.csv`.
#' @param strict Logical. If `TRUE`, invalid outputs stop with a
#'   beginner-facing error. If `FALSE`, validation issues are returned in the
#'   output object.
#'
#' @return An object of class `dismod_mr_outputs` with elements `outputs`,
#'   `validation`, `source_path`, and `target_grid`.
#' @export
#'
#' @examples
#' \dontrun{
#' modelled <- read_dismod_mr_outputs(
#'   "path/to/dismod_mr_results.csv",
#'   target_grid = "path/to/dismod_mr_inputs/dismod_mr_target_grid.csv"
#' )
#' modelled
#' }
read_dismod_mr_outputs <- function(path,
                                   target_grid = NULL,
                                   strict = TRUE) {
  if (!is.character(path) || length(path) != 1 || is.na(path) || !nzchar(path)) {
    stop("`path` must be a single DisMod-MR output CSV file path.", call. = FALSE)
  }
  if (!file.exists(path)) {
    stop("DisMod-MR output file does not exist: ", path, call. = FALSE)
  }

  outputs <- utils::read.csv(path, stringsAsFactors = FALSE, na.strings = c("", "NA"))
  target_grid_data <- dismod_mr_read_target_grid(target_grid)
  validation <- validate_dismod_mr_outputs(outputs, target_grid = target_grid_data, strict = strict)

  structure(
    list(
      outputs = dismod_mr_clean_outputs(outputs),
      validation = validation,
      source_path = path,
      target_grid = target_grid_data
    ),
    class = "dismod_mr_outputs"
  )
}

#' Validate external DisMod-MR output results
#'
#' Checks that modelled DisMod-MR outputs use the package's long-format output
#' contract. The accepted modelled parameters are incidence, prevalence,
#' remission, excess mortality, and case fatality. `disability_weight` is not a
#' DisMod-MR modelled parameter and is rejected.
#'
#' @param outputs A data frame of DisMod-MR outputs, or a `dismod_mr_outputs`
#'   object returned by `read_dismod_mr_outputs()`.
#' @param target_grid Optional target grid as a data frame or path to
#'   `dismod_mr_target_grid.csv`.
#' @param strict Logical. If `TRUE`, validation errors stop execution. If
#'   `FALSE`, the validation object is returned with all collected issues.
#'
#' @return An object of class `dismod_mr_output_validation`.
#' @export
validate_dismod_mr_outputs <- function(outputs,
                                       target_grid = NULL,
                                       strict = TRUE) {
  if (inherits(outputs, "dismod_mr_outputs")) {
    outputs <- outputs$outputs
  }
  if (!is.data.frame(outputs)) {
    stop("DisMod-MR outputs must be a data frame or a `dismod_mr_outputs` object.", call. = FALSE)
  }

  required_columns <- dismod_mr_output_required_columns()
  optional_columns <- dismod_mr_output_optional_columns()
  allowed_parameters <- dismod_mr_parameters()
  issues <- dismod_mr_empty_output_issues()

  missing_columns <- setdiff(required_columns, names(outputs))
  if (length(missing_columns) > 0) {
    for (column in missing_columns) {
      issues <- dismod_mr_add_output_issue(
        issues,
        severity = "error",
        issue = "missing_required_column",
        column = column,
        row = NA_integer_,
        message = paste0("DisMod-MR outputs are missing required column `", column, "`.")
      )
    }
  }

  if (length(missing_columns) == 0) {
    issues <- dismod_mr_validate_output_rows(issues, outputs, allowed_parameters)
    issues <- dismod_mr_validate_output_duplicates(issues, outputs)
  }

  target_grid_data <- dismod_mr_read_target_grid(target_grid)
  if (!is.null(target_grid_data)) {
    issues <- dismod_mr_validate_target_grid(issues, outputs, target_grid_data, missing_columns)
  }

  issues <- dismod_mr_finalize_output_issues(issues)
  summary <- data.frame(
    metric = c("rows", "errors", "warnings"),
    value = c(
      nrow(outputs),
      sum(issues$severity == "error"),
      sum(issues$severity == "warning")
    ),
    stringsAsFactors = FALSE
  )
  validation <- structure(
    list(
      issues = issues,
      summary = summary,
      is_valid = !any(issues$severity == "error"),
      required_columns = required_columns,
      optional_columns = optional_columns,
      allowed_parameters = allowed_parameters
    ),
    class = "dismod_mr_output_validation"
  )

  if (isTRUE(strict) && !validation$is_valid) {
    dismod_mr_stop_for_output_errors(validation)
  }
  validation
}

#' @export
print.dismod_mr_outputs <- function(x, ...) {
  cat("DisMod-MR outputs\n")
  cat("Source path: ", x$source_path %||% "<in memory>", "\n", sep = "")
  cat("Rows: ", nrow(x$outputs), "\n", sep = "")
  cat("Diseases: ", length(unique(stats::na.omit(x$outputs$disease))), "\n", sep = "")
  cat("Parameters: ", length(unique(stats::na.omit(x$outputs$parameter))), "\n", sep = "")
  cat("Validation passed: ", if (isTRUE(x$validation$is_valid)) "yes" else "no", "\n", sep = "")
  cat("Target-grid validation: ", if (is.null(x$target_grid)) "not used" else "used", "\n", sep = "")
  invisible(x)
}

#' @export
print.dismod_mr_output_validation <- function(x, ...) {
  errors <- sum(x$issues$severity == "error")
  warnings <- sum(x$issues$severity == "warning")
  cat("DisMod-MR output validation\n")
  cat("Status: ", if (isTRUE(x$is_valid)) "passed" else "failed", "\n", sep = "")
  cat("Errors: ", errors, "\n", sep = "")
  cat("Warnings: ", warnings, "\n", sep = "")
  if (nrow(x$issues) > 0) {
    counts <- sort(table(x$issues$issue), decreasing = TRUE)
    brief <- paste(paste(names(counts), as.integer(counts), sep = ": "), collapse = "; ")
    cat("Issue summary: ", brief, "\n", sep = "")
    print.data.frame(utils::head(x$issues, 10), row.names = FALSE)
    if (nrow(x$issues) > 10) {
      cat("... ", nrow(x$issues) - 10, " more issue(s)\n", sep = "")
    }
  }
  invisible(x)
}

dismod_mr_output_required_columns <- function() {
  c("age", "sex", "stratum", "disease", "parameter", "mean_value")
}

dismod_mr_output_optional_columns <- function() {
  c("lower_95", "upper_95")
}

dismod_mr_output_key_columns <- function() {
  c("disease", "age", "sex", "stratum", "parameter")
}

dismod_mr_read_target_grid <- function(target_grid) {
  if (is.null(target_grid)) {
    return(NULL)
  }
  if (is.character(target_grid) && length(target_grid) == 1 && !is.na(target_grid)) {
    if (!file.exists(target_grid)) {
      stop("DisMod-MR target grid file does not exist: ", target_grid, call. = FALSE)
    }
    return(utils::read.csv(target_grid, stringsAsFactors = FALSE, na.strings = c("", "NA")))
  }
  if (is.data.frame(target_grid)) {
    return(target_grid)
  }
  stop("`target_grid` must be NULL, a data frame, or a path to `dismod_mr_target_grid.csv`.", call. = FALSE)
}

dismod_mr_clean_outputs <- function(outputs) {
  out <- as.data.frame(outputs, stringsAsFactors = FALSE)
  for (column in intersect(c("disease", "sex", "stratum", "parameter"), names(out))) {
    out[[column]] <- as.character(out[[column]])
  }
  for (column in intersect(c("age", "mean_value", "lower_95", "upper_95"), names(out))) {
    out[[column]] <- suppressWarnings(as.numeric(out[[column]]))
  }
  if ("age" %in% names(out)) {
    valid_age <- !is.na(out$age) & abs(out$age - round(out$age)) < .Machine$double.eps^0.5
    out$age[valid_age] <- as.integer(round(out$age[valid_age]))
  }
  sort_columns <- intersect(c("disease", "sex", "stratum", "parameter", "age"), names(out))
  if (length(sort_columns) == 5 && nrow(out) > 0) {
    order_args <- c(out[sort_columns], list(na.last = TRUE))
    out <- out[do.call(order, order_args), , drop = FALSE]
    row.names(out) <- NULL
  }
  out
}

dismod_mr_empty_output_issues <- function() {
  dismod_mr_finalize_output_issues(data.frame(
    severity = character(),
    issue = character(),
    column = character(),
    row = integer(),
    message = character(),
    stringsAsFactors = FALSE
  ))
}

dismod_mr_add_output_issue <- function(issues, severity, issue, column, row, message) {
  dismod_mr_finalize_output_issues(rbind(
    as.data.frame(issues, stringsAsFactors = FALSE),
    data.frame(
      severity = severity,
      issue = issue,
      column = column,
      row = as.integer(row),
      message = message,
      stringsAsFactors = FALSE
    )
  ))
}

dismod_mr_finalize_output_issues <- function(issues) {
  issues <- as.data.frame(issues, stringsAsFactors = FALSE)
  expected <- c("severity", "issue", "column", "row", "message")
  issues <- issues[, expected, drop = FALSE]
  issues$row <- as.integer(issues$row)
  row.names(issues) <- NULL
  issues
}

dismod_mr_validate_output_rows <- function(issues, outputs, allowed_parameters) {
  identifier_columns <- c("disease", "sex", "stratum", "parameter")
  for (column in identifier_columns) {
    values <- as.character(outputs[[column]])
    bad <- which(is.na(outputs[[column]]) | !nzchar(trimws(values)))
    for (row in bad) {
      issues <- dismod_mr_add_output_issue(
        issues,
        severity = "error",
        issue = "missing_identifier",
        column = column,
        row = row,
        message = paste0("DisMod-MR outputs row ", row, " has missing or empty `", column, "`.")
      )
    }
  }

  parameters <- as.character(outputs$parameter)
  unsupported <- which(!is.na(outputs$parameter) & nzchar(trimws(parameters)) & !parameters %in% allowed_parameters)
  for (row in unsupported) {
    issues <- dismod_mr_add_output_issue(
      issues,
      severity = "error",
      issue = "unsupported_parameter",
      column = "parameter",
      row = row,
      message = paste0(
        "DisMod-MR outputs row ", row, " uses unsupported parameter `",
        parameters[[row]], "`. Allowed parameters are: ",
        paste(allowed_parameters, collapse = ", "), "."
      )
    )
  }

  issues <- dismod_mr_validate_numeric_column(
    issues, outputs, "age",
    missing_issue = "invalid_age",
    missing_message = "Age must be present as an exact integer single-year age."
  )
  age <- suppressWarnings(as.numeric(outputs$age))
  non_integer <- which(!is.na(age) & abs(age - round(age)) >= .Machine$double.eps^0.5)
  for (row in non_integer) {
    issues <- dismod_mr_add_output_issue(
      issues,
      severity = "error",
      issue = "non_integer_age",
      column = "age",
      row = row,
      message = paste0("DisMod-MR outputs row ", row, " has age `", outputs$age[[row]], "`. Ages must be exact integer single-year ages.")
    )
  }

  issues <- dismod_mr_validate_numeric_column(
    issues, outputs, "mean_value",
    missing_issue = "missing_mean_value",
    missing_message = "`mean_value` must be present and numeric."
  )
  mean_value <- suppressWarnings(as.numeric(outputs$mean_value))
  negative_mean <- which(!is.na(mean_value) & mean_value < 0)
  for (row in negative_mean) {
    issues <- dismod_mr_add_output_issue(
      issues,
      severity = "error",
      issue = "negative_mean_value",
      column = "mean_value",
      row = row,
      message = paste0("DisMod-MR outputs row ", row, " has negative `mean_value`.")
    )
  }

  dismod_mr_validate_uncertainty_columns(issues, outputs, mean_value)
}

dismod_mr_validate_numeric_column <- function(issues, outputs, column, missing_issue, missing_message) {
  values <- suppressWarnings(as.numeric(outputs[[column]]))
  bad <- which(is.na(values))
  for (row in bad) {
    issues <- dismod_mr_add_output_issue(
      issues,
      severity = "error",
      issue = missing_issue,
      column = column,
      row = row,
      message = paste0("DisMod-MR outputs row ", row, ": ", missing_message)
    )
  }
  issues
}

dismod_mr_validate_uncertainty_columns <- function(issues, outputs, mean_value) {
  has_lower <- "lower_95" %in% names(outputs)
  has_upper <- "upper_95" %in% names(outputs)
  if (xor(has_lower, has_upper)) {
    column <- if (has_lower) "upper_95" else "lower_95"
    return(dismod_mr_add_output_issue(
      issues,
      severity = "error",
      issue = "one_sided_uncertainty",
      column = column,
      row = NA_integer_,
      message = "DisMod-MR outputs must include both `lower_95` and `upper_95`, or neither uncertainty column."
    ))
  }
  if (!has_lower && !has_upper) {
    return(issues)
  }

  lower <- suppressWarnings(as.numeric(outputs$lower_95))
  upper <- suppressWarnings(as.numeric(outputs$upper_95))
  for (column in c("lower_95", "upper_95")) {
    values <- suppressWarnings(as.numeric(outputs[[column]]))
    missing <- which(is.na(values))
    for (row in missing) {
      issues <- dismod_mr_add_output_issue(
        issues,
        severity = "error",
        issue = "missing_uncertainty_value",
        column = column,
        row = row,
        message = paste0("DisMod-MR outputs row ", row, " has missing or non-numeric `", column, "`.")
      )
    }
    negative <- which(!is.na(values) & values < 0)
    for (row in negative) {
      issues <- dismod_mr_add_output_issue(
        issues,
        severity = "error",
        issue = "negative_uncertainty_value",
        column = column,
        row = row,
        message = paste0("DisMod-MR outputs row ", row, " has negative `", column, "`.")
      )
    }
  }

  bad_lower <- which(!is.na(lower) & !is.na(mean_value) & lower > mean_value)
  for (row in bad_lower) {
    issues <- dismod_mr_add_output_issue(
      issues,
      severity = "error",
      issue = "invalid_uncertainty_bounds",
      column = "lower_95",
      row = row,
      message = paste0("DisMod-MR outputs row ", row, " has `lower_95` greater than `mean_value`.")
    )
  }
  bad_upper <- which(!is.na(upper) & !is.na(mean_value) & upper < mean_value)
  for (row in bad_upper) {
    issues <- dismod_mr_add_output_issue(
      issues,
      severity = "error",
      issue = "invalid_uncertainty_bounds",
      column = "upper_95",
      row = row,
      message = paste0("DisMod-MR outputs row ", row, " has `upper_95` less than `mean_value`.")
    )
  }
  issues
}

dismod_mr_validate_output_duplicates <- function(issues, outputs) {
  key <- dismod_mr_output_key(outputs)
  duplicated_rows <- which(duplicated(key) | duplicated(key, fromLast = TRUE))
  for (row in duplicated_rows) {
    issues <- dismod_mr_add_output_issue(
      issues,
      severity = "error",
      issue = "duplicate_key_row",
      column = paste(dismod_mr_output_key_columns(), collapse = ", "),
      row = row,
      message = paste0("DisMod-MR outputs row ", row, " duplicates another disease-age-sex-stratum-parameter combination.")
    )
  }
  issues
}

dismod_mr_validate_target_grid <- function(issues, outputs, target_grid, missing_output_columns) {
  key_columns <- dismod_mr_output_key_columns()
  missing_target_columns <- setdiff(key_columns, names(target_grid))
  for (column in missing_target_columns) {
    issues <- dismod_mr_add_output_issue(
      issues,
      severity = "error",
      issue = "target_grid_missing_column",
      column = column,
      row = NA_integer_,
      message = paste0("DisMod-MR target grid is missing required column `", column, "`.")
    )
  }
  if (length(missing_target_columns) > 0 || length(intersect(key_columns, missing_output_columns)) > 0) {
    return(issues)
  }

  output_keys <- dismod_mr_output_key(outputs)
  target_keys <- dismod_mr_output_key(target_grid)
  missing <- which(!target_keys %in% output_keys)
  for (row in missing) {
    issues <- dismod_mr_add_output_issue(
      issues,
      severity = "error",
      issue = "missing_target_grid_combination",
      column = paste(key_columns, collapse = ", "),
      row = row,
      message = paste0("DisMod-MR outputs are missing target-grid combination row ", row, ".")
    )
  }
  extra <- which(!output_keys %in% target_keys)
  for (row in extra) {
    issues <- dismod_mr_add_output_issue(
      issues,
      severity = "warning",
      issue = "extra_output_row",
      column = paste(key_columns, collapse = ", "),
      row = row,
      message = paste0("DisMod-MR outputs row ", row, " was not requested by the target grid.")
    )
  }
  issues
}

dismod_mr_output_key <- function(data) {
  key_columns <- dismod_mr_output_key_columns()
  parts <- lapply(key_columns, function(column) {
    if (column == "age") {
      value <- suppressWarnings(as.numeric(data[[column]]))
      return(ifelse(is.na(value), NA_character_, as.character(value)))
    }
    as.character(data[[column]])
  })
  do.call(paste, c(parts, sep = "\r"))
}

dismod_mr_stop_for_output_errors <- function(validation) {
  errors <- validation$issues[validation$issues$severity == "error", , drop = FALSE]
  messages <- unique(errors$message)
  shown <- utils::head(messages, 5)
  suffix <- if (length(messages) > 5) {
    paste0("\n... ", length(messages) - 5, " more error(s).")
  } else {
    ""
  }
  stop(
    "DisMod-MR outputs failed validation:\n- ",
    paste(shown, collapse = "\n- "),
    suffix,
    call. = FALSE
  )
}
