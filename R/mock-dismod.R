#' Create a mock PMSLT model specification
#'
#' This helper returns a small risk-factor-mediated PMSLT specification for
#' teaching and package demonstrations.
#'
#' @return A `pmslt_spec` object.
#' @export
mock_pmslt_spec <- function() {
  pmslt_spec(
    intervention = "Illustrative tobacco control intervention",
    mechanism = "risk_factor",
    diseases = c("CHD", "Stroke"),
    risk_factors = "Smoking",
    risk_categories = list(Smoking = c("Never", "Current", "Former")),
    ages = age_bands(40, 80, by = 10, open_ended = FALSE),
    sexes = c("male", "female"),
    strata = "total",
    horizon = 10,
    base_year = 2025,
    cost_effectiveness = FALSE
  )
}

#' Generate mock PMSLT input files
#'
#' Creates a complete `inputs_raw` folder with plausible demonstration values.
#' Disease epidemiology values are intentionally not perfectly coherent so that
#' [mock_dismod_output()] has visible before/after corrections to plot.
#'
#' @param output_dir Directory where mock raw input files should be written.
#' @param spec Optional `pmslt_spec`. Defaults to [mock_pmslt_spec()].
#' @param overwrite Logical. Should existing files be overwritten?
#'
#' @return Invisibly returns a list containing `spec` and generated templates.
#' @export
generate_mock_pmslt_inputs <- function(output_dir = "mock_inputs_raw",
                                       spec = mock_pmslt_spec(),
                                       overwrite = TRUE) {
  validate_spec(spec)
  templates <- draft_input_templates(spec, output_dir = output_dir, overwrite = overwrite)

  population <- templates[["01_population"]]
  age_mid <- mock_age_midpoint(population)
  sex_factor <- ifelse(population$sex == "male", 1.03, 0.97)
  population$initial_population <- round(100000 * exp(-(age_mid - min(age_mid)) / 70) * sex_factor)
  population$source <- "mock generated census counts"
  population$notes <- "Demonstration data only"
  write_template_csv(population, file.path(output_dir, "01_population.csv"))

  acmr <- templates[["02_all_cause_mortality"]]
  age_mid <- mock_age_midpoint(acmr)
  acmr$acmr_BAU <- round(0.002 * exp((age_mid - 40) / 25) * ifelse(acmr$sex == "male", 1.25, 0.9), 6)
  acmr$source <- "mock generated mortality curve"
  acmr$notes <- "Rates are per person-year"
  write_template_csv(acmr, file.path(output_dir, "02_all_cause_mortality.csv"))

  morbidity <- templates[["03_all_cause_morbidity"]]
  age_mid <- mock_age_midpoint(morbidity)
  morbidity$pYLD_BAU <- round(pmin(0.35, 0.06 + (age_mid - 40) * 0.004), 4)
  morbidity$source <- "mock generated pYLD"
  morbidity$notes <- "All-cause background morbidity"
  write_template_csv(morbidity, file.path(output_dir, "03_all_cause_morbidity.csv"))

  life_expectancy <- templates[["04_life_expectancy"]]
  life_expectancy$expected_years_remaining <- pmax(0, 88 - life_expectancy$age)
  life_expectancy$source <- "mock reference life table"
  life_expectancy$notes <- "Demonstration data only"
  write_template_csv(life_expectancy, file.path(output_dir, "04_life_expectancy.csv"))

  disease <- fill_mock_disease_epidemiology(templates[["05_disease_epidemiology_raw"]])
  write_template_csv(disease, file.path(output_dir, "05_disease_epidemiology_raw.csv"))

  dismod_input <- fill_mock_dismod_skeleton(templates[["06_dismod_input_skeleton"]], disease)
  write_template_csv(dismod_input, file.path(output_dir, "06_dismod_input_skeleton.csv"))

  trends <- templates[["07_bau_trends"]]
  trends$incidence_apc <- ifelse(trends$disease == "CHD", -0.012, -0.006)
  trends$cfr_apc <- ifelse(trends$disease == "CHD", -0.018, -0.01)
  trends$prevalence_apc <- NA_real_
  trends$source <- "mock trend assumption"
  trends$notes <- "Annual proportional change"
  write_template_csv(trends, file.path(output_dir, "07_bau_trends.csv"))

  prevalence <- fill_mock_risk_prevalence(templates[["08_risk_factor_prevalence"]])
  write_template_csv(prevalence, file.path(output_dir, "08_risk_factor_prevalence.csv"))

  rr <- fill_mock_relative_risks(templates[["09_relative_risks"]])
  write_template_csv(rr, file.path(output_dir, "09_relative_risks.csv"))

  invisible(list(spec = spec, templates = build_input_templates(spec)))
}

#' Generate mock DisMod-style corrected outputs
#'
#' This function creates deterministic, teaching-only outputs that look like a
#' post-DisMod correction file. It uses simple illness-death consistency
#' equations and age smoothing. It is not a replacement for DisMod-MR.
#'
#' @param input_dir Raw input directory created by [generate_mock_pmslt_inputs()]
#'   or [draft_input_templates()].
#' @param output_dir Directory where mock DisMod outputs should be written.
#' @param overwrite Logical. Should existing files be overwritten?
#'
#' @return Invisibly returns a list with `wide`, `long`, and `diagnostics`.
#' @export
mock_dismod_output <- function(input_dir = "mock_inputs_raw",
                               output_dir = file.path(input_dir, "mock_dismod_output"),
                               overwrite = TRUE) {
  raw_path <- file.path(input_dir, "05_disease_epidemiology_raw.csv")
  if (!file.exists(raw_path)) {
    stop("Missing raw disease file: ", raw_path, call. = FALSE)
  }

  raw <- utils::read.csv(raw_path, stringsAsFactors = FALSE, na.strings = c("", "NA"))
  require_columns(
    raw,
    c(
      "age_start", "age_end", "age_label", "sex", "stratum", "disease",
      "incidence_rate", "prevalence", "remission_rate",
      "excess_mortality_rate", "case_fatality_rate"
    ),
    "05_disease_epidemiology_raw.csv"
  )

  wide <- raw
  age_mid <- mock_age_midpoint(wide)
  disease_factor <- ifelse(wide$disease == "CHD", 1, 0.75)

  wide$dismod_incidence_rate <- smooth_positive(
    as.numeric(wide$incidence_rate),
    age_mid,
    lower = 1e-7
  )
  wide$dismod_remission_rate <- pmax(0, as.numeric(wide$remission_rate))
  wide$dismod_excess_mortality_rate <- smooth_positive(
    as.numeric(wide$excess_mortality_rate),
    age_mid,
    lower = 1e-7
  )
  coherent_prevalence <- wide$dismod_incidence_rate /
    (wide$dismod_incidence_rate + wide$dismod_remission_rate + wide$dismod_excess_mortality_rate)
  wide$dismod_prevalence <- round(pmin(0.95, pmax(0, coherent_prevalence)), 6)
  wide$dismod_case_fatality_rate <- round(wide$dismod_excess_mortality_rate * disease_factor, 6)

  wide$dismod_incidence_rate <- round(wide$dismod_incidence_rate, 6)
  wide$dismod_remission_rate <- round(wide$dismod_remission_rate, 6)
  wide$dismod_excess_mortality_rate <- round(wide$dismod_excess_mortality_rate, 6)

  wide$mock_dismod_note <- "Teaching-only correction using simple illness-death consistency equations"

  long <- mock_dismod_wide_to_long(wide)
  diagnostics <- mock_dismod_diagnostics(wide)

  write_mock_dismod_outputs(output_dir, wide, long, diagnostics, overwrite)
  message("Mock DisMod outputs written to: ", normalizePath(output_dir))
  invisible(list(wide = wide, long = long, diagnostics = diagnostics))
}

#' Plot raw versus mock DisMod-corrected epidemiological parameters
#'
#' Creates simple before/after plots from `mock_dismod_output_long.csv`.
#'
#' @param dismod_output_dir Directory created by [mock_dismod_output()].
#' @param output_file Optional PNG path. If `NULL`, plot on the active device.
#' @param parameters Character vector of parameters to plot. Defaults to all.
#' @param disease Optional disease filter.
#' @param sex Optional sex filter.
#'
#' @return Invisibly returns the plotted data.
#' @export
plot_dismod_corrections <- function(dismod_output_dir,
                                    output_file = file.path(dismod_output_dir, "epi_parameter_corrections.png"),
                                    parameters = c(
                                      "incidence_rate", "prevalence", "remission_rate",
                                      "excess_mortality_rate", "case_fatality_rate"
                                    ),
                                    disease = NULL,
                                    sex = NULL) {
  long_path <- file.path(dismod_output_dir, "mock_dismod_output_long.csv")
  if (!file.exists(long_path)) {
    stop("Missing mock DisMod long output: ", long_path, call. = FALSE)
  }

  data <- utils::read.csv(long_path, stringsAsFactors = FALSE, na.strings = c("", "NA"))
  data <- data[data$parameter %in% parameters, , drop = FALSE]
  if (!is.null(disease)) {
    data <- data[data$disease %in% disease, , drop = FALSE]
  }
  if (!is.null(sex)) {
    data <- data[data$sex %in% sex, , drop = FALSE]
  }
  if (nrow(data) == 0) {
    stop("No rows to plot after filtering.", call. = FALSE)
  }

  if (!is.null(output_file)) {
    grDevices::png(output_file, width = 1400, height = 900, res = 150)
    device_open <- TRUE
  } else {
    device_open <- FALSE
  }

  plot_mock_corrections_base(data)
  if (isTRUE(device_open)) {
    grDevices::dev.off()
  }
  if (!is.null(output_file)) {
    message("Correction plot written to: ", normalizePath(output_file))
  }
  invisible(data)
}

fill_mock_disease_epidemiology <- function(disease) {
  age_mid <- mock_age_midpoint(disease)
  sex_factor <- ifelse(disease$sex == "male", 1.15, 0.9)
  disease_factor <- ifelse(disease$disease == "CHD", 1, 0.7)

  disease$incidence_rate <- round(0.004 * exp((age_mid - 40) / 30) * sex_factor * disease_factor, 6)
  disease$remission_rate <- ifelse(disease$disease == "CHD", 0, 0.005)
  disease$excess_mortality_rate <- round(0.012 * exp((age_mid - 40) / 35) * disease_factor, 6)

  coherent <- disease$incidence_rate /
    (disease$incidence_rate + disease$remission_rate + disease$excess_mortality_rate)
  inconsistency_factor <- ifelse(disease$sex == "male", 1.35, 0.72)
  disease$prevalence <- round(pmin(0.85, coherent * inconsistency_factor), 6)
  disease$case_fatality_rate <- round(disease$excess_mortality_rate * ifelse(disease$disease == "CHD", 0.82, 1.4), 6)
  disease$disability_weight <- ifelse(disease$disease == "CHD", 0.18, 0.22)
  disease$source <- "mock deliberately inconsistent disease inputs"
  disease$notes <- "Demonstration data only; use mock_dismod_output() to create corrected outputs"
  disease
}

fill_mock_dismod_skeleton <- function(dismod_input, disease) {
  param_map <- c(
    incidence = "incidence_rate",
    prevalence = "prevalence",
    remission = "remission_rate",
    excess_mortality = "excess_mortality_rate",
    case_fatality = "case_fatality_rate"
  )
  key <- paste(disease$age_start, disease$sex, disease$stratum, disease$disease)
  disease_lookup <- split(disease, key)
  dismod_input$mean_value <- NA_real_
  dismod_input$lower_95 <- NA_real_
  dismod_input$upper_95 <- NA_real_
  for (i in seq_len(nrow(dismod_input))) {
    row_key <- paste(dismod_input$age_start[[i]], dismod_input$sex[[i]], dismod_input$stratum[[i]], dismod_input$disease[[i]])
    source_row <- disease_lookup[[row_key]]
    value <- source_row[[param_map[[dismod_input$parameter[[i]]]]]][[1]]
    dismod_input$mean_value[[i]] <- value
    dismod_input$lower_95[[i]] <- pmax(0, value * 0.8)
    dismod_input$upper_95[[i]] <- pmin(if (dismod_input$parameter[[i]] == "prevalence") 1 else Inf, value * 1.25)
  }
  dismod_input$data_source <- "mock raw disease input"
  dismod_input$quality_flag <- "Medium"
  dismod_input$notes <- "Mock DisMod skeleton populated for demonstration"
  dismod_input
}

fill_mock_risk_prevalence <- function(prevalence) {
  prevalence$prevalence_BAU <- ifelse(
    prevalence$risk_category == "Never", 0.52,
    ifelse(prevalence$risk_category == "Current", 0.28, 0.20)
  )
  prevalence$prevalence_intervention <- ifelse(
    prevalence$risk_category == "Never", 0.57,
    ifelse(prevalence$risk_category == "Current", 0.20, 0.23)
  )
  prevalence$source <- "mock smoking prevalence"
  prevalence$notes <- "Intervention shifts some current smokers to never/former categories"
  prevalence
}

fill_mock_relative_risks <- function(rr) {
  rr$rr <- ifelse(
    rr$risk_category == "Never", 1,
    ifelse(rr$risk_category == "Former", 1.35, ifelse(rr$disease == "CHD", 2.1, 1.8))
  )
  rr$rr_lower <- round(pmax(1, rr$rr * 0.85), 3)
  rr$rr_upper <- round(rr$rr * 1.2, 3)
  rr$reference_category <- "Never"
  rr$source <- "mock relative risks"
  rr$notes <- "Demonstration values only"
  rr
}

mock_dismod_wide_to_long <- function(wide) {
  params <- c(
    incidence_rate = "dismod_incidence_rate",
    prevalence = "dismod_prevalence",
    remission_rate = "dismod_remission_rate",
    excess_mortality_rate = "dismod_excess_mortality_rate",
    case_fatality_rate = "dismod_case_fatality_rate"
  )
  grid_cols <- c("age_start", "age_end", "age_label", "sex", "stratum", "disease")
  rows <- lapply(names(params), function(parameter) {
    raw_value <- as.numeric(wide[[parameter]])
    corrected <- as.numeric(wide[[params[[parameter]]]])
    data.frame(
      wide[grid_cols],
      parameter = parameter,
      raw_value = raw_value,
      dismod_mean = corrected,
      dismod_lower_95 = mock_lower(parameter, corrected),
      dismod_upper_95 = mock_upper(parameter, corrected),
      absolute_change = corrected - raw_value,
      relative_change_pct = ifelse(abs(raw_value) > 0, 100 * (corrected - raw_value) / raw_value, NA_real_),
      correction_note = ifelse(
        is.na(raw_value),
        "filled missing value",
        ifelse(abs(corrected - raw_value) > 1e-12, "corrected for mock consistency", "unchanged")
      ),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

mock_dismod_diagnostics <- function(wide) {
  data.frame(
    wide[c("age_start", "age_end", "age_label", "sex", "stratum", "disease")],
    raw_prevalence = wide$prevalence,
    corrected_prevalence = wide$dismod_prevalence,
    prevalence_relative_change_pct = ifelse(
      abs(wide$prevalence) > 0,
      100 * (wide$dismod_prevalence - wide$prevalence) / wide$prevalence,
      NA_real_
    ),
    note = wide$mock_dismod_note,
    stringsAsFactors = FALSE
  )
}

write_mock_dismod_outputs <- function(output_dir, wide, long, diagnostics, overwrite) {
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }
  outputs <- list(
    "mock_dismod_output_wide.csv" = wide,
    "mock_dismod_output_long.csv" = long,
    "mock_dismod_diagnostics.csv" = diagnostics
  )
  for (name in names(outputs)) {
    path <- file.path(output_dir, name)
    if (file.exists(path) && !isTRUE(overwrite)) {
      stop("File already exists: ", path, ". Use `overwrite = TRUE` to replace it.", call. = FALSE)
    }
    utils::write.csv(outputs[[name]], path, row.names = FALSE, na = "")
  }
}

plot_mock_corrections_base <- function(data) {
  data$panel <- paste(data$disease, data$parameter, sep = " - ")
  panels <- unique(data$panel)
  old_par <- graphics::par(no.readonly = TRUE)
  on.exit(graphics::par(old_par), add = TRUE)
  graphics::par(mfrow = grDevices::n2mfrow(length(panels)), mar = c(4, 4, 3, 1))

  for (panel in panels) {
    panel_data <- data[data$panel == panel, , drop = FALSE]
    age <- as.numeric(panel_data$age_start)
    raw <- as.numeric(panel_data$raw_value)
    corrected <- as.numeric(panel_data$dismod_mean)
    y_lim <- range(c(raw, corrected), na.rm = TRUE)
    graphics::plot(
      age,
      raw,
      type = "b",
      pch = 16,
      col = "#9E2A2B",
      ylim = y_lim,
      xlab = "Age start",
      ylab = "Value",
      main = panel
    )
    graphics::lines(age, corrected, type = "b", pch = 17, col = "#005F73")
    graphics::legend(
      "topleft",
      legend = c("Raw input", "Mock DisMod corrected"),
      col = c("#9E2A2B", "#005F73"),
      pch = c(16, 17),
      lty = 1,
      bty = "n",
      cex = 0.8
    )
  }
}

mock_age_midpoint <- function(data) {
  age_end <- as.numeric(data$age_end)
  age_end[is.infinite(age_end)] <- as.numeric(data$age_start[is.infinite(age_end)]) + 4
  (as.numeric(data$age_start) + age_end) / 2
}

smooth_positive <- function(value, age_mid, lower = 0) {
  value <- as.numeric(value)
  if (all(is.na(value))) {
    return(value)
  }
  filled <- value
  missing <- is.na(filled)
  if (any(missing)) {
    filled[missing] <- stats::approx(
      x = age_mid[!missing],
      y = value[!missing],
      xout = age_mid[missing],
      rule = 2
    )$y
  }
  pmax(lower, filled)
}

mock_lower <- function(parameter, value) {
  out <- pmax(0, value * 0.85)
  if (parameter == "prevalence") {
    out <- pmin(1, out)
  }
  round(out, 6)
}

mock_upper <- function(parameter, value) {
  out <- value * 1.18
  if (parameter == "prevalence") {
    out <- pmin(1, out)
  }
  round(out, 6)
}

write_template_csv <- function(data, path) {
  utils::write.csv(data, path, row.names = FALSE, na = "")
}
