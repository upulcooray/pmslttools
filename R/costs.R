#' Validate PMSLT cost inputs
#'
#' Checks a `12_costs.csv`-style data frame or CSV path before deterministic
#' costs are attached to lifetable results. The column-level checks use the
#' central schema rules for `12_costs.csv`; additional checks make sure currency,
#' price year, and repeated background costs are internally consistent.
#'
#' @param costs Data frame or CSV path using the `12_costs.csv` schema.
#' @param spec Optional `pmslt_spec` object used to validate generated labels.
#'
#' @return A data frame with class `pmslt_validation_issues`.
#' @export
validate_cost_inputs <- function(costs, spec = NULL) {
  if (!is.null(spec)) {
    validate_spec(spec)
  }

  read <- read_cost_input_for_validation(costs)
  if (inherits(read, "pmslt_validation_issues")) {
    return(read)
  }

  data <- read$data
  file <- read$file
  schema <- pmslt_input_schemas()[["12_costs"]]
  issues <- empty_validation_issues()

  expected_columns <- schema$columns$column
  missing_columns <- setdiff(expected_columns, names(data))
  for (column in missing_columns) {
    issues <- append_validation_issue(
      issues,
      file = file,
      row = NA_integer_,
      column = column,
      severity = "error",
      message = paste0("Required cost input column '", column, "' is missing."),
      suggested_fix = paste0("Regenerate 12_costs.csv or add the '", column, "' column.")
    )
  }

  issues <- validate_required_missing_values(issues, data, file, schema)
  for (column in intersect(expected_columns, names(data))) {
    validation <- raw_column_validation("12_costs", column)
    issues <- validate_column_values(issues, data, file, column, validation, spec)
  }
  issues <- validate_age_consistency(issues, data, file)
  issues <- validate_duplicate_key_rows(issues, data, file, schema)
  issues <- validate_cost_consistency(issues, data, file)

  finalize_validation_issues(issues)
}

#' Attach deterministic costs to PMSLT lifetable results
#'
#' Uses `12_costs.csv` inputs to add annual background costs and disease-
#' management costs to compatible exact-age lifetable results. Disease costs
#' are calculated only when `results` includes disease deltas from
#' [integrate_disease_deltas()]. Background costs are counted once per
#' lifetable row, even though `12_costs.csv` has one row per disease.
#'
#' @param results Output from [run_pmslt_lifetable_bau()] or
#'   [integrate_disease_deltas()].
#' @param costs Data frame or CSV path using the `12_costs.csv` schema.
#' @param spec Optional `pmslt_spec` object used to validate generated labels.
#'
#' @return A `pmslt_lifetable` data frame with `background_costs`,
#'   `total_disease_costs`, and `total_costs` columns.
#' @export
attach_pmslt_costs <- function(results, costs, spec = NULL) {
  validate_cost_results(results, "results")
  issues <- validate_cost_inputs(costs, spec = spec)
  stop_for_cost_issues(issues)

  costs <- read_cost_input(costs, "costs")
  costs <- normalize_cost_inputs(costs)
  metadata <- cost_metadata(costs)

  out <- results
  out$.pmslt_row_id <- seq_len(nrow(out))
  background <- match_background_costs(out, costs)
  out$background_cost_per_person <- background$background_cost
  out$background_costs <- out$person_years * out$background_cost_per_person
  out$total_disease_costs <- 0

  disease_details <- attach_disease_cost_details(out, costs)
  if (!is.null(disease_details)) {
    totals <- stats::aggregate(
      disease_details["disease_costs"],
      by = list(.pmslt_row_id = disease_details$.pmslt_row_id),
      FUN = sum
    )
    out$total_disease_costs <- totals$disease_costs[match(out$.pmslt_row_id, totals$.pmslt_row_id)]
    out$total_disease_costs[is.na(out$total_disease_costs)] <- 0
  }

  out$total_costs <- out$background_costs + out$total_disease_costs
  out$.pmslt_row_id <- NULL
  row.names(out) <- NULL
  class(out) <- class(results)
  attr(out, "spec") <- attr(results, "spec", exact = TRUE)
  attr(out, "ageing_rule") <- attr(results, "ageing_rule", exact = TRUE)
  attr(out, "disease_deltas") <- attr(results, "disease_deltas", exact = TRUE)
  attr(out, "cost_currency") <- metadata$currency
  attr(out, "cost_price_year") <- metadata$price_year
  if (!is.null(disease_details)) {
    disease_details$.pmslt_row_id <- NULL
    row.names(disease_details) <- NULL
    attr(out, "cost_disease_details") <- disease_details
  }
  out
}

#' Summarise deterministic PMSLT costs
#'
#' @param results Output from `attach_pmslt_costs()`.
#' @param by Character vector of grouping variables. Use `"overall"` by itself
#'   for one total row, or combine `"time_step"`, `"sex"`, `"stratum"`, `"age"`,
#'   `"age_band"`, and `"disease"` where available.
#' @param group_by Optional alias for `by`.
#'
#' @return A plain data frame with grouping columns and cost totals.
#' @export
summarise_pmslt_costs <- function(results,
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
  by <- as.character(by)
  validate_cost_grouping(by)
  validate_costed_results(results, "results")

  if ("disease" %in% by) {
    return(summarise_disease_costs(results, by))
  }

  group_cols <- if (identical(by, "overall")) character() else by
  data <- results
  if ("age_band" %in% group_cols) {
    data <- attach_summary_age_band(data, results)
  }
  missing_groups <- setdiff(group_cols, names(data))
  if (length(missing_groups) > 0) {
    stop("Cannot summarise costs by `", missing_groups[[1]], "` because that column is not in `results`.", call. = FALSE)
  }
  metrics <- c("background_costs", "total_disease_costs", "total_costs")
  require_summary_metrics(data, metrics, "results")
  add_cost_metadata_columns(summarise_numeric_columns(data, group_cols, metrics), results)
}

#' Compare deterministic PMSLT costs
#'
#' Creates intervention-minus-BAU cost differences from two compatible costed
#' PMSLT lifetable outputs.
#'
#' @param bau_results BAU output from `attach_pmslt_costs()`.
#' @param intervention_results Intervention output from `attach_pmslt_costs()`
#'   with the same result structure as `bau_results`.
#' @param by Character vector of grouping variables passed to
#'   `summarise_pmslt_costs()`.
#'
#' @return A plain data frame with cost differences calculated as
#'   `intervention - BAU`.
#' @export
compare_pmslt_costs <- function(bau_results,
                                intervention_results,
                                by = c("overall", "time_step", "sex", "stratum", "age", "age_band", "disease")) {
  by <- if (missing(by)) "overall" else as.character(by)
  validate_cost_grouping(by)
  validate_costed_results(bau_results, "bau_results")
  validate_costed_results(intervention_results, "intervention_results")
  validate_cost_metadata_match(bau_results, intervention_results)
  validate_comparison_structure(bau_results, intervention_results)

  bau_summary <- summarise_pmslt_costs(bau_results, by = by)
  intervention_summary <- summarise_pmslt_costs(intervention_results, by = by)
  metadata_cols <- c("currency", "price_year")
  bau_compare <- bau_summary[setdiff(names(bau_summary), metadata_cols)]
  intervention_compare <- intervention_summary[setdiff(names(intervention_summary), metadata_cols)]
  out <- compare_summary_tables(bau_compare, intervention_compare, by)
  add_cost_metadata_columns(out, bau_results)
}

read_cost_input_for_validation <- function(costs) {
  if (is.character(costs) && length(costs) == 1) {
    if (!file.exists(costs)) {
      return(append_validation_issue(
        empty_validation_issues(),
        file = basename(costs),
        row = NA_integer_,
        column = NA_character_,
        severity = "error",
        message = paste0("Cost input file does not exist: ", costs, "."),
        suggested_fix = "Check the path to 12_costs.csv or regenerate the raw input templates."
      ))
    }
    return(list(
      data = utils::read.csv(costs, stringsAsFactors = FALSE, na.strings = c("", "NA"), check.names = FALSE),
      file = basename(costs)
    ))
  }
  if (!is.data.frame(costs)) {
    return(append_validation_issue(
      empty_validation_issues(),
      file = "12_costs.csv",
      row = NA_integer_,
      column = NA_character_,
      severity = "error",
      message = "`costs` must be a data frame or a CSV file path.",
      suggested_fix = "Pass a data frame with the 12_costs.csv columns or the path to 12_costs.csv."
    ))
  }
  list(data = costs, file = "12_costs.csv")
}

read_cost_input <- function(costs, label) {
  if (is.character(costs) && length(costs) == 1) {
    if (!file.exists(costs)) {
      stop("Missing ", label, " file: ", costs, call. = FALSE)
    }
    return(utils::read.csv(costs, stringsAsFactors = FALSE, na.strings = c("", "NA"), check.names = FALSE))
  }
  if (!is.data.frame(costs)) {
    stop("`", label, "` must be a data frame or a CSV file path.", call. = FALSE)
  }
  costs
}

validate_cost_consistency <- function(issues, data, file) {
  needed <- c("age_start", "age_end", "sex", "stratum", "disease", "disease_cost", "background_cost", "currency", "price_year")
  if (!all(needed %in% names(data))) {
    return(issues)
  }
  issues <- append_single_value_issue(issues, data, file, "currency", "Use one currency in 12_costs.csv before deterministic cost summaries are calculated.")
  issues <- append_single_value_issue(issues, data, file, "price_year", "Use one price year in 12_costs.csv before deterministic cost summaries are calculated.")

  key <- paste(data$age_start, data$age_end, data$sex, data$stratum, sep = "\r")
  for (group in unique(key)) {
    rows <- which(key == group)
    values <- data$background_cost[rows]
    present <- !(is.na(values) | !nzchar(trimws(values)))
    unique_values <- unique(as.character(values[present]))
    if (length(unique_values) > 1) {
      for (row in rows[present]) {
        issues <- append_validation_issue(
          issues,
          file = file,
          row = row,
          column = "background_cost",
          severity = "error",
          message = "Background cost differs across disease rows for the same age, sex, and stratum.",
          suggested_fix = "Use the same background_cost for each disease row in that demographic group, or leave it blank if background costs are handled elsewhere."
        )
      }
    }
  }
  issues
}

append_single_value_issue <- function(issues, data, file, column, fix) {
  values <- data[[column]]
  present <- !(is.na(values) | !nzchar(trimws(values)))
  unique_values <- unique(as.character(values[present]))
  if (length(unique_values) <= 1) {
    return(issues)
  }
  first <- unique_values[[1]]
  bad <- present & as.character(values) != first
  for (row in which(bad)) {
    issues <- append_validation_issue(
      issues,
      file = file,
      row = row,
      column = column,
      severity = "error",
      message = paste0("Column '", column, "' is inconsistent within 12_costs.csv."),
      suggested_fix = fix
    )
  }
  issues
}

normalize_cost_inputs <- function(costs) {
  costs$age_start <- as.numeric(costs$age_start)
  costs$age_end <- as.numeric(costs$age_end)
  costs$sex <- as.character(costs$sex)
  costs$stratum <- as.character(costs$stratum)
  costs$disease <- as.character(costs$disease)
  costs$disease_cost <- as.numeric(costs$disease_cost)
  costs$background_cost <- as.numeric(costs$background_cost)
  costs$background_cost[is.na(costs$background_cost)] <- 0
  costs$currency <- as.character(costs$currency)
  costs$price_year <- as.integer(as.numeric(costs$price_year))
  costs
}

cost_metadata <- function(costs) {
  list(
    currency = unique(costs$currency[!is.na(costs$currency) & nzchar(costs$currency)])[[1]],
    price_year = unique(costs$price_year[!is.na(costs$price_year)])[[1]]
  )
}

validate_cost_results <- function(results, label) {
  if (!is.data.frame(results) || !inherits(results, "pmslt_lifetable")) {
    stop("`", label, "` must be a PMSLT lifetable result.", call. = FALSE)
  }
  required <- c("time_step", "age", "sex", "stratum", "person_years")
  require_columns(results, required, label)
  require_summary_metrics(results, "person_years", label)
  invisible(TRUE)
}

validate_costed_results <- function(results, label) {
  validate_cost_results(results, label)
  required <- c("background_costs", "total_disease_costs", "total_costs")
  require_columns(results, required, label)
  require_summary_metrics(results, required, label)
  invisible(TRUE)
}

stop_for_cost_issues <- function(issues) {
  if (any(issues$severity == "error")) {
    stop(
      "Cost inputs have validation errors. Run `validate_cost_inputs()` to inspect the issue table.",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

match_background_costs <- function(results, costs) {
  background <- stats::aggregate(
    costs["background_cost"],
    by = costs[c("age_start", "age_end", "sex", "stratum")],
    FUN = function(x) unique(x)[[1]]
  )
  match_cost_rows(results, background, keys = c("sex", "stratum"), label = "background costs")
}

attach_disease_cost_details <- function(results, costs) {
  disease_deltas <- attr(results, "disease_deltas", exact = TRUE)
  if (!is.data.frame(disease_deltas)) {
    return(NULL)
  }
  disease_deltas$.pmslt_row_id <- results$.pmslt_row_id[
    match(
      comparison_key_values(disease_deltas[c("time_step", "age", "sex", "stratum")], c("time_step", "age", "sex", "stratum")),
      comparison_key_values(results[c("time_step", "age", "sex", "stratum")], c("time_step", "age", "sex", "stratum"))
    )
  ]
  if (any(is.na(disease_deltas$.pmslt_row_id))) {
    stop("Disease-delta cost attachment could not match every disease row back to the lifetable.", call. = FALSE)
  }
  matched <- match_cost_rows(disease_deltas, costs, keys = c("sex", "stratum", "disease"), label = "disease costs")
  out <- disease_deltas
  out$disease_cost_per_case <- matched$disease_cost
  out$prevalent_cases <- out$person_years * out$disease_prevalence
  out$disease_costs <- out$prevalent_cases * out$disease_cost_per_case
  require_summary_metrics(out, c("prevalent_cases", "disease_costs"), "disease cost details")
  out
}

match_cost_rows <- function(data, costs, keys, label) {
  out <- vector("list", nrow(data))
  for (i in seq_len(nrow(data))) {
    in_age <- data$age[[i]] >= costs$age_start & data$age[[i]] <= costs$age_end
    in_keys <- rep(TRUE, nrow(costs))
    for (key in keys) {
      in_keys <- in_keys & as.character(costs[[key]]) == as.character(data[[key]][[i]])
    }
    matched <- costs[in_age & in_keys, , drop = FALSE]
    if (nrow(matched) != 1) {
      stop(
        "`12_costs.csv` must contain exactly one ", label,
        " row for age=", data$age[[i]],
        ", sex=", data$sex[[i]],
        ", stratum=", data$stratum[[i]],
        if ("disease" %in% keys) paste0(", disease=", data$disease[[i]]) else "",
        ".",
        call. = FALSE
      )
    }
    out[[i]] <- matched
  }
  do.call(rbind, out)
}

validate_cost_grouping <- function(by) {
  allowed <- c("overall", "time_step", "sex", "stratum", "age", "age_band", "disease")
  bad <- setdiff(by, allowed)
  if (length(bad) > 0) {
    stop("Unknown cost grouping variable: `", bad[[1]], "`.", call. = FALSE)
  }
  if ("overall" %in% by && length(by) > 1) {
    stop("Use `by = \"overall\"` by itself, or choose specific cost grouping variables.", call. = FALSE)
  }
  invisible(TRUE)
}

summarise_disease_costs <- function(results, by) {
  details <- attr(results, "cost_disease_details", exact = TRUE)
  if (!is.data.frame(details)) {
    stop(
      "Disease-specific cost summaries need results from `attach_pmslt_costs()` applied after `integrate_disease_deltas()`.",
      call. = FALSE
    )
  }
  group_cols <- by
  if ("age_band" %in% group_cols) {
    details <- attach_summary_age_band(details, results)
  }
  missing_groups <- setdiff(group_cols, names(details))
  if (length(missing_groups) > 0) {
    stop("Cannot summarise disease costs by `", missing_groups[[1]], "` because that column is not in the disease cost details.", call. = FALSE)
  }
  metrics <- c("prevalent_cases", "disease_costs")
  require_summary_metrics(details, metrics, "disease cost details")
  out <- summarise_numeric_columns(details, group_cols, metrics)
  out$total_costs <- out$disease_costs
  add_cost_metadata_columns(out, results)
}

add_cost_metadata_columns <- function(data, results) {
  data$currency <- attr(results, "cost_currency", exact = TRUE)
  data$price_year <- attr(results, "cost_price_year", exact = TRUE)
  data
}

validate_cost_metadata_match <- function(bau_results, intervention_results) {
  if (!identical(attr(bau_results, "cost_currency", exact = TRUE), attr(intervention_results, "cost_currency", exact = TRUE)) ||
      !identical(attr(bau_results, "cost_price_year", exact = TRUE), attr(intervention_results, "cost_price_year", exact = TRUE))) {
    stop("Cannot compare costs with different currencies or price years.", call. = FALSE)
  }
  invisible(TRUE)
}
