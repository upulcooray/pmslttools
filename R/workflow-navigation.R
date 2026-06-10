#' Get the next recommended PMSLT workflow step
#'
#' `next_pmslt_step()` gives beginner-friendly navigation through the
#' pmslttools workflow. It does not run modelling code, validate files, or
#' change any inputs.
#'
#' @param stage Optional workflow stage. Supported values are `"spec"`,
#'   `"templates"`, `"raw_inputs"`, `"raw_validation"`, `"disease_consistency"`,
#'   `"interventions"`, `"lifetable"`, `"summaries"`, and `"reporting"`.
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
    "disease_consistency",
    "interventions",
    "lifetable",
    "summaries",
    "reporting"
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
      why = "Readiness checking validates the completed CSV files and gives a can-proceed signal before disease consistency solving.",
      example = 'readiness <- check_raw_input_readiness("inputs_raw", spec)'
    ))
  }

  if (stage == "raw_validation") {
    return(raw_validation_next_step(object))
  }

  if (stage == "disease_consistency") {
    return(new_next_step(
      current_stage = "disease_consistency",
      next_step = "Use the canonical disease input file in the intervention workflow.",
      recommended_function = "run_pmslt_interventions",
      why = "The disease consistency step writes exact-age `pmslt_disease_epi.csv`; downstream intervention functions should consume that file instead of raw age-banded disease templates.",
      example = 'results <- run_pmslt_interventions(disease_epi = "inputs_raw/disease_consistency_results/pmslt_disease_epi.csv")'
    ))
  }

  if (stage == "interventions") {
    return(new_next_step(
      current_stage = "interventions",
      next_step = "Bridge intervention disease effects into comparable BAU and intervention all-cause lifetables.",
      recommended_function = "run_pmslt_lifetable_interventions",
      why = "The disease intervention runner produces disease-level mortality and morbidity deltas; the main lifetable bridge applies those deltas to all-cause outcomes before summaries.",
      example = "lifetables <- run_pmslt_lifetable_interventions(population, mortality, morbidity, intervention_effects = results, horizon = spec$horizon, spec = spec)"
    ))
  }

  if (stage == "lifetable") {
    return(new_next_step(
      current_stage = "lifetable",
      next_step = "Summarise compatible lifetable outputs.",
      recommended_function = "summarise_pmslt_results",
      why = "Summaries are the implemented reporting layer for BAU all-cause outputs, attached disease deltas, and intervention lifetables returned by the bridge.",
      example = 'summarise_pmslt_results(lifetables$interventions[[1]], by = "age_band")'
    ))
  }

  if (stage == "summaries") {
    return(new_next_step(
      current_stage = "summaries",
      next_step = "Review deterministic health outputs, then add cost and ICER reporting only when those outputs exist.",
      recommended_function = "calculate_halys",
      why = "HALY helpers are implemented as a reporting layer over existing lifetable outputs; cost and ICER helpers summarise deterministic outputs without changing the engine.",
      example = 'calculate_halys(result, by = "age_band")'
    ))
  }

  if (stage == "reporting") {
    return(new_next_step(
      current_stage = "reporting",
      next_step = "Use deterministic summaries as the stable handoff for later uncertainty or presentation outputs.",
      recommended_function = "calculate_icers",
      why = "ICERs are calculated only after incremental costs and incremental HALYs already exist, using the intervention-minus-BAU convention.",
      example = 'calculate_icers(incremental_results, incremental_cost = "total_cost_difference")'
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
      why = "Raw validation found blocking issues. Disease consistency solving and PMSLT-ready input preparation should wait until `can_proceed` is TRUE.",
      example = "readiness$issues"
    ))
  }

  if (identical(can_proceed, TRUE)) {
    return(new_next_step(
      current_stage = "raw_validation",
      next_step = "Proceed to disease consistency solving and write PMSLT-ready disease inputs.",
      recommended_function = "solve_disease_consistency",
      why = "The raw input readiness check indicates that no blocking raw input errors remain.",
      example = 'solve_disease_consistency("inputs_raw", solver = "dismod_slove")'
    ))
  }

  new_next_step(
    current_stage = "raw_validation",
    next_step = "Proceed only if `can_proceed` is TRUE; otherwise inspect and fix the issues.",
    recommended_function = "check_raw_input_readiness",
    why = "Raw validation is the gate between filled CSV templates and downstream disease processing.",
    example = "if (readiness$can_proceed) solve_disease_consistency(\"inputs_raw\") else readiness$issues"
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
