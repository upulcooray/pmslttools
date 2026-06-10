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
#' @param discount_rate Annual discount rate applied to life-years, YLD, and
#'   costs in the headline summaries, using `1 / (1 + rate)^year`. Defaults to
#'   `0` (no discounting). A typical health economic value is `0.03`. The raw
#'   `lifetable` is always kept undiscounted.
#' @param scenario Optional label stored in the run metadata, useful when
#'   comparing or combining several `run_pmslt()` results.
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
                      discount_rate = 0,
                      scenario = NULL,
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
  discount_rate <- validate_discount_rate(discount_rate)
  if (!is.null(spec)) {
    validate_spec(spec)
  }
  if (!is.null(horizon)) {
    horizon <- validate_lifetable_horizon(horizon, spec)
  } else if (!is.null(spec)) {
    horizon <- validate_lifetable_horizon(NULL, spec)
  }

  # --- Resolve inputs (explicit argument wins; otherwise look in input_dir) ----
  # Population/mortality/morbidity may be supplied in the banded census template
  # format; prepare_lifetable_inputs() expands them to the exact single-year ages
  # the main lifetable engine requires (exact-age inputs pass through unchanged).
  lifetable_inputs <- prepare_lifetable_inputs(
    population = population,
    mortality = mortality,
    morbidity = morbidity,
    input_dir = input_dir
  )
  population <- lifetable_inputs$population
  mortality <- lifetable_inputs$mortality
  morbidity <- lifetable_inputs$morbidity
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
  # Reporting uses present-valued life-years and costs when discount_rate > 0.
  # The raw `lifetable` is left undiscounted for transparency.
  report_bau <- discount_lifetable_outcomes(lifetable$bau, discount_rate)
  report_arms <- stats::setNames(
    lapply(arms, function(arm) discount_lifetable_outcomes(lifetable$interventions[[arm]], discount_rate)),
    arms
  )

  halys <- list(
    bau = calculate_halys(report_bau, by = report_by),
    interventions = stats::setNames(
      lapply(arms, function(arm) calculate_halys(report_arms[[arm]], by = report_by)),
      arms
    ),
    comparisons = stats::setNames(
      lapply(arms, function(arm) compare_halys(report_bau, report_arms[[arm]], by = report_by)),
      arms
    )
  )

  cost_results <- NULL
  icers <- NULL
  if (!is.null(costs)) {
    bau_costed <- attach_pmslt_costs(report_bau, costs, spec = spec)
    arm_costed <- stats::setNames(
      lapply(arms, function(arm) attach_pmslt_costs(report_arms[[arm]], costs, spec = spec)),
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
    icers <- build_run_pmslt_icers(report_bau, report_arms, bau_costed, arm_costed, arms)
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
    # Push every parameter draw through the full lifetable + reporting chain so
    # uncertainty is summarised on the decision metrics (HALYs, costs, ICERs).
    psa_result$outcomes <- summarise_psa_outcomes(
      draw_outputs = psa_result$draw_outputs,
      population = population,
      mortality = mortality,
      morbidity = morbidity,
      horizon = horizon,
      spec = spec,
      costs = costs,
      discount_rate = discount_rate,
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
      discount_rate = discount_rate,
      scenario = scenario,
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
build_run_pmslt_icers <- function(report_bau, report_arms, bau_costed, arm_costed, arms) {
  rows <- lapply(arms, function(arm) {
    haly_cmp <- compare_halys(report_bau, report_arms[[arm]], by = "overall")
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

validate_discount_rate <- function(discount_rate) {
  if (!is.numeric(discount_rate) || length(discount_rate) != 1 || is.na(discount_rate)) {
    stop("`discount_rate` must be a single number, for example 0 or 0.03.", call. = FALSE)
  }
  if (discount_rate < 0 || discount_rate >= 1) {
    stop("`discount_rate` must be in [0, 1), for example 0.03 for 3% per year.", call. = FALSE)
  }
  discount_rate
}

# Discount life-years, YLD, and disease quantities to present value using
# 1 / (1 + r)^time_step. With r = 0 the input is returned unchanged. Costs are
# discounted downstream because they are derived from these discounted
# person-years.
discount_lifetable_outcomes <- function(results, discount_rate) {
  if (discount_rate == 0) {
    return(results)
  }
  factor <- 1 / (1 + discount_rate)^as.numeric(results$time_step)
  for (col in c("person_years", "yld", "total_disease_cases",
                "total_disease_deaths", "total_disease_yld")) {
    if (col %in% names(results)) {
      results[[col]] <- results[[col]] * factor
    }
  }
  deltas <- attr(results, "disease_deltas", exact = TRUE)
  if (is.data.frame(deltas)) {
    delta_factor <- 1 / (1 + discount_rate)^as.numeric(deltas$time_step)
    for (col in c("person_years", "disease_cases", "disease_deaths", "disease_yld")) {
      if (col %in% names(deltas)) {
        deltas[[col]] <- deltas[[col]] * delta_factor
      }
    }
    attr(results, "disease_deltas") <- deltas
  }
  results
}

# Run every PSA draw through the main lifetable and reporting layers, returning
# a per-arm uncertainty summary of incremental HALYs and (when costs are
# supplied) incremental costs and ICERs.
summarise_psa_outcomes <- function(draw_outputs,
                                   population,
                                   mortality,
                                   morbidity,
                                   horizon,
                                   spec,
                                   costs,
                                   discount_rate,
                                   interval_width) {
  if (!is.data.frame(draw_outputs) || nrow(draw_outputs) == 0) {
    return(data.frame())
  }
  rows <- list()
  for (draw in sort(unique(draw_outputs$draw))) {
    effects <- draw_outputs[draw_outputs$draw == draw, , drop = FALSE]
    effects$draw <- NULL
    bridge <- run_pmslt_lifetable_interventions(
      population = population,
      mortality = mortality,
      morbidity = morbidity,
      intervention_effects = effects,
      horizon = horizon,
      spec = spec
    )
    report_bau <- discount_lifetable_outcomes(bridge$bau, discount_rate)
    bau_costed <- if (is.null(costs)) NULL else attach_pmslt_costs(report_bau, costs, spec = spec)
    for (arm in names(bridge$interventions)) {
      report_arm <- discount_lifetable_outcomes(bridge$interventions[[arm]], discount_rate)
      haly_cmp <- compare_halys(report_bau, report_arm, by = "overall")
      row <- data.frame(
        draw = draw,
        intervention = arm,
        haly_difference = haly_cmp$haly_difference,
        stringsAsFactors = FALSE
      )
      if (!is.null(costs)) {
        cost_cmp <- compare_pmslt_costs(bau_costed, attach_pmslt_costs(report_arm, costs, spec = spec), by = "overall")
        row$cost_difference <- cost_cmp$total_costs_difference
        row$icer <- if (haly_cmp$haly_difference > 0) {
          cost_cmp$total_costs_difference / haly_cmp$haly_difference
        } else {
          NA_real_
        }
      }
      rows[[length(rows) + 1L]] <- row
    }
  }
  draws_long <- do.call(rbind, rows)
  metric_cols <- intersect(c("haly_difference", "cost_difference", "icer"), names(draws_long))
  probs <- c((1 - interval_width) / 2, 1 - (1 - interval_width) / 2)

  groups <- split(draws_long, draws_long$intervention)
  summary_rows <- lapply(groups, function(group) {
    out <- data.frame(intervention = group$intervention[[1]], stringsAsFactors = FALSE)
    for (metric in metric_cols) {
      values <- as.numeric(group[[metric]])
      qs <- stats::quantile(values, probs = probs, na.rm = TRUE, names = FALSE, type = 8)
      out[[paste0(metric, "_mean")]] <- mean(values, na.rm = TRUE)
      out[[paste0(metric, "_lower")]] <- qs[[1]]
      out[[paste0(metric, "_upper")]] <- qs[[2]]
    }
    out
  })
  out <- do.call(rbind, summary_rows)
  row.names(out) <- NULL
  out
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
      " | Discount: ", object$metadata$discount_rate * 100, "%",
      " | Arms: ", length(object$arms), "\n", sep = "")
  if (!is.null(object$metadata$scenario)) {
    cat("Scenario: ", object$metadata$scenario, "\n", sep = "")
  }
  cat("\n")

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
    cat("\nProbabilistic sensitivity analysis (incremental, mean and ",
        object$metadata$report_by, " interval):\n", sep = "")
    if (is.data.frame(object$psa$outcomes) && nrow(object$psa$outcomes) > 0) {
      print(object$psa$outcomes, row.names = FALSE)
    } else {
      cat("  draw-level deltas available in `$psa$summary`.\n")
    }
  }
  invisible(object)
}
