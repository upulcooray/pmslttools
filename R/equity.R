# Equity and stratum rate-ratio helpers.

#' List stratum rate-ratio disaggregation targets
#'
#' @return A data frame listing the supported `parameter` values in
#'   `11_stratum_rate_ratios.csv` and the aggregate rate columns they can
#'   disaggregate.
#' @export
stratum_rate_ratio_definitions <- function() {
  data.frame(
    parameter = c(
      "acmr", "morbidity", "incidence", "remission",
      "excess_mortality", "case_fatality", "mortality"
    ),
    applies_to = c(
      "all-cause mortality",
      "all-cause morbidity",
      "disease incidence",
      "disease remission",
      "disease excess mortality",
      "disease case fatality",
      "disease-specific mortality evidence"
    ),
    columns = c(
      "mortality_rate; acmr_BAU",
      "morbidity_rate; pYLD_BAU",
      "incidence_BAU; incidence_rate",
      "remission_rate",
      "excess_mortality_BAU; excess_mortality_rate",
      "case_fatality_BAU; case_fatality_rate",
      "disease_mortality_rate"
    ),
    stringsAsFactors = FALSE
  )
}

stratum_rate_ratio_parameter_names <- function() {
  stratum_rate_ratio_definitions()$parameter
}

stratum_rate_ratio_column_map <- function() {
  list(
    acmr = c("mortality_rate", "acmr_BAU"),
    morbidity = c("morbidity_rate", "pYLD_BAU"),
    incidence = c("incidence_BAU", "incidence_rate"),
    remission = "remission_rate",
    excess_mortality = c("excess_mortality_BAU", "excess_mortality_rate"),
    case_fatality = c("case_fatality_BAU", "case_fatality_rate"),
    mortality = "disease_mortality_rate"
  )
}

#' Disaggregate aggregate rates by model stratum
#'
#' Applies the long-format `11_stratum_rate_ratios.csv` contract to all-cause
#' or disease-rate input tables before PMSLT model execution. Supported
#' disaggregation targets are all-cause mortality (`mortality_rate` or
#' `acmr_BAU`), all-cause morbidity (`morbidity_rate` or `pYLD_BAU`), disease
#' incidence, remission, excess mortality, case fatality, and explicit
#' disease-specific mortality evidence.
#'
#' @param data Data frame containing aggregate rates.
#' @param rate_ratios Data frame or CSV path using columns `age_start` or
#'   `age`, `sex`, `stratum`, `parameter`, `rate_ratio`, and
#'   `reference_stratum`.
#' @param target_keys Optional data frame with the required `age`, `sex`, and
#'   `stratum` combinations. When supplied, aggregate rows are expanded to these
#'   keys before ratios are applied.
#' @param spec Optional `pmslt_spec` object. Used to reject strata outside the
#'   model specification.
#' @param label Short label used in error messages.
#'
#' @return A data frame with disaggregated rate columns plus audit columns named
#'   `<rate>_original_aggregate`, `<rate>_rate_ratio`,
#'   `<rate>_rate_ratio_parameter`, and `<rate>_reference_stratum`.
#' @export
disaggregate_stratum_rates <- function(data,
                                       rate_ratios,
                                       target_keys = NULL,
                                       spec = NULL,
                                       label = "data") {
  if (!is.data.frame(data)) {
    stop("`data` must be a data frame containing aggregate rates.", call. = FALSE)
  }
  if (!is.null(spec)) {
    validate_spec(spec)
  }
  ratios <- read_stratum_rate_ratios(rate_ratios)
  ratios <- normalise_stratum_rate_ratios(ratios, spec)

  targets <- find_stratum_rate_targets(data)
  if (length(targets) == 0) {
    stop(
      "`", label, "` does not contain any disaggregatable rate columns. ",
      "Supported columns are listed by `stratum_rate_ratio_definitions()`.",
      call. = FALSE
    )
  }

  if (!is.null(target_keys)) {
    data <- expand_aggregate_rates_to_target_keys(data, target_keys, label)
  } else {
    data <- normalise_equity_age_column(data, label)
  }
  require_columns(data, c("age", "sex", "stratum"), label)

  for (target in targets) {
    data <- apply_one_stratum_rate_ratio(
      data,
      ratios,
      parameter = target$parameter,
      value_col = target$column,
      label = label
    )
  }

  data
}

read_stratum_rate_ratios <- function(rate_ratios) {
  if (is.character(rate_ratios) && length(rate_ratios) == 1) {
    if (!file.exists(rate_ratios)) {
      stop("Missing stratum rate-ratio file: ", rate_ratios, call. = FALSE)
    }
    return(utils::read.csv(rate_ratios, stringsAsFactors = FALSE, na.strings = c("", "NA")))
  }
  if (!is.data.frame(rate_ratios)) {
    stop("`rate_ratios` must be a data frame or a CSV file path.", call. = FALSE)
  }
  rate_ratios
}

normalise_stratum_rate_ratios <- function(rate_ratios, spec = NULL) {
  rate_ratios <- normalise_equity_age_column(rate_ratios, "rate_ratios")
  require_columns(
    rate_ratios,
    c("age", "sex", "stratum", "parameter", "rate_ratio", "reference_stratum"),
    "rate_ratios"
  )
  rate_ratios$age <- validate_equity_integer(rate_ratios$age, "age", "rate_ratios")
  rate_ratios$sex <- as.character(rate_ratios$sex)
  rate_ratios$stratum <- as.character(rate_ratios$stratum)
  rate_ratios$parameter <- as.character(rate_ratios$parameter)
  rate_ratios$reference_stratum <- as.character(rate_ratios$reference_stratum)
  rate_ratios$rate_ratio <- suppressWarnings(as.numeric(rate_ratios$rate_ratio))

  if (any(is.na(rate_ratios$rate_ratio)) || any(rate_ratios$rate_ratio <= 0)) {
    stop("`rate_ratio` in rate_ratios must contain positive numeric values.", call. = FALSE)
  }
  bad_parameter <- setdiff(unique(rate_ratios$parameter), stratum_rate_ratio_parameter_names())
  if (length(bad_parameter) > 0) {
    stop(
      "Unknown stratum rate-ratio parameter: `", bad_parameter[[1]], "`. ",
      "Use one of: ", paste(stratum_rate_ratio_parameter_names(), collapse = ", "), ".",
      call. = FALSE
    )
  }
  duplicated_key <- duplicated(rate_ratios[c("age", "sex", "stratum", "parameter")])
  if (any(duplicated_key)) {
    first <- rate_ratios[which(duplicated_key)[[1]], , drop = FALSE]
    stop(
      "`rate_ratios` must have one row per age, sex, stratum, and parameter. ",
      "First duplicate: age=", first$age[[1]],
      ", sex=", first$sex[[1]],
      ", stratum=", first$stratum[[1]],
      ", parameter=", first$parameter[[1]], ".",
      call. = FALSE
    )
  }
  if (!is.null(spec)) {
    validate_stratum_rate_ratio_spec_values(rate_ratios, spec)
  }

  rate_ratios
}

validate_stratum_rate_ratio_spec_values <- function(rate_ratios, spec) {
  bad_strata <- setdiff(unique(rate_ratios$stratum), spec$strata)
  if (length(bad_strata) > 0) {
    stop(
      "`rate_ratios` includes stratum `", bad_strata[[1]],
      "`, which is not in `spec$strata`.",
      call. = FALSE
    )
  }
  bad_reference <- setdiff(unique(rate_ratios$reference_stratum), spec$strata)
  if (length(bad_reference) > 0) {
    stop(
      "`rate_ratios` includes reference_stratum `", bad_reference[[1]],
      "`, which is not in `spec$strata`.",
      call. = FALSE
    )
  }
  bad_sex <- setdiff(unique(rate_ratios$sex), spec$sexes)
  if (length(bad_sex) > 0) {
    stop(
      "`rate_ratios` includes sex `", bad_sex[[1]],
      "`, which is not in `spec$sexes`.",
      call. = FALSE
    )
  }
  bad_age <- setdiff(as.character(unique(rate_ratios$age)), as.character(spec$ages$age_start))
  if (length(bad_age) > 0) {
    stop(
      "`rate_ratios` includes age `", bad_age[[1]],
      "`, which is not in `spec$ages$age_start`.",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

find_stratum_rate_targets <- function(data) {
  column_map <- stratum_rate_ratio_column_map()
  out <- list()
  for (parameter in names(column_map)) {
    present <- intersect(column_map[[parameter]], names(data))
    for (column in present) {
      out[[length(out) + 1L]] <- list(parameter = parameter, column = column)
    }
  }
  out
}

normalise_equity_age_column <- function(data, label) {
  if (!"age" %in% names(data) && "age_start" %in% names(data)) {
    names(data)[names(data) == "age_start"] <- "age"
  }
  if (!"age" %in% names(data)) {
    stop("`", label, "` must contain `age` or `age_start`.", call. = FALSE)
  }
  data
}

validate_equity_integer <- function(x, column, label) {
  value <- suppressWarnings(as.numeric(x))
  if (any(is.na(value)) || any(abs(value - round(value)) > .Machine$double.eps^0.5)) {
    stop("`", column, "` in ", label, " must contain whole numbers.", call. = FALSE)
  }
  as.integer(value)
}

expand_aggregate_rates_to_target_keys <- function(data, target_keys, label) {
  target_keys <- normalise_equity_age_column(target_keys, "target_keys")
  require_columns(target_keys, c("age", "sex", "stratum"), "target_keys")
  target_keys <- unique(target_keys[c("age", "sex", "stratum")])
  target_keys$age <- validate_equity_integer(target_keys$age, "age", "target_keys")
  target_keys$sex <- as.character(target_keys$sex)
  target_keys$stratum <- as.character(target_keys$stratum)

  data <- normalise_equity_age_column(data, label)
  require_columns(data, c("age", "sex"), label)
  data$age <- validate_equity_integer(data$age, "age", label)
  data$sex <- as.character(data$sex)
  if ("stratum" %in% names(data)) {
    data$stratum <- as.character(data$stratum)
    data_keys <- unique(data[c("age", "sex", "stratum")])
    if (all(equity_key_in(target_keys, data_keys, c("age", "sex", "stratum"))) &&
        all(equity_key_in(data_keys, target_keys, c("age", "sex", "stratum")))) {
      return(data)
    }
  }

  grouping <- intersect(c("time_step", "age", "sex", "disease"), names(data))
  value_cols <- setdiff(names(data), "stratum")
  collapsed <- data[value_cols]
  duplicated_group <- duplicated(collapsed[grouping])
  if (any(duplicated_group)) {
    first <- collapsed[which(duplicated_group)[[1]], grouping, drop = FALSE]
    stop(
      "`", label, "` must have one aggregate row per age and sex",
      if ("time_step" %in% grouping) " and time_step" else "",
      " before stratum disaggregation. First duplicate group: ",
      format_equity_key(first),
      ".",
      call. = FALSE
    )
  }

  out <- merge(
    target_keys,
    collapsed,
    by = intersect(c("age", "sex"), names(collapsed)),
    all.x = TRUE,
    sort = FALSE
  )
  missing_rate <- !stats::complete.cases(out[setdiff(grouping, "time_step")])
  if (any(missing_rate)) {
    stop("`", label, "` is missing aggregate rows needed for stratum disaggregation.", call. = FALSE)
  }
  out
}

apply_one_stratum_rate_ratio <- function(data, ratios, parameter, value_col, label) {
  needed <- unique(data[c("age", "sex", "stratum")])
  needed$parameter <- parameter
  missing <- needed[!equity_key_in(needed, ratios, c("age", "sex", "stratum", "parameter")), , drop = FALSE]
  if (nrow(missing) > 0) {
    first <- missing[1, , drop = FALSE]
    stop(
      "`rate_ratios` is missing a row needed to disaggregate `", value_col, "`. ",
      "First missing key: age=", first$age[[1]],
      ", sex=", first$sex[[1]],
      ", stratum=", first$stratum[[1]],
      ", parameter=", parameter, ".",
      call. = FALSE
    )
  }

  data$.pmslt_row_id <- seq_len(nrow(data))
  selected <- ratios[ratios$parameter == parameter, c(
    "age", "sex", "stratum", "parameter", "rate_ratio", "reference_stratum"
  )]
  out <- merge(
    data,
    selected,
    by = c("age", "sex", "stratum"),
    all.x = TRUE,
    sort = FALSE
  )
  original_col <- paste0(value_col, "_original_aggregate")
  ratio_col <- paste0(value_col, "_rate_ratio")
  parameter_col <- paste0(value_col, "_rate_ratio_parameter")
  reference_col <- paste0(value_col, "_reference_stratum")
  out[[original_col]] <- suppressWarnings(as.numeric(out[[value_col]]))
  out[[ratio_col]] <- out$rate_ratio
  out[[parameter_col]] <- out$parameter
  out[[reference_col]] <- out$reference_stratum
  out[[value_col]] <- out[[original_col]] * out[[ratio_col]]
  out$parameter <- NULL
  out$rate_ratio <- NULL
  out$reference_stratum <- NULL
  out <- out[order(out$.pmslt_row_id), , drop = FALSE]
  out$.pmslt_row_id <- NULL
  row.names(out) <- NULL
  out
}

equity_key_in <- function(left, right, keys) {
  do.call(paste, c(left[keys], sep = "\r")) %in%
    do.call(paste, c(right[keys], sep = "\r"))
}

format_equity_key <- function(data) {
  paste(
    paste(names(data), unlist(data[1, , drop = TRUE], use.names = FALSE), sep = "="),
    collapse = ", "
  )
}
