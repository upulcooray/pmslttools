#' Create a PMSLT model specification
#'
#' `pmslt_spec()` captures the minimum information needed to design
#' project-specific data collection templates for a PMSLT simulation.
#'
#' @param intervention Short description of the intervention.
#' @param intervention_arms Character vector of intervention arms. Defaults to
#'   `intervention`. Use this for multiple intervention scenarios.
#' @param mechanism One of `"risk_factor"`, `"direct"`, or `"both"`.
#' @param diseases Character vector of diseases modelled.
#' @param risk_factors Character vector of risk factors. Required when
#'   `mechanism` is `"risk_factor"` or `"both"`.
#' @param risk_categories Risk-factor exposure categories. Use a named list,
#'   for example `list(Smoking = c("Never", "Current", "Former"))`. If the
#'   model has one risk factor, a plain character vector is also accepted.
#' @param ages Data frame returned by [age_bands()], or any data frame with
#'   `age_start` and `age_end` columns.
#' @param sexes Character vector of sex labels.
#' @param strata Character vector of population strata.
#' @param horizon Number of annual simulation cycles.
#' @param base_year Base year for the model.
#' @param timestep Length of each model cycle in years.
#' @param cost_effectiveness Logical. Should cost input templates be generated?
#'
#' @return An object of class `pmslt_spec`.
#' @export
pmslt_spec <- function(intervention,
                       mechanism = c("risk_factor", "direct", "both"),
                       diseases,
                       risk_factors = character(),
                       risk_categories = NULL,
                       intervention_arms = NULL,
                       ages = age_bands(0, 100, by = 5),
                       sexes = c("male", "female"),
                       strata = "total",
                       horizon = 80,
                       base_year = NA_integer_,
                       timestep = 1,
                       cost_effectiveness = FALSE) {
  mechanism <- match.arg(mechanism)

  risk_factors <- unique(as.character(risk_factors))
  spec <- list(
    intervention = intervention,
    intervention_arms = validate_intervention_arms(intervention_arms, intervention),
    mechanism = mechanism,
    diseases = unique_nonempty_character(diseases, "diseases"),
    risk_factors = risk_factors,
    risk_categories = validate_risk_categories(risk_categories, risk_factors, mechanism),
    ages = validate_age_table(ages),
    sexes = unique_nonempty_character(sexes, "sexes"),
    strata = unique_nonempty_character(strata, "strata"),
    horizon = validate_positive_integer(horizon, "horizon"),
    base_year = base_year,
    timestep = validate_positive_number(timestep, "timestep"),
    cost_effectiveness = isTRUE(cost_effectiveness)
  )

  class(spec) <- "pmslt_spec"
  validate_spec(spec)
  spec
}

#' Create age bands
#'
#' @param min Minimum age.
#' @param max Maximum age.
#' @param by Age-band width.
#' @param open_ended Logical. Should the final age band be open ended?
#'
#' @return A data frame with `age_start`, `age_end`, and `age_label`.
#' @export
age_bands <- function(min = 0, max = 100, by = 5, open_ended = TRUE) {
  min <- validate_nonnegative_number(min, "min")
  max <- validate_positive_number(max, "max")
  by <- validate_positive_number(by, "by")

  if (max <= min) {
    stop("`max` must be greater than `min`.", call. = FALSE)
  }

  starts <- seq(min, max, by = by)
  ends <- starts + by - 1

  if (open_ended) {
    ends[length(ends)] <- Inf
  } else {
    ends[length(ends)] <- max
  }

  labels <- ifelse(
    is.infinite(ends),
    paste0(starts, "+"),
    paste0(starts, "-", ends)
  )

  data.frame(
    age_start = starts,
    age_end = ends,
    age_label = labels,
    stringsAsFactors = FALSE
  )
}

#' Validate a PMSLT model specification
#'
#' @param spec A `pmslt_spec` object.
#'
#' @return Invisibly returns `TRUE` if valid.
#' @export
validate_spec <- function(spec) {
  if (!inherits(spec, "pmslt_spec")) {
    stop("`spec` must be created with `pmslt_spec()`.", call. = FALSE)
  }

  if (spec$mechanism %in% c("risk_factor", "both") &&
      length(spec$risk_factors) == 0) {
    stop(
      "`risk_factors` must be supplied for risk-factor-mediated models.",
      call. = FALSE
    )
  }

  if (spec$mechanism %in% c("risk_factor", "both") &&
      length(spec$risk_categories) == 0) {
    stop(
      "`risk_categories` must be supplied for risk-factor-mediated models.",
      call. = FALSE
    )
  }

  if (!all(c("age_start", "age_end", "age_label") %in% names(spec$ages))) {
    stop("`ages` must contain age_start, age_end, and age_label.", call. = FALSE)
  }

  invisible(TRUE)
}

#' @export
print.pmslt_spec <- function(x, ...) {
  cat("PMSLT model specification\n")
  cat("Intervention: ", x$intervention, "\n", sep = "")
  cat("Intervention arms: ", paste(x$intervention_arms, collapse = ", "), "\n", sep = "")
  cat("Mechanism: ", x$mechanism, "\n", sep = "")
  cat("Diseases: ", paste(x$diseases, collapse = ", "), "\n", sep = "")
  if (length(x$risk_factors) > 0) {
    cat("Risk factors: ", paste(x$risk_factors, collapse = ", "), "\n", sep = "")
    cat(
      "Risk categories: ",
      paste(
        vapply(
          names(x$risk_categories),
          function(rf) paste0(rf, " = ", paste(x$risk_categories[[rf]], collapse = ", ")),
          character(1)
        ),
        collapse = "; "
      ),
      "\n",
      sep = ""
    )
  }
  cat("Ages: ", x$ages$age_label[1], " to ", x$ages$age_label[nrow(x$ages)], "\n", sep = "")
  cat("Sexes: ", paste(x$sexes, collapse = ", "), "\n", sep = "")
  cat("Strata: ", paste(x$strata, collapse = ", "), "\n", sep = "")
  cat("Horizon: ", x$horizon, " cycles\n", sep = "")
  invisible(x)
}

unique_nonempty_character <- function(x, name) {
  x <- unique(as.character(x))
  x <- x[!is.na(x) & nzchar(x)]
  if (length(x) == 0) {
    stop("`", name, "` must contain at least one non-empty value.", call. = FALSE)
  }
  x
}

validate_age_table <- function(x) {
  if (!is.data.frame(x)) {
    stop("`ages` must be a data frame.", call. = FALSE)
  }
  required <- c("age_start", "age_end")
  missing <- setdiff(required, names(x))
  if (length(missing) > 0) {
    stop("`ages` is missing: ", paste(missing, collapse = ", "), call. = FALSE)
  }
  if (!"age_label" %in% names(x)) {
    x$age_label <- ifelse(
      is.infinite(x$age_end),
      paste0(x$age_start, "+"),
      paste0(x$age_start, "-", x$age_end)
    )
  }
  x[, c("age_start", "age_end", "age_label")]
}

validate_risk_categories <- function(risk_categories, risk_factors, mechanism) {
  if (!mechanism %in% c("risk_factor", "both")) {
    return(list())
  }

  if (length(risk_factors) == 0) {
    return(list())
  }

  if (is.null(risk_categories)) {
    return(list())
  }

  if (is.character(risk_categories)) {
    if (length(risk_factors) != 1) {
      stop(
        "`risk_categories` must be a named list when more than one risk factor is supplied.",
        call. = FALSE
      )
    }
    risk_categories <- stats::setNames(list(risk_categories), risk_factors)
  }

  if (!is.list(risk_categories) || is.null(names(risk_categories))) {
    stop(
      "`risk_categories` must be a named list, for example list(Smoking = c('Never', 'Current')).",
      call. = FALSE
    )
  }

  missing_names <- setdiff(risk_factors, names(risk_categories))
  if (length(missing_names) > 0) {
    stop(
      "`risk_categories` is missing categories for: ",
      paste(missing_names, collapse = ", "),
      call. = FALSE
    )
  }

  extra_names <- setdiff(names(risk_categories), risk_factors)
  if (length(extra_names) > 0) {
    stop(
      "`risk_categories` includes names that are not in `risk_factors`: ",
      paste(extra_names, collapse = ", "),
      call. = FALSE
    )
  }

  risk_categories <- risk_categories[risk_factors]
  lapply(names(risk_categories), function(risk_factor) {
    unique_nonempty_character(risk_categories[[risk_factor]], paste0("risk_categories$", risk_factor))
  }) |>
    stats::setNames(risk_factors)
}

validate_intervention_arms <- function(intervention_arms, intervention) {
  if (is.null(intervention_arms)) {
    intervention_arms <- intervention
  }
  unique_nonempty_character(intervention_arms, "intervention_arms")
}

validate_positive_integer <- function(x, name) {
  value <- validate_positive_number(x, name)
  if (value != as.integer(value)) {
    stop("`", name, "` must be a whole number.", call. = FALSE)
  }
  as.integer(value)
}

validate_positive_number <- function(x, name) {
  if (length(x) != 1 || is.na(x) || !is.numeric(x) || x <= 0) {
    stop("`", name, "` must be a positive number.", call. = FALSE)
  }
  x
}

validate_nonnegative_number <- function(x, name) {
  if (length(x) != 1 || is.na(x) || !is.numeric(x) || x < 0) {
    stop("`", name, "` must be a non-negative number.", call. = FALSE)
  }
  x
}
