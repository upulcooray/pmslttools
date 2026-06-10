#' Run a complete PMSLT analysis from one call
#'
#' `run_pmslt()` is the end-to-end driver for the package. It chains the
#' individual workflow layers that are otherwise called separately:
#'
#' 1. Solve disease-parameter consistency with [solve_disease_consistency()]
#'    (or accept a pre-solved `disease_epi`).
#' 2. Translate raw intervention evidence into per-arm disease deltas with
#'    [run_pmslt_interventions()].
#' 3. Age the population through the all-cause main lifetable for business as
#'    usual and every intervention arm with [run_pmslt_lifetable_interventions()].
#' 4. Summarise health outcomes with [calculate_halys()] / [compare_halys()],
#'    attach costs with [attach_pmslt_costs()], and compute ICERs with
#'    [calculate_icers()].
#' 5. Optionally add an equity disaggregation overlay and a probabilistic
#'    sensitivity analysis.
#'
#' The function is deliberately beginner friendly: pointed at a directory created
#' by [draft_input_templates()], it reads the standard numbered CSV files and
#' runs the whole pipeline with sensible defaults. Each input can also be passed
#' explicitly as a data frame or path, which is the escape hatch for advanced or
#' rigorous use.
#'
#' @param input_dir Directory created by [draft_input_templates()] holding the
#'   numbered raw input CSVs. Used to locate any input not supplied explicitly.
#' @param spec Optional [pmslt_spec()] object. When supplied it validates labels
#'   and supplies the default `horizon`.
#' @param solver Disease-consistency solver. `"dismod_slove"` (default) runs
#'   without optional dependencies; `"disbayes"` runs the Bayesian solver and
#'   needs the optional `disbayes` package. Ignored when `disease_epi` is given.
#' @param horizon Simulation horizon in years. Defaults to the spec horizon, or
#'   is inferred by the solver.
#' @param disease_epi Optional pre-solved canonical disease inputs (data frame or
#'   path to `pmslt_disease_epi.csv`). When supplied the solver step is skipped.
#' @param population,mortality,morbidity All-cause main-lifetable inputs. Default
#'   to `01_population.csv`, `02_all_cause_mortality.csv`, and
#'   `03_all_cause_morbidity.csv` in `input_dir`. `population` and `mortality`
#'   are required; `morbidity` is optional.
#' @param risk_prevalence,relative_risks,direct_effects Intervention evidence.
#'   Default to `08_risk_factor_prevalence.csv`, `09_relative_risks.csv`, and
#'   `10_direct_intervention_effects.csv` in `input_dir` when present.
#' @param costs Optional cost inputs (`12_costs.csv`). When supplied, costed
#'   results and ICERs are produced.
#' @param stratum_rate_ratios Optional equity rate ratios
#'   (`11_stratum_rate_ratios.csv`). Used only when `equity = TRUE`.
#' @param equity Logical. Add a stratum-disaggregated disease-integration overlay
#'   using [integrate_disease_deltas()].
#' @param psa Logical. Run a probabilistic sensitivity analysis with
#'   [run_psa_interventions()].
#' @param psa_draws,psa_seed,psa_interval_width PSA controls passed through to
#'   [run_psa_interventions()].
#' @param report_by Grouping for the headline HALY and cost summaries. Defaults
#'   to `"overall"`.
#' @param cohort_size Disease-lifetable cohort size passed to
#'   [run_pmslt_interventions()].
#' @param overwrite Logical. Overwrite an existing solver output file.
#' @param ... Additional arguments passed to [solve_disease_consistency()].
#'
#' @return An object of class `pmslt_run`: a list with the resolved `disease_epi`,
#'   per-arm intervention `deltas`, the `lifetable` bridge object (BAU plus each
#'   intervention arm and their comparisons), `halys` summaries, optional `costs`
#'   and `icers`, optional `equity` and `psa` elements, the `arms` modelled, and
#'   run `metadata`. Use [summary()] for a readable overview.
#' @export
#'
#' @examples
#' \dontrun{
#' out <- tempfile("pmslt_inputs_")
#' generate_mock_pmslt_inputs(output_dir = out)
#' run <- run_pmslt(out, solver = "dismod_slove", horizon = 5)
#' summary(run)
#' }
run_pmslt <- function(input_dir = NULL,
                      spec = NULL,
                      solver = c("dismod_slove", "disbayes"),
                      horizon = NULL,
                      disease_epi = NULL,
                      population = NULL,
                      mortality = NULL,
                      morbidity = NULL,
                      risk_prevalence = NULL,
                      relative_risks = NULL,
                      direct_effects = NULL,
                      costs = NULL,
                      stratum_rate_ratios = NULL,
                      equity = FALSE,
                      psa = FALSE,
                      psa_draws = 100,
                      psa_seed = NULL,
                      psa_interval_width = 0.95,
                      report_by = "overall",
                      cohort_size = 1000,
                      overwrite = FALSE,
                      ...) {
  solver <- match.arg(solver)
  if (!is.null(spec)) {
    validate_spec(spec)
  }
  if (!is.null(horizon)) {
    horizon <- validate_lifetable_horizon(horizon, spec)
  } else if (!is.null(spec)) {
    horizon <- validate_lifetable_horizon(NULL, spec)
  }

  # --- Resolve inputs (explicit argument wins; otherwise look in input_dir) ----
  population <- resolve_run_pmslt_input(population, input_dir, "01_population.csv",
                                        required = TRUE, label = "population")
  mortality <- resolve_run_pmslt_input(mortality, input_dir, "02_all_cause_mortality.csv",
                                       required = TRUE, label = "mortality")
  morbidity <- resolve_run_pmslt_input(morbidity, input_dir, "03_all_cause_morbidity.csv",
                                       required = FALSE, label = "morbidity")
  risk_prevalence <- resolve_run_pmslt_input(risk_prevalence, input_dir, "08_risk_factor_prevalence.csv",
                                             required = FALSE, label = "risk_prevalence")
  relative_risks <- resolve_run_pmslt_input(relative_risks, input_dir, "09_relative_risks.csv",
                                            required = FALSE, label = "relative_risks")
  direct_effects <- resolve_run_pmslt_input(direct_effects, input_dir, "10_direct_intervention_effects.csv",
                                            required = FALSE, label = "direct_effects")
  costs <- resolve_run_pmslt_input(costs, input_dir, "12_costs.csv",
                                   required = FALSE, label = "costs")
  stratum_rate_ratios <- resolve_run_pmslt_input(stratum_rate_ratios, input_dir, "11_stratum_rate_ratios.csv",
                                                 required = equity, label = "stratum_rate_ratios")

  # --- Step 1: disease consistency ------------------------------------------
  solver_result <- NULL
  if (is.null(disease_epi)) {
    if (is.null(input_dir)) {
      stop("Supply `input_dir` (or a pre-solved `disease_epi`) so disease consistency can be solved.", call. = FALSE)
    }
    solver_result <- solve_disease_consistency(
      input_dir = input_dir,
      solver = solver,
      horizon = horizon,
      overwrite = overwrite,
      ...
    )
    disease_epi <- solver_result$pmslt_disease_epi
  } else if (is.character(disease_epi) && length(disease_epi) == 1) {
    disease_epi <- read_pmslt_disease_inputs(disease_epi)
  } else {
    validate_pmslt_disease_inputs(disease_epi)
  }

  # --- Step 2: intervention disease deltas -----------------------------------
  deltas <- run_pmslt_interventions(
    disease_epi = disease_epi,
    risk_prevalence = risk_prevalence,
    relative_risks = relative_risks,
    direct_effects = direct_effects,
    cohort_size = cohort_size
  )

  # --- Step 3: main all-cause lifetable for BAU and each arm -----------------
  lifetable <- run_pmslt_lifetable_interventions(
    population = population,
    mortality = mortality,
    morbidity = morbidity,
    intervention_effects = deltas,
    horizon = horizon,
    spec = spec
  )
  arms <- names(lifetable$interventions)

  # --- Step 4: outcomes, costs, ICERs ----------------------------------------
  halys <- list(
    bau = calculate_halys(lifetable$bau, by = report_by),
    interventions = stats::setNames(
      lapply(arms, function(arm) calculate_halys(lifetable$interventions[[arm]], by = report_by)),
      arms
    ),
    comparisons = stats::setNames(
      lapply(arms, function(arm) compare_halys(lifetable$bau, lifetable$interventions[[arm]], by = report_by)),
      arms
    )
  )

  cost_results <- NULL
  icers <- NULL
  if (!is.null(costs)) {
    bau_costed <- attach_pmslt_costs(lifetable$bau, costs, spec = spec)
    arm_costed <- stats::setNames(
      lapply(arms, function(arm) attach_pmslt_costs(lifetable$interventions[[arm]], costs, spec = spec)),
      arms
    )
    cost_results <- list(
      bau = summarise_pmslt_costs(bau_costed, by = report_by),
      interventions = stats::setNames(
        lapply(arms, function(arm) summarise_pmslt_costs(arm_costed[[arm]], by = report_by)),
        arms
      ),
      comparisons = stats::setNames(
        lapply(arms, function(arm) compare_pmslt_costs(bau_costed, arm_costed[[arm]], by = report_by)),
        arms
      )
    )
    icers <- build_run_pmslt_icers(lifetable, bau_costed, arm_costed, arms)
  }

  # --- Step 5 (optional): equity disaggregation overlay ----------------------
  equity_result <- NULL
  if (isTRUE(equity)) {
    if (is.null(stratum_rate_ratios)) {
      stop("`equity = TRUE` needs `stratum_rate_ratios` (11_stratum_rate_ratios.csv).", call. = FALSE)
    }
    bau_plain <- run_pmslt_lifetable_bau(
      population = population,
      mortality = mortality,
      morbidity = morbidity,
      horizon = horizon,
      spec = spec
    )
    equity_result <- integrate_disease_deltas(
      lifetable = bau_plain,
      disease_epi = disease_epi,
      stratum_rate_ratios = stratum_rate_ratios
    )
  }

  # --- Step 5 (optional): probabilistic sensitivity analysis -----------------
  psa_result <- NULL
  if (isTRUE(psa)) {
    psa_result <- run_psa_interventions(
      disease_epi = disease_epi,
      risk_prevalence = risk_prevalence,
      relative_risks = relative_risks,
      direct_effects = direct_effects,
      draws = psa_draws,
      seed = psa_seed,
      cohort_size = cohort_size,
      interval_width = psa_interval_width
    )
  }

  out <- list(
    spec = spec,
    disease_epi = disease_epi,
    deltas = deltas,
    lifetable = lifetable,
    halys = halys,
    costs = cost_results,
    icers = icers,
    equity = equity_result,
    psa = psa_result,
    arms = arms,
    metadata = list(
      solver = if (is.null(solver_result)) "supplied_disease_epi" else solver,
      horizon = horizon,
      input_dir = input_dir,
      report_by = report_by,
      run_at = Sys.time(),
      r_version = getRversion()
    )
  )
  class(out) <- "pmslt_run"
  out
}

# Resolve one run_pmslt() input: explicit argument, else file in input_dir.
resolve_run_pmslt_input <- function(value, input_dir, filename, required, label) {
  if (!is.null(value)) {
    return(value)
  }
  if (!is.null(input_dir)) {
    candidate <- file.path(input_dir, filename)
    if (file.exists(candidate)) {
      return(candidate)
    }
  }
  if (isTRUE(required)) {
    stop(
      "Cannot find `", label, "`. Supply it directly, or place `", filename,
      "` in `input_dir`.",
      call. = FALSE
    )
  }
  NULL
}

# Build a per-arm incremental cost/HALY table and its ICERs.
build_run_pmslt_icers <- function(lifetable, bau_costed, arm_costed, arms) {
  rows <- lapply(arms, function(arm) {
    haly_cmp <- compare_halys(lifetable$bau, lifetable$interventions[[arm]], by = "overall")
    cost_cmp <- compare_pmslt_costs(bau_costed, arm_costed[[arm]], by = "overall")
    data.frame(
      intervention = arm,
      haly_difference = haly_cmp$haly_difference,
      total_costs_difference = cost_cmp$total_costs_difference,
      stringsAsFactors = FALSE
    )
  })
  incremental <- do.call(rbind, rows)
  row.names(incremental) <- NULL
  calculate_icers(
    incremental,
    incremental_cost = "total_costs_difference",
    incremental_haly = "haly_difference"
  )
}

#' @export
print.pmslt_run <- function(x, ...) {
  cat("<pmslt_run>\n")
  cat("  solver:    ", x$metadata$solver, "\n", sep = "")
  cat("  horizon:   ", x$metadata$horizon, " year(s)\n", sep = "")
  cat("  arms:      ", paste(x$arms, collapse = ", "), "\n", sep = "")
  cat("  outputs:   halys",
      if (!is.null(x$costs)) ", costs" else "",
      if (!is.null(x$icers)) ", icers" else "",
      if (!is.null(x$equity)) ", equity" else "",
      if (!is.null(x$psa)) ", psa" else "",
      "\n", sep = "")
  cat("  Use summary() for headline results.\n")
  invisible(x)
}

#' @export
summary.pmslt_run <- function(object, ...) {
  cat("PMSLT run summary\n")
  cat("=================\n")
  cat("Solver: ", object$metadata$solver,
      " | Horizon: ", object$metadata$horizon, " year(s)",
      " | Arms: ", length(object$arms), "\n\n", sep = "")

  cat("Business-as-usual HALYs:\n")
  print(object$halys$bau, row.names = FALSE)

  for (arm in object$arms) {
    cat("\nArm: ", arm, "\n", sep = "")
    cat("  Incremental HALYs vs BAU:\n")
    print(object$halys$comparisons[[arm]], row.names = FALSE)
  }

  if (!is.null(object$icers)) {
    cat("\nIncremental cost-effectiveness (intervention - BAU):\n")
    print(object$icers, row.names = FALSE)
  }

  if (!is.null(object$psa)) {
    cat("\nPSA: ", max(object$psa$draw_outputs$draw, 0L),
        " draws; uncertainty summary available in `$psa$summary`.\n", sep = "")
  }
  invisible(object)
}
