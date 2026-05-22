#' Get the next recommended PMSLT workflow step
#'
#' `next_pmslt_step()` gives beginner-friendly navigation through the
#' pmslttools workflow. It does not run modelling code, validate files, or
#' change any inputs.
#'
#' @param stage Optional workflow stage. Supported values are `"spec"`,
#'   `"templates"`, `"raw_inputs"`, `"raw_validation"`, `"dismod_lite"`,
#'   `"pmslt_disease_inputs"`, `"disease_lifetable"`, `"interventions"`, and
#'   `"halys"`.
#' @param object Optional pmslttools object used to infer the workflow stage
#'   when `stage` is not supplied. Inference is conservative and currently
#'   recognises `pmslt_spec`, `raw_input_readiness_check`, and
#'   `summarised_raw_input_issues` objects.
#'
#' @return A list with class `pmslt_next_step` containing `current_stage`,
#'   `next_step`, `recommended_function`, `why`, and `example`.
#' @export
#'
#' @examples
#' next_pmslt_step()
#' next_pmslt_step("raw_inputs")
#' \dontrun{
#' readiness <- check_raw_input_readiness(input_dir, spec)
#' next_pmslt_step(object = readiness)
#' }
next_pmslt_step <- function(stage = NULL, object = NULL) {
  if (!is.null(stage)) {
    current_stage <- normalise_next_step_stage(stage)
  } else if (!is.null(object)) {
    current_stage <- infer_next_step_stage(object)
  } else {
    current_stage <- "start"
  }

  out <- next_step_guidance(current_stage, object = object)
  class(out) <- "pmslt_next_step"
  out
}

#' @export
print.pmslt_next_step <- function(x, ...) {
  cat("PMSLT workflow guidance\n")
  cat("Current stage: ", x$current_stage, "\n", sep = "")
  cat("Next step: ", x$next_step, "\n", sep = "")
  cat("Recommended function: ", x$recommended_function, "\n", sep = "")
  cat("Why: ", x$why, "\n", sep = "")
  cat("Example: ", x$example, "\n", sep = "")
  invisible(x)
}

supported_next_step_stages <- function() {
  c(
    "spec",
    "templates",
    "raw_inputs",
    "raw_validation",
    "dismod_lite",
    "pmslt_disease_inputs",
    "disease_lifetable",
    "interventions",
    "halys"
  )
}

normalise_next_step_stage <- function(stage) {
  if (!is.character(stage) || length(stage) != 1 || is.na(stage)) {
    stop("`stage` must be a single workflow stage.", call. = FALSE)
  }

  stage <- tolower(trimws(stage))
  supported <- supported_next_step_stages()
  if (!stage %in% supported) {
    stop(
      "Unsupported PMSLT workflow stage: '",
      stage,
      "'. Supported stages are: ",
      paste(supported, collapse = ", "),
      ".",
      call. = FALSE
    )
  }

  stage
}

infer_next_step_stage <- function(object) {
  if (inherits(object, "raw_input_readiness_check") ||
      inherits(object, "summarised_raw_input_issues")) {
    return("raw_validation")
  }
  if (inherits(object, "pmslt_spec")) {
    return("spec")
  }

  "start"
}

next_step_guidance <- function(stage, object = NULL) {
  if (stage == "start") {
    return(new_next_step(
      current_stage = "start",
      next_step = "Define the model structure you want to build.",
      recommended_function = "pmslt_spec",
      why = "pmslttools starts by turning the intervention, diseases, ages, sexes, strata, and time horizon into a reusable project specification.",
      example = 'spec <- pmslt_spec(intervention = "Tobacco tax", mechanism = "direct", diseases = "CHD")'
    ))
  }

  if (stage == "spec") {
    return(new_next_step(
      current_stage = "spec",
      next_step = "Draft the raw CSV input templates from the specification.",
      recommended_function = "draft_input_templates",
      why = "Templates turn the model specification into the files a beginner needs to fill before validation and DisMod-style processing.",
      example = 'draft_input_templates(spec, output_dir = "inputs_raw")'
    ))
  }

  if (stage == "templates") {
    return(new_next_step(
      current_stage = "templates",
      next_step = "Fill the generated CSV templates, then check raw input readiness.",
      recommended_function = "check_raw_input_readiness",
      why = "The generated templates are only a scaffold until the blank required fields have been filled and checked.",
      example = 'readiness <- check_raw_input_readiness("inputs_raw", spec)'
    ))
  }

  if (stage == "raw_inputs") {
    return(new_next_step(
      current_stage = "raw_inputs",
      next_step = "Run the one-step raw input readiness check.",
      recommended_function = "check_raw_input_readiness",
      why = "Readiness checking validates the completed CSV files and gives a can-proceed signal before DisMod-lite or PMSLT-ready input preparation.",
      example = 'readiness <- check_raw_input_readiness("inputs_raw", spec)'
    ))
  }

  if (stage == "raw_validation") {
    return(raw_validation_next_step(object))
  }

  if (stage == "dismod_lite") {
    return(new_next_step(
      current_stage = "dismod_lite",
      next_step = "Prepare the canonical PMSLT disease input file.",
      recommended_function = "prepare_pmslt_disease_inputs",
      why = "Downstream disease lifetable helpers expect a PMSLT-ready disease table with exact integer ages.",
      example = 'prepare_pmslt_disease_inputs("inputs_raw/mock_dismod_output")'
    ))
  }

  if (stage == "pmslt_disease_inputs") {
    return(new_next_step(
      current_stage = "pmslt_disease_inputs",
      next_step = "Validate or read the PMSLT disease inputs, then run the disease lifetable.",
      recommended_function = "read_pmslt_disease_inputs",
      why = "The disease lifetable should use the checked post-DisMod `pmslt_disease_epi.csv` file, not the raw age-banded disease template.",
      example = 'disease_epi <- read_pmslt_disease_inputs("pmslt_disease_epi.csv")'
    ))
  }

  if (stage == "disease_lifetable") {
    return(new_next_step(
      current_stage = "disease_lifetable",
      next_step = "Run intervention workflows or integrate disease deltas with the all-cause lifetable where appropriate.",
      recommended_function = "run_pmslt_interventions",
      why = "After disease lifetable outputs exist, the next modelling question is usually how intervention scenarios change those outputs.",
      example = 'results <- run_pmslt_interventions(disease_epi = "pmslt_disease_epi.csv")'
    ))
  }

  if (stage == "interventions") {
    return(new_next_step(
      current_stage = "interventions",
      next_step = "Compare HALY-style health outcomes across compatible outputs.",
      recommended_function = "compare_halys",
      why = "Intervention outputs are easier to interpret when summarised as differences in HALYs, person-years, and YLDs.",
      example = "compare_halys(bau_result, intervention_result)"
    ))
  }

  if (stage == "halys") {
    return(new_next_step(
      current_stage = "halys",
      next_step = "Review outputs and decide whether later uncertainty, equity, or cost extensions are needed.",
      recommended_function = "calculate_halys",
      why = "HALY summaries are a reporting layer; uncertainty, equity, and cost extensions should be considered after the deterministic workflow is understood.",
      example = 'calculate_halys(result, by = "age_band")'
    ))
  }

  stop("Internal error: unsupported stage after validation.", call. = FALSE)
}

raw_validation_next_step <- function(object) {
  can_proceed <- NULL
  if (inherits(object, "raw_input_readiness_check")) {
    can_proceed <- isTRUE(object$can_proceed)
  } else if (inherits(object, "summarised_raw_input_issues")) {
    can_proceed <- isTRUE(object$can_proceed)
  }

  if (identical(can_proceed, FALSE)) {
    return(new_next_step(
      current_stage = "raw_validation",
      next_step = "Inspect the validation issues and fix errors before proceeding.",
      recommended_function = "check_raw_input_readiness",
      why = "Raw validation found blocking issues. DisMod-lite and PMSLT-ready input preparation should wait until `can_proceed` is TRUE.",
      example = "readiness$issues"
    ))
  }

  if (identical(can_proceed, TRUE)) {
    return(new_next_step(
      current_stage = "raw_validation",
      next_step = "Proceed to DisMod-lite or PMSLT-ready disease input preparation.",
      recommended_function = "dismod_slove",
      why = "The raw input readiness check indicates that no blocking raw input errors remain.",
      example = 'dismod_slove("inputs_raw")'
    ))
  }

  new_next_step(
    current_stage = "raw_validation",
    next_step = "Proceed only if `can_proceed` is TRUE; otherwise inspect and fix the issues.",
    recommended_function = "check_raw_input_readiness",
    why = "Raw validation is the gate between filled CSV templates and downstream disease processing.",
    example = "if (readiness$can_proceed) dismod_slove(\"inputs_raw\") else readiness$issues"
  )
}

new_next_step <- function(current_stage,
                          next_step,
                          recommended_function,
                          why,
                          example) {
  list(
    current_stage = current_stage,
    next_step = next_step,
    recommended_function = recommended_function,
    why = why,
    example = example
  )
}
