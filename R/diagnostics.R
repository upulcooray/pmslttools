#' Diagnose missing disease parameters
#'
#' Explains the minimum epidemiological parameters needed before DisMod
#' processing. This function is intentionally plain-language because it is aimed
#' at users who are new to simulation modelling.
#'
#' @param raw_disease_data Optional data frame containing disease rows and
#'   epidemiological parameter columns.
#' @param spec A `pmslt_spec` object.
#'
#' @return A data frame with one row per disease and plain-language guidance.
#' @export
diagnose_missing_parameters <- function(raw_disease_data = NULL, spec) {
  validate_spec(spec)

  required_cols <- c(
    "incidence_rate",
    "prevalence",
    "remission_rate",
    "excess_mortality_rate",
    "case_fatality_rate"
  )

  if (is.null(raw_disease_data)) {
    return(data.frame(
      disease = spec$diseases,
      supplied_parameters = 0L,
      dismod_ready = FALSE,
      message = paste(
        "No raw disease data supplied yet.",
        "Collect at least 3 of incidence, prevalence, remission,",
        "excess mortality, and case fatality for DisMod processing.",
        "For chronic non-remitting diseases, remission can usually be set to 0."
      ),
      stringsAsFactors = FALSE
    ))
  }

  missing_cols <- setdiff(c("disease", required_cols), names(raw_disease_data))
  if (length(missing_cols) > 0) {
    stop(
      "`raw_disease_data` is missing: ",
      paste(missing_cols, collapse = ", "),
      call. = FALSE
    )
  }

  rows <- lapply(spec$diseases, function(disease_name) {
    disease_rows <- raw_disease_data[raw_disease_data$disease == disease_name, , drop = FALSE]
    present <- vapply(
      required_cols,
      function(col) any(!is.na(disease_rows[[col]])),
      logical(1)
    )
    n_present <- sum(present)
    dismod_ready <- n_present >= 3

    guidance <- if (dismod_ready) {
      paste(
        "Enough parameter types are present for a DisMod attempt.",
        "Still check age, sex, and stratum coverage before running DisMod."
      )
    } else {
      paste(
        "Not enough parameter types for DisMod.",
        "Add more epidemiological inputs or explicitly set remission to 0",
        "when the disease is non-remitting."
      )
    }

    data.frame(
      disease = disease_name,
      supplied_parameters = n_present,
      dismod_ready = dismod_ready,
      present_parameters = paste(names(present)[present], collapse = "; "),
      missing_parameters = paste(names(present)[!present], collapse = "; "),
      message = guidance,
      stringsAsFactors = FALSE
    )
  })

  do.call(rbind, rows)
}
