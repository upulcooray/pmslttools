#' Summarise deterministic PMSLT costs
#'
#' Summarises cost columns from an existing PMSLT-style output table. This is a
#' reporting helper only: it does not discount costs, assign thresholds, or
#' change simulation outputs.
#'
#' @param costs Data frame with PMSLT reporting keys and one or more cost
#'   columns. Cost columns are detected from `cost`, `costs`, `total_cost`, and
#'   columns ending in `_cost` or `_costs`.
#' @param by Character vector of grouping variables. Use `"overall"` for one
#'   ungrouped row, or any combination of `"time_step"`, `"sex"`, `"stratum"`,
#'   `"age"`, and `"age_band"`.
#' @param cost_cols Optional character vector naming the cost columns to
#'   summarise.
#' @param group_by Optional alias for `by`.
#' @param spec Optional `pmslt_spec` object used only for reporting
#'   `age_band` when `costs` does not already carry a `spec` attribute.
#'
#' @return A plain data frame with grouping columns followed by cost totals.
#' @export
summarise_costs <- function(costs,
                            by = c("overall", "time_step", "sex", "stratum", "age", "age_band"),
                            cost_cols = NULL,
                            group_by = NULL,
                            spec = NULL) {
  by <- resolve_reporting_grouping(by, group_by, missing(by), "cost")
  validate_comparison_grouping(by)
  costs <- validate_cost_summary_input(costs, cost_cols, spec)
  group_cols <- if (identical(by, "overall")) character() else by

  if ("age_band" %in% group_cols) {
    costs <- attach_summary_age_band(costs, costs)
  }
  missing_groups <- setdiff(group_cols, names(costs))
  if (length(missing_groups) > 0) {
    stop("Cannot summarise costs by `", missing_groups[[1]], "` because that column is not in `costs`.", call. = FALSE)
  }

  cost_cols <- reporting_cost_columns(costs, cost_cols)
  require_summary_metrics(costs, cost_cols, "costs")
  summarise_numeric_columns(costs, group_cols, cost_cols)
}

#' Compare intervention and BAU deterministic PMSLT costs
#'
#' Creates intervention-minus-BAU cost summaries from compatible cost outputs.
#' This is a reporting helper only: it does not discount costs, assign
#' thresholds, or change simulation outputs.
#'
#' @param bau_costs BAU cost output.
#' @param intervention_costs Intervention cost output with the same
#'   `time_step`, `age`, `sex`, and `stratum` structure as `bau_costs`.
#' @inheritParams summarise_costs
#'
#' @return A plain data frame with grouping columns followed by cost
#'   differences calculated as `intervention - BAU`.
#' @export
compare_costs <- function(bau_costs,
                          intervention_costs,
                          by = c("overall", "time_step", "sex", "stratum", "age", "age_band"),
                          cost_cols = NULL,
                          spec = NULL) {
  by <- if (missing(by)) "overall" else as.character(by)
  validate_comparison_grouping(by)
  bau_costs <- validate_cost_summary_input(bau_costs, cost_cols, spec, label = "bau_costs")
  intervention_costs <- validate_cost_summary_input(intervention_costs, cost_cols, spec, label = "intervention_costs")
  validate_comparison_structure(bau_costs, intervention_costs)

  bau_summary <- summarise_costs(bau_costs, by = by, cost_cols = cost_cols)
  intervention_summary <- summarise_costs(intervention_costs, by = by, cost_cols = cost_cols)
  compare_summary_tables(bau_summary, intervention_summary, by)
}

#' Calculate deterministic ICERs
#'
#' Calculates ICERs only from an incremental reporting table that already
#' contains incremental costs and incremental HALYs. The incremental convention
#' must be `intervention - BAU`.
#'
#' @param incremental_results Data frame containing one incremental cost column
#'   and one incremental HALY column.
#' @param incremental_cost Column name for incremental costs. If omitted, the
#'   first detected cost-difference column is used.
#' @param incremental_haly Column name for incremental HALYs. Defaults to
#'   `haly_difference`, with `halys_difference` accepted as a fallback.
#'
#' @return A plain data frame containing the input columns plus `icer` and
#'   `icer_status`. ICER is reported only when incremental HALYs are positive.
#' @export
calculate_icers <- function(incremental_results,
                            incremental_cost = NULL,
                            incremental_haly = NULL) {
  if (!is.data.frame(incremental_results)) {
    stop("`incremental_results` must be a data frame with incremental costs and incremental HALYs.", call. = FALSE)
  }
  incremental_cost <- resolve_incremental_cost_column(incremental_results, incremental_cost)
  incremental_haly <- resolve_incremental_haly_column(incremental_results, incremental_haly)
  require_summary_metrics(incremental_results, c(incremental_cost, incremental_haly), "incremental_results")

  out <- as.data.frame(incremental_results, stringsAsFactors = FALSE)
  inc_cost <- as.numeric(out[[incremental_cost]])
  inc_haly <- as.numeric(out[[incremental_haly]])

  out$icer <- NA_real_
  positive <- inc_haly > 0
  out$icer[positive] <- inc_cost[positive] / inc_haly[positive]
  out$icer_status <- ifelse(
    inc_haly > 0,
    "positive_incremental_halys",
    ifelse(inc_haly == 0, "zero_incremental_halys", "negative_incremental_halys")
  )
  out
}

resolve_reporting_grouping <- function(by, group_by, by_missing, label) {
  if (!is.null(group_by)) {
    if (!by_missing) {
      stop("Use either `by` or `group_by`, not both.", call. = FALSE)
    }
    return(as.character(group_by))
  }
  if (by_missing) {
    return("overall")
  }
  as.character(by)
}

validate_cost_summary_input <- function(costs,
                                        cost_cols = NULL,
                                        spec = NULL,
                                        label = "costs") {
  if (!is.data.frame(costs)) {
    stop("`", label, "` must be a data frame with PMSLT cost outputs.", call. = FALSE)
  }
  required <- c("time_step", "age", "sex", "stratum")
  require_columns(costs, required, label)
  validate_lifetable_age(costs$age, label)
  time_step <- suppressWarnings(as.numeric(costs$time_step))
  if (any(is.na(time_step)) ||
      any(abs(time_step - round(time_step)) > .Machine$double.eps^0.5)) {
    stop("`time_step` in `", label, "` must contain non-missing whole numbers.", call. = FALSE)
  }
  if (any(!stats::complete.cases(costs[required]))) {
    stop("`", label, "` has missing time_step, age, sex, or stratum values.", call. = FALSE)
  }
  duplicate_key <- duplicated(costs[required])
  if (any(duplicate_key)) {
    first <- costs[which(duplicate_key)[[1]], required, drop = FALSE]
    stop(
      "`", label, "` must have only one row per time_step, age, sex, and stratum. ",
      "First duplicate: age=", first$age[[1]],
      ", sex=", first$sex[[1]],
      ", stratum=", first$stratum[[1]],
      ", time_step=", first$time_step[[1]], ".",
      call. = FALSE
    )
  }
  detected_cost_cols <- reporting_cost_columns(costs, cost_cols)
  if (length(detected_cost_cols) == 0) {
    stop(
      "Cannot summarise costs because `", label, "` has no cost columns. ",
      "Use `cost`, `costs`, `total_cost`, or columns ending in `_cost` or `_costs`, or supply `cost_cols`.",
      call. = FALSE
    )
  }
  if (!is.null(spec)) {
    validate_spec(spec)
    attr(costs, "spec") <- spec
  }
  costs
}

reporting_cost_columns <- function(data, cost_cols = NULL) {
  if (!is.null(cost_cols)) {
    if (!is.character(cost_cols) || length(cost_cols) == 0 || any(is.na(cost_cols))) {
      stop("`cost_cols` must be a non-empty character vector.", call. = FALSE)
    }
    missing_cols <- setdiff(cost_cols, names(data))
    if (length(missing_cols) > 0) {
      stop("Cost column `", missing_cols[[1]], "` is not in the data.", call. = FALSE)
    }
    return(cost_cols)
  }

  names(data)[
    names(data) %in% c("cost", "costs", "total_cost") |
      grepl("(_cost|_costs)$", names(data))
  ]
}

resolve_incremental_cost_column <- function(incremental_results, incremental_cost) {
  if (!is.null(incremental_cost)) {
    if (!is.character(incremental_cost) || length(incremental_cost) != 1 || is.na(incremental_cost)) {
      stop("`incremental_cost` must be one column name.", call. = FALSE)
    }
    if (!incremental_cost %in% names(incremental_results)) {
      stop("Incremental cost column `", incremental_cost, "` is not in `incremental_results`.", call. = FALSE)
    }
    return(incremental_cost)
  }

  candidates <- names(incremental_results)[
    grepl("(^cost|_cost|_costs|total_cost).*_difference$", names(incremental_results)) |
      names(incremental_results) %in% c("incremental_cost", "incremental_costs")
  ]
  if (length(candidates) == 0) {
    stop(
      "Cannot calculate ICERs because `incremental_results` has no incremental cost column. ",
      "Supply `incremental_cost` or pass output from `compare_costs()`.",
      call. = FALSE
    )
  }
  if (length(candidates) > 1) {
    stop(
      "Cannot choose one incremental cost column automatically. Supply `incremental_cost`; candidates are: ",
      paste(candidates, collapse = ", "),
      ".",
      call. = FALSE
    )
  }
  candidates[[1]]
}

resolve_incremental_haly_column <- function(incremental_results, incremental_haly) {
  if (!is.null(incremental_haly)) {
    if (!is.character(incremental_haly) || length(incremental_haly) != 1 || is.na(incremental_haly)) {
      stop("`incremental_haly` must be one column name.", call. = FALSE)
    }
    if (!incremental_haly %in% names(incremental_results)) {
      stop("Incremental HALY column `", incremental_haly, "` is not in `incremental_results`.", call. = FALSE)
    }
    return(incremental_haly)
  }

  candidates <- intersect(c("haly_difference", "halys_difference", "incremental_haly", "incremental_halys"), names(incremental_results))
  if (length(candidates) == 0) {
    stop(
      "Cannot calculate ICERs because `incremental_results` has no incremental HALY column. ",
      "Supply `incremental_haly` or pass output from `compare_halys()`.",
      call. = FALSE
    )
  }
  candidates[[1]]
}
