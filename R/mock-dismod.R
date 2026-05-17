#' Create a mock PMSLT model specification
#'
#' This helper returns a small PMSLT specification with two intervention arms
#' for teaching and package demonstrations.
#'
#' @return A `pmslt_spec` object.
#' @export
mock_pmslt_spec <- function() {
  pmslt_spec(
    intervention = "Illustrative tobacco control intervention",
    intervention_arms = c("Tobacco tax", "Tobacco tax plus acute care"),
    mechanism = "both",
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

  if ("08_risk_factor_prevalence" %in% names(templates)) {
    prevalence <- fill_mock_risk_prevalence(templates[["08_risk_factor_prevalence"]])
    write_template_csv(prevalence, file.path(output_dir, "08_risk_factor_prevalence.csv"))
  }

  if ("09_relative_risks" %in% names(templates)) {
    rr <- fill_mock_relative_risks(templates[["09_relative_risks"]])
    write_template_csv(rr, file.path(output_dir, "09_relative_risks.csv"))
  }

  if ("10_direct_intervention_effects" %in% names(templates)) {
    direct <- fill_mock_direct_effects(templates[["10_direct_intervention_effects"]])
    write_template_csv(direct, file.path(output_dir, "10_direct_intervention_effects.csv"))
  }

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
#' @param continuous_age Logical. Should continuous single-year age outputs and
#'   PMSLT age-grid predictions be generated?
#'
#' @return Invisibly returns a list with `wide`, `long`, `diagnostics`,
#'   `continuous`, and `pmslt_ages`.
#' @export
mock_dismod_output <- function(input_dir = "mock_inputs_raw",
                               output_dir = file.path(input_dir, "mock_dismod_output"),
                               overwrite = TRUE,
                               continuous_age = TRUE) {
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
  continuous <- NULL
  pmslt_ages <- NULL
  if (isTRUE(continuous_age)) {
    continuous <- smooth_dismod_age_curve(output_dir, overwrite = overwrite)
    raw_ages <- unique(raw[c("age_start", "age_end", "age_label")])
    pmslt_ages <- predict_dismod_to_age_grid(output_dir, ages = raw_ages, overwrite = overwrite)
    prepare_pmslt_disease_inputs(
      input_dir = input_dir,
      dismod_output_dir = output_dir,
      overwrite = overwrite
    )
  }
  message("Mock DisMod outputs written to: ", normalizePath(output_dir))
  invisible(list(
    wide = wide,
    long = long,
    diagnostics = diagnostics,
    continuous = continuous,
    pmslt_ages = pmslt_ages
  ))
}

#' Prepare PMSLT-ready disease epidemiology inputs
#'
#' Converts post-DisMod PMSLT age-grid predictions into a wide, time-expanded
#' disease epidemiology file that can be passed to a PMSLT disease lifetable.
#'
#' @param input_dir Raw input directory containing `05_disease_epidemiology_raw.csv`
#'   and optionally `07_bau_trends.csv` and `08_risk_factor_prevalence.csv`.
#' @param dismod_output_dir Directory containing `mock_dismod_output_pmslt_ages.csv`.
#' @param output_file CSV path for PMSLT-ready disease inputs.
#' @param horizon Optional simulation horizon. If `NULL`, inferred from
#'   `08_risk_factor_prevalence.csv` when available; otherwise 0.
#' @param overwrite Logical. Should an existing output file be overwritten?
#'
#' @return Invisibly returns the PMSLT-ready disease input data frame.
#' @export
prepare_pmslt_disease_inputs <- function(input_dir = "mock_inputs_raw",
                                         dismod_output_dir = file.path(input_dir, "mock_dismod_output"),
                                         output_file = file.path(dismod_output_dir, "pmslt_disease_epi.csv"),
                                         horizon = NULL,
                                         overwrite = TRUE) {
  pmslt_age_path <- file.path(dismod_output_dir, "mock_dismod_output_pmslt_ages.csv")
  if (!file.exists(pmslt_age_path)) {
    predict_dismod_to_age_grid(dismod_output_dir = dismod_output_dir, overwrite = overwrite)
  }
  if (file.exists(output_file) && !isTRUE(overwrite)) {
    stop("File already exists: ", output_file, ". Use `overwrite = TRUE` to replace it.", call. = FALSE)
  }

  pmslt_long <- utils::read.csv(pmslt_age_path, stringsAsFactors = FALSE, na.strings = c("", "NA"))
  require_columns(
    pmslt_long,
    c("age_start", "age_end", "age_label", "sex", "stratum", "disease", "parameter", "dismod_age_grid_mean"),
    "mock_dismod_output_pmslt_ages.csv"
  )
  base <- stats::reshape(
    pmslt_long[c("age_start", "age_end", "age_label", "sex", "stratum", "disease", "parameter", "dismod_age_grid_mean")],
    idvar = c("age_start", "age_end", "age_label", "sex", "stratum", "disease"),
    timevar = "parameter",
    direction = "wide"
  )
  names(base) <- sub("dismod_age_grid_mean[.]", "", names(base))
  row.names(base) <- NULL

  raw_path <- file.path(input_dir, "05_disease_epidemiology_raw.csv")
  if (file.exists(raw_path)) {
    raw <- utils::read.csv(raw_path, stringsAsFactors = FALSE, na.strings = c("", "NA"))
    if ("disability_weight" %in% names(raw)) {
      raw_dw <- unique(raw[c("age_start", "age_end", "age_label", "sex", "stratum", "disease", "disability_weight")])
      base <- merge(base, raw_dw, by = c("age_start", "age_end", "age_label", "sex", "stratum", "disease"), all.x = TRUE, sort = FALSE)
    }
  }
  if (!"disability_weight" %in% names(base)) {
    base$disability_weight <- NA_real_
  }

  trend_path <- file.path(input_dir, "07_bau_trends.csv")
  if (file.exists(trend_path)) {
    trends <- utils::read.csv(trend_path, stringsAsFactors = FALSE, na.strings = c("", "NA"))
    keep <- intersect(c("disease", "incidence_apc", "cfr_apc", "prevalence_apc"), names(trends))
    base <- merge(base, unique(trends[keep]), by = "disease", all.x = TRUE, sort = FALSE)
  }
  for (col in c("incidence_apc", "cfr_apc", "prevalence_apc")) {
    if (!col %in% names(base)) {
      base[[col]] <- 0
    }
    base[[col]][is.na(base[[col]])] <- 0
  }

  if (is.null(horizon)) {
    horizon <- infer_mock_horizon(input_dir)
  }
  time_grid <- data.frame(time_step = seq.int(0, horizon), stringsAsFactors = FALSE)
  out <- merge(base, time_grid, all = TRUE)
  out$incidence_BAU <- out$incidence_rate * exp(out$incidence_apc * out$time_step)
  out$prevalence_initial <- ifelse(out$time_step == 0, out$prevalence, NA_real_)
  out$case_fatality_BAU <- out$case_fatality_rate * exp(out$cfr_apc * out$time_step)
  out$excess_mortality_BAU <- out$excess_mortality_rate * exp(out$cfr_apc * out$time_step)
  out$prevalence_BAU_reference <- out$prevalence * exp(out$prevalence_apc * out$time_step)
  out$input_source <- "post-DisMod PMSLT age-grid prediction"

  ordered_cols <- c(
    "age_start", "age_end", "age_label", "sex", "stratum", "disease", "time_step",
    "incidence_BAU", "prevalence_initial", "remission_rate",
    "excess_mortality_BAU", "case_fatality_BAU", "disability_weight",
    "prevalence_BAU_reference", "incidence_apc", "cfr_apc", "prevalence_apc",
    "input_source"
  )
  out <- out[ordered_cols]
  out <- out[order(out$disease, out$sex, out$stratum, out$age_start, out$time_step), ]
  row.names(out) <- NULL

  utils::write.csv(out, output_file, row.names = FALSE, na = "")
  invisible(out)
}

#' Smooth mock DisMod outputs over continuous age
#'
#' Fits simple parameter-specific age curves from mock DisMod corrected values
#' and predicts single-year age values. This represents the conceptual step
#' where DisMod smooths epidemiological parameters across continuous age.
#'
#' @param dismod_output_dir Directory created by [mock_dismod_output()].
#' @param output_file CSV path for continuous-age predictions.
#' @param age_min Minimum single-year age to predict. Defaults to the minimum
#'   raw age start.
#' @param age_max Maximum single-year age to predict. Defaults to the maximum
#'   raw age end.
#' @param parameters Parameters to smooth.
#' @param overwrite Logical. Should existing output be overwritten?
#'
#' @return Invisibly returns the continuous-age data frame.
#' @export
smooth_dismod_age_curve <- function(dismod_output_dir,
                                    output_file = file.path(dismod_output_dir, "mock_dismod_output_continuous.csv"),
                                    age_min = NULL,
                                    age_max = NULL,
                                    parameters = c(
                                      "incidence_rate", "prevalence", "remission_rate",
                                      "excess_mortality_rate", "case_fatality_rate"
                                    ),
                                    overwrite = TRUE) {
  long_path <- file.path(dismod_output_dir, "mock_dismod_output_long.csv")
  if (!file.exists(long_path)) {
    stop("Missing mock DisMod long output: ", long_path, call. = FALSE)
  }
  if (file.exists(output_file) && !isTRUE(overwrite)) {
    stop("File already exists: ", output_file, ". Use `overwrite = TRUE` to replace it.", call. = FALSE)
  }

  data <- utils::read.csv(long_path, stringsAsFactors = FALSE, na.strings = c("", "NA"))
  data <- data[data$parameter %in% parameters, , drop = FALSE]
  data$age_mid <- mock_age_midpoint(data)
  if (is.null(age_min)) {
    age_min <- floor(min(as.numeric(data$age_start), na.rm = TRUE))
  }
  if (is.null(age_max)) {
    age_max <- ceiling(max(as.numeric(data$age_end), na.rm = TRUE))
  }
  age <- seq.int(age_min, age_max)

  group_cols <- c("sex", "stratum", "disease", "parameter")
  groups <- unique(data[group_cols])
  rows <- lapply(seq_len(nrow(groups)), function(i) {
    group <- groups[i, , drop = FALSE]
    subset <- data[
      data$sex == group$sex &
        data$stratum == group$stratum &
        data$disease == group$disease &
        data$parameter == group$parameter,
      ,
      drop = FALSE
    ]
    value <- predict_smooth_parameter(
      x = subset$age_mid,
      y = subset$dismod_mean,
      xout = age,
      parameter = group$parameter
    )
    group_expanded <- group[rep(1, length(age)), , drop = FALSE]
    row.names(group_expanded) <- NULL
    data.frame(
      group_expanded,
      age = age,
      dismod_smoothed = value,
      smoothing_method = smoothing_method_label(subset),
      stringsAsFactors = FALSE
    )
  })

  out <- do.call(rbind, rows)
  utils::write.csv(out, output_file, row.names = FALSE, na = "")
  invisible(out)
}

#' Predict continuous-age mock DisMod curves to a PMSLT age grid
#'
#' Converts single-year smoothed values into the PMSLT model age bands. By
#' default this averages all single-year ages inside each PMSLT age band.
#'
#' @param dismod_output_dir Directory created by [mock_dismod_output()].
#' @param ages Age grid. Defaults to age bands inferred from
#'   `mock_dismod_output_long.csv`.
#' @param continuous_file CSV path created by [smooth_dismod_age_curve()].
#' @param output_file CSV path for PMSLT age-grid predictions.
#' @param method One of `"band_mean"` or `"midpoint"`.
#' @param overwrite Logical. Should existing output be overwritten?
#'
#' @return Invisibly returns the PMSLT-age data frame.
#' @export
predict_dismod_to_age_grid <- function(dismod_output_dir,
                                       ages = NULL,
                                       continuous_file = file.path(dismod_output_dir, "mock_dismod_output_continuous.csv"),
                                       output_file = file.path(dismod_output_dir, "mock_dismod_output_pmslt_ages.csv"),
                                       method = c("band_mean", "midpoint"),
                                       overwrite = TRUE) {
  method <- match.arg(method)
  if (!file.exists(continuous_file)) {
    smooth_dismod_age_curve(
      dismod_output_dir = dismod_output_dir,
      output_file = continuous_file,
      overwrite = overwrite
    )
  }
  if (file.exists(output_file) && !isTRUE(overwrite)) {
    stop("File already exists: ", output_file, ". Use `overwrite = TRUE` to replace it.", call. = FALSE)
  }
  continuous <- utils::read.csv(continuous_file, stringsAsFactors = FALSE, na.strings = c("", "NA"))
  if (is.null(ages)) {
    long_path <- file.path(dismod_output_dir, "mock_dismod_output_long.csv")
    raw <- utils::read.csv(long_path, stringsAsFactors = FALSE, na.strings = c("", "NA"))
    ages <- unique(raw[c("age_start", "age_end", "age_label")])
  } else {
    ages <- validate_age_table(ages)
  }

  group_cols <- c("sex", "stratum", "disease", "parameter")
  groups <- unique(continuous[group_cols])
  rows <- lapply(seq_len(nrow(groups)), function(i) {
    group <- groups[i, , drop = FALSE]
    curve <- continuous[
      continuous$sex == group$sex &
        continuous$stratum == group$stratum &
        continuous$disease == group$disease &
        continuous$parameter == group$parameter,
      ,
      drop = FALSE
    ]
    band_rows <- lapply(seq_len(nrow(ages)), function(j) {
      age_row <- ages[j, , drop = FALSE]
      age_end <- as.numeric(age_row$age_end)
      if (is.infinite(age_end)) {
        age_end <- max(curve$age, na.rm = TRUE)
      }
      if (method == "midpoint") {
        target_age <- round((as.numeric(age_row$age_start) + age_end) / 2)
        selected <- curve[curve$age == target_age, "dismod_smoothed"]
        if (length(selected) == 0 || is.na(selected[[1]])) {
          selected <- stats::approx(curve$age, curve$dismod_smoothed, xout = target_age, rule = 2)$y
        }
        value <- selected[[1]]
      } else {
        selected <- curve[curve$age >= age_row$age_start & curve$age <= age_end, "dismod_smoothed"]
        value <- mean(selected, na.rm = TRUE)
      }
      group_one <- group
      row.names(group_one) <- NULL
      data.frame(
        age_row,
        group_one,
        dismod_age_grid_mean = round(value, 8),
        age_prediction_method = method,
        stringsAsFactors = FALSE
      )
    })
    do.call(rbind, band_rows)
  })

  out <- do.call(rbind, rows)
  utils::write.csv(out, output_file, row.names = FALSE, na = "")
  invisible(out)
}

#' Plot raw points, continuous DisMod curve, and PMSLT age predictions
#'
#' @param dismod_output_dir Directory created by [mock_dismod_output()].
#' @param output_file Optional PNG output path.
#' @param parameters Parameters to plot.
#' @param disease Optional disease filter.
#' @param sex Optional sex filter.
#'
#' @return Invisibly returns a list with raw, continuous, and PMSLT-age data.
#' @export
plot_dismod_age_curve <- function(dismod_output_dir,
                                  output_file = file.path(dismod_output_dir, "dismod_continuous_age_curve.png"),
                                  parameters = c("incidence_rate", "prevalence"),
                                  disease = NULL,
                                  sex = NULL) {
  raw_path <- file.path(dismod_output_dir, "mock_dismod_output_long.csv")
  continuous_path <- file.path(dismod_output_dir, "mock_dismod_output_continuous.csv")
  pmslt_path <- file.path(dismod_output_dir, "mock_dismod_output_pmslt_ages.csv")
  if (!file.exists(raw_path)) {
    stop("Missing mock DisMod long output: ", raw_path, call. = FALSE)
  }
  if (!file.exists(continuous_path)) {
    smooth_dismod_age_curve(dismod_output_dir)
  }
  if (!file.exists(pmslt_path)) {
    predict_dismod_to_age_grid(dismod_output_dir)
  }

  raw <- utils::read.csv(raw_path, stringsAsFactors = FALSE, na.strings = c("", "NA"))
  continuous <- utils::read.csv(continuous_path, stringsAsFactors = FALSE, na.strings = c("", "NA"))
  pmslt <- utils::read.csv(pmslt_path, stringsAsFactors = FALSE, na.strings = c("", "NA"))
  raw$age_mid <- mock_age_midpoint(raw)
  pmslt$age_mid <- mock_age_midpoint(pmslt)

  raw <- filter_curve_data(raw, parameters, disease, sex)
  continuous <- filter_curve_data(continuous, parameters, disease, sex)
  pmslt <- filter_curve_data(pmslt, parameters, disease, sex)
  if (nrow(raw) == 0 || nrow(continuous) == 0 || nrow(pmslt) == 0) {
    stop("No rows to plot after filtering.", call. = FALSE)
  }

  if (!is.null(output_file)) {
    grDevices::png(output_file, width = 1400, height = 900, res = 150)
    device_open <- TRUE
  } else {
    device_open <- FALSE
  }
  plot_continuous_age_curve_base(raw, continuous, pmslt)
  if (isTRUE(device_open)) {
    grDevices::dev.off()
  }
  if (!is.null(output_file)) {
    message("Continuous age curve plot written to: ", normalizePath(output_file))
  }
  invisible(list(raw = raw, continuous = continuous, pmslt_ages = pmslt))
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
  tobacco_tax <- ifelse(
    prevalence$risk_category == "Never", 0.57,
    ifelse(prevalence$risk_category == "Current", 0.20, 0.23)
  )
  combined <- ifelse(
    prevalence$risk_category == "Never", 0.60,
    ifelse(prevalence$risk_category == "Current", 0.16, 0.24)
  )
  prevalence$prevalence_intervention <- ifelse(
    prevalence$intervention == "Tobacco tax plus acute care",
    combined,
    tobacco_tax
  )
  prevalence$source <- "mock smoking prevalence"
  prevalence$notes <- ifelse(
    prevalence$intervention == "Tobacco tax plus acute care",
    "Combined scenario has a larger smoking prevalence shift and direct disease management effects",
    "Tobacco tax shifts some current smokers to never/former categories"
  )
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

fill_mock_direct_effects <- function(direct) {
  direct$incidence_rr <- 1
  direct$cfr_rr <- 1
  direct$morbidity_rr <- 1
  direct$coverage <- 1

  acute_care <- direct$intervention == "Tobacco tax plus acute care"
  direct$cfr_rr[acute_care] <- ifelse(direct$disease[acute_care] == "CHD", 0.85, 0.9)
  direct$morbidity_rr[acute_care] <- ifelse(direct$disease[acute_care] == "CHD", 0.95, 0.96)
  direct$coverage[acute_care] <- 0.7
  direct$source <- "mock direct disease-management effect"
  direct$notes <- ifelse(
    acute_care,
    "Direct disease effect: improved acute care reduces case fatality and morbidity",
    "No direct disease effect in this intervention arm"
  )
  direct
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

predict_smooth_parameter <- function(x, y, xout, parameter) {
  x <- as.numeric(x)
  y <- as.numeric(y)
  keep <- !is.na(x) & !is.na(y) & is.finite(x) & is.finite(y)
  x <- x[keep]
  y <- y[keep]
  if (length(x) == 0) {
    return(rep(NA_real_, length(xout)))
  }
  if (length(unique(x)) == 1) {
    return(rep(y[[1]], length(xout)))
  }

  order_index <- order(x)
  x <- x[order_index]
  y <- y[order_index]
  if (parameter == "prevalence") {
    bounded <- pmin(0.999999, pmax(0.000001, y))
    transformed <- stats::qlogis(bounded)
    predicted <- smooth_on_scale(x, transformed, xout)
    return(round(stats::plogis(predicted), 8))
  }

  if (all(y > 0)) {
    predicted <- smooth_on_scale(x, log(y), xout)
    return(round(pmax(0, exp(predicted)), 8))
  }

  round(pmax(0, smooth_on_scale(x, y, xout)), 8)
}

smooth_on_scale <- function(x, y, xout) {
  if (length(unique(x)) >= 4) {
    fit <- stats::smooth.spline(x = x, y = y, spar = 0.55)
    return(stats::predict(fit, x = xout)$y)
  }
  stats::approx(x = x, y = y, xout = xout, rule = 2)$y
}

smoothing_method_label <- function(data) {
  if (length(unique(data$age_mid[!is.na(data$dismod_mean)])) >= 4) {
    "smooth_spline"
  } else {
    "linear_interpolation"
  }
}

filter_curve_data <- function(data, parameters, disease, sex) {
  data <- data[data$parameter %in% parameters, , drop = FALSE]
  if (!is.null(disease)) {
    data <- data[data$disease %in% disease, , drop = FALSE]
  }
  if (!is.null(sex)) {
    data <- data[data$sex %in% sex, , drop = FALSE]
  }
  data
}

plot_continuous_age_curve_base <- function(raw, continuous, pmslt) {
  raw$panel <- paste(raw$disease, raw$parameter, sep = " - ")
  continuous$panel <- paste(continuous$disease, continuous$parameter, sep = " - ")
  pmslt$panel <- paste(pmslt$disease, pmslt$parameter, sep = " - ")
  panels <- unique(raw$panel)
  old_par <- graphics::par(no.readonly = TRUE)
  on.exit(graphics::par(old_par), add = TRUE)
  graphics::par(mfrow = grDevices::n2mfrow(length(panels)), mar = c(4, 4, 3, 1))

  for (panel in panels) {
    raw_panel <- raw[raw$panel == panel, , drop = FALSE]
    continuous_panel <- continuous[continuous$panel == panel, , drop = FALSE]
    pmslt_panel <- pmslt[pmslt$panel == panel, , drop = FALSE]
    y_lim <- range(
      c(raw_panel$raw_value, raw_panel$dismod_mean, continuous_panel$dismod_smoothed, pmslt_panel$dismod_age_grid_mean),
      na.rm = TRUE
    )
    graphics::plot(
      continuous_panel$age,
      continuous_panel$dismod_smoothed,
      type = "l",
      lwd = 2,
      col = "#005F73",
      ylim = y_lim,
      xlab = "Age",
      ylab = "Value",
      main = panel
    )
    graphics::points(raw_panel$age_mid, raw_panel$raw_value, pch = 16, col = "#9E2A2B")
    graphics::points(raw_panel$age_mid, raw_panel$dismod_mean, pch = 17, col = "#0A9396")
    graphics::points(pmslt_panel$age_mid, pmslt_panel$dismod_age_grid_mean, pch = 15, col = "#EE9B00")
    graphics::legend(
      "topleft",
      legend = c("Continuous curve", "Raw band input", "Corrected band value", "PMSLT age-grid value"),
      col = c("#005F73", "#9E2A2B", "#0A9396", "#EE9B00"),
      pch = c(NA, 16, 17, 15),
      lty = c(1, NA, NA, NA),
      lwd = c(2, NA, NA, NA),
      bty = "n",
      cex = 0.75
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

infer_mock_horizon <- function(input_dir) {
  prevalence_path <- file.path(input_dir, "08_risk_factor_prevalence.csv")
  if (!file.exists(prevalence_path)) {
    return(0L)
  }
  prevalence <- utils::read.csv(prevalence_path, stringsAsFactors = FALSE, na.strings = c("", "NA"))
  if (!"time_step" %in% names(prevalence)) {
    return(0L)
  }
  max(as.integer(prevalence$time_step), na.rm = TRUE)
}

write_template_csv <- function(data, path) {
  utils::write.csv(data, path, row.names = FALSE, na = "")
}
