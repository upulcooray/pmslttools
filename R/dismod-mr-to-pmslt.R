#' Convert DisMod-MR outputs to PMSLT disease inputs
#'
#' Bridges validated external DisMod-MR long-format model outputs into the
#' canonical `pmslt_disease_epi.csv` structure used by downstream PMSLT disease
#' modules. DisMod-MR supplies modelled disease rates; `disability_weight` is
#' joined from raw disease epidemiology evidence.
#'
#' @param dismod_outputs DisMod-MR outputs as a data frame, a CSV path, or a
#'   `dismod_mr_outputs` object returned by [read_dismod_mr_outputs()].
#' @param raw_disease_inputs Raw disease epidemiology evidence as a data frame
#'   or a path to `05_disease_epidemiology_raw.csv`. It must contain
#'   `disease`, `age_start`, `age_end`, `sex`, `stratum`, and
#'   `disability_weight`.
#' @param output_path Optional CSV path to write the PMSLT-ready disease inputs.
#' @param validate Logical. Should the converted table be checked with
#'   [validate_pmslt_disease_inputs()]? DisMod-MR output validation is always
#'   performed before conversion.
#' @param overwrite Logical. Should `output_path` be replaced if it already
#'   exists?
#'
#' @return A data frame with class `pmslt_disease_inputs_from_dismod_mr`.
#'   Attributes store the DisMod-MR validation object, a source summary, and the
#'   output path when written.
#' @export
#'
#' @examples
#' \dontrun{
#' modelled <- read_dismod_mr_outputs(
#'   "path/to/dismod_mr_results.csv",
#'   target_grid = "path/to/dismod_mr_inputs/dismod_mr_target_grid.csv"
#' )
#' disease_inputs <- prepare_pmslt_disease_inputs_from_dismod_mr(
#'   modelled,
#'   raw_disease_inputs = "path/to/raw_inputs/05_disease_epidemiology_raw.csv",
#'   output_path = "path/to/raw_inputs/pmslt_disease_epi.csv"
#' )
#' }
prepare_pmslt_disease_inputs_from_dismod_mr <- function(dismod_outputs,
                                                        raw_disease_inputs,
                                                        output_path = NULL,
                                                        validate = TRUE,
                                                        overwrite = FALSE) {
  dismod <- dismod_mr_bridge_outputs(dismod_outputs)
  raw <- dismod_mr_bridge_raw_disease_inputs(raw_disease_inputs)

  out <- dismod_mr_bridge_widen_outputs(dismod$outputs)
  out <- dismod_mr_bridge_join_disability_weight(out, raw)
  out <- dismod_mr_bridge_add_schema_columns(out)
  out <- out[order(out$disease, out$sex, out$stratum, out$age), , drop = FALSE]
  row.names(out) <- NULL

  validation_passed <- NA
  if (isTRUE(validate)) {
    validate_pmslt_disease_inputs(out)
    validation_passed <- TRUE
  } else {
    validation_passed <- FALSE
  }

  if (!is.null(output_path)) {
    if (!is.character(output_path) || length(output_path) != 1 || is.na(output_path) || !nzchar(output_path)) {
      stop("`output_path` must be NULL or a single CSV file path.", call. = FALSE)
    }
    if (file.exists(output_path) && !isTRUE(overwrite)) {
      stop("File already exists: ", output_path, ". Use `overwrite = TRUE` to replace it.", call. = FALSE)
    }
    output_dir <- dirname(output_path)
    if (!dir.exists(output_dir)) {
      dir.create(output_dir, recursive = TRUE)
    }
    utils::write.csv(out, output_path, row.names = FALSE, na = "")
  }

  attr(out, "validation") <- dismod$validation
  attr(out, "pmslt_validation_passed") <- validation_passed
  attr(out, "source_summary") <- dismod_mr_bridge_source_summary(out, dismod$outputs)
  attr(out, "output_path") <- output_path
  class(out) <- c("pmslt_disease_inputs_from_dismod_mr", class(out))
  out
}

#' @export
print.pmslt_disease_inputs_from_dismod_mr <- function(x, ...) {
  cat("PMSLT disease inputs from DisMod-MR\n")
  cat("Rows: ", nrow(x), "\n", sep = "")
  cat("Diseases: ", length(unique(stats::na.omit(x$disease))), "\n", sep = "")
  cat("Ages: ", length(unique(stats::na.omit(x$age))), "\n", sep = "")
  cat("Sexes: ", length(unique(stats::na.omit(x$sex))), "\n", sep = "")
  cat("Strata: ", length(unique(stats::na.omit(x$stratum))), "\n", sep = "")
  validation_passed <- attr(x, "pmslt_validation_passed")
  validation_text <- if (isTRUE(validation_passed)) {
    "yes"
  } else if (identical(validation_passed, FALSE)) {
    "not run"
  } else {
    "unknown"
  }
  cat("Canonical PMSLT validation passed: ", validation_text, "\n", sep = "")
  output_path <- attr(x, "output_path") %||% "<not written>"
  cat("Output path: ", output_path, "\n", sep = "")
  invisible(x)
}

dismod_mr_bridge_parameter_map <- function() {
  c(
    incidence = "incidence_BAU",
    prevalence = "prevalence_initial",
    remission = "remission_rate",
    excess_mortality = "excess_mortality_BAU",
    case_fatality = "case_fatality_BAU"
  )
}

dismod_mr_bridge_outputs <- function(dismod_outputs) {
  if (inherits(dismod_outputs, "dismod_mr_outputs")) {
    if (!isTRUE(dismod_outputs$validation$is_valid)) {
      stop("DisMod-MR outputs failed validation before PMSLT conversion.", call. = FALSE)
    }
    validation <- validate_dismod_mr_outputs(dismod_outputs)
    return(list(
      outputs = dismod_mr_clean_outputs(dismod_outputs$outputs),
      validation = validation
    ))
  }

  if (is.character(dismod_outputs) && length(dismod_outputs) == 1 && !is.na(dismod_outputs)) {
    modelled <- read_dismod_mr_outputs(dismod_outputs)
    return(list(
      outputs = modelled$outputs,
      validation = modelled$validation
    ))
  }

  if (is.data.frame(dismod_outputs)) {
    validation <- validate_dismod_mr_outputs(dismod_outputs)
    return(list(
      outputs = dismod_mr_clean_outputs(dismod_outputs),
      validation = validation
    ))
  }

  stop("`dismod_outputs` must be a data frame, a CSV path, or a `dismod_mr_outputs` object.", call. = FALSE)
}

dismod_mr_bridge_raw_disease_inputs <- function(raw_disease_inputs) {
  if (is.character(raw_disease_inputs) && length(raw_disease_inputs) == 1 && !is.na(raw_disease_inputs)) {
    if (!file.exists(raw_disease_inputs)) {
      stop("Raw disease input file does not exist: ", raw_disease_inputs, call. = FALSE)
    }
    raw_disease_inputs <- utils::read.csv(raw_disease_inputs, stringsAsFactors = FALSE, na.strings = c("", "NA"))
  }
  if (!is.data.frame(raw_disease_inputs)) {
    stop("`raw_disease_inputs` must be a data frame or a path to `05_disease_epidemiology_raw.csv`.", call. = FALSE)
  }

  required <- c("disease", "age_start", "age_end", "sex", "stratum", "disability_weight")
  require_columns(raw_disease_inputs, required, "raw_disease_inputs")
  raw <- as.data.frame(raw_disease_inputs, stringsAsFactors = FALSE)
  for (column in c("disease", "sex", "stratum")) {
    raw[[column]] <- as.character(raw[[column]])
  }
  for (column in c("age_start", "age_end", "disability_weight")) {
    raw[[column]] <- suppressWarnings(as.numeric(raw[[column]]))
  }
  raw
}

dismod_mr_bridge_widen_outputs <- function(outputs) {
  required_parameters <- names(dismod_mr_bridge_parameter_map())
  key_cols <- c("disease", "age", "sex", "stratum")
  keys <- unique(outputs[key_cols])
  rows <- vector("list", nrow(keys))

  for (i in seq_len(nrow(keys))) {
    key <- keys[i, , drop = FALSE]
    subset <- outputs[
      outputs$disease == key$disease[[1]] &
        outputs$age == key$age[[1]] &
        outputs$sex == key$sex[[1]] &
        outputs$stratum == key$stratum[[1]],
      ,
      drop = FALSE
    ]
    missing_parameters <- setdiff(required_parameters, subset$parameter)
    if (length(missing_parameters) > 0) {
      stop(
        "Cannot convert DisMod-MR outputs for disease `", key$disease[[1]],
        "`, age ", key$age[[1]], ", sex `", key$sex[[1]],
        "`, stratum `", key$stratum[[1]], "` because required parameter(s) are missing: ",
        paste(missing_parameters, collapse = ", "), ".",
        call. = FALSE
      )
    }

    row <- data.frame(
      age = as.integer(key$age[[1]]),
      sex = key$sex[[1]],
      stratum = key$stratum[[1]],
      disease = key$disease[[1]],
      time_step = 0L,
      stringsAsFactors = FALSE
    )
    map <- dismod_mr_bridge_parameter_map()
    for (parameter in names(map)) {
      value <- subset$mean_value[subset$parameter == parameter][[1]]
      row[[unname(map[[parameter]])]] <- as.numeric(value)
    }
    if (all(c("lower_95", "upper_95") %in% names(subset))) {
      for (parameter in names(map)) {
        parameter_row <- subset[subset$parameter == parameter, , drop = FALSE]
        base <- unname(map[[parameter]])
        row[[paste0(base, "_lower_95")]] <- as.numeric(parameter_row$lower_95[[1]])
        row[[paste0(base, "_upper_95")]] <- as.numeric(parameter_row$upper_95[[1]])
      }
    }
    rows[[i]] <- row
  }

  dismod_mr_bind_rows(rows)
}

dismod_mr_bridge_join_disability_weight <- function(out, raw) {
  out$disability_weight <- NA_real_
  for (i in seq_len(nrow(out))) {
    matches <- raw[
      raw$disease == out$disease[[i]] &
        raw$sex == out$sex[[i]] &
        raw$stratum == out$stratum[[i]] &
        !is.na(raw$age_start) &
        !is.na(raw$age_end) &
        raw$age_start <= out$age[[i]] &
        raw$age_end >= out$age[[i]],
      ,
      drop = FALSE
    ]
    key_message <- paste0(
      "disease `", out$disease[[i]], "`, age ", out$age[[i]],
      ", sex `", out$sex[[i]], "`, stratum `", out$stratum[[i]], "`"
    )
    if (nrow(matches) == 0) {
      stop(
        "Cannot join disability_weight for ", key_message,
        " because no matching raw disease row was found.",
        call. = FALSE
      )
    }
    if (nrow(matches) > 1) {
      stop(
        "Cannot join disability_weight for ", key_message,
        " because multiple matching raw disease rows were found.",
        call. = FALSE
      )
    }
    disability_weight <- matches$disability_weight[[1]]
    if (is.na(disability_weight)) {
      stop(
        "Cannot join disability_weight for ", key_message,
        " because the matching raw disease row has missing or non-numeric disability_weight.",
        call. = FALSE
      )
    }
    out$disability_weight[[i]] <- disability_weight
  }
  out
}

dismod_mr_bridge_add_schema_columns <- function(out) {
  out$prevalence_BAU_reference <- out$prevalence_initial
  out$incidence_apc <- 0
  out$cfr_apc <- 0
  out$prevalence_apc <- 0
  out$input_source <- "external DisMod-MR bridge"

  schema_cols <- pmslt_disease_epi_schema()$columns$column
  provenance_cols <- setdiff(names(out), schema_cols)
  out[c(schema_cols, provenance_cols)]
}

dismod_mr_bridge_source_summary <- function(out, outputs) {
  data.frame(
    metric = c(
      "dismod_output_rows",
      "pmslt_rows",
      "diseases",
      "ages",
      "sexes",
      "strata"
    ),
    value = c(
      nrow(outputs),
      nrow(out),
      length(unique(stats::na.omit(out$disease))),
      length(unique(stats::na.omit(out$age))),
      length(unique(stats::na.omit(out$sex))),
      length(unique(stats::na.omit(out$stratum)))
    ),
    stringsAsFactors = FALSE
  )
}
