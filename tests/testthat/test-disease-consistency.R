test_that("disbayes solver gives a clear optional dependency message when absent", {
  skip_if(requireNamespace("disbayes", quietly = TRUE))

  expect_error(
    solve_disease_consistency(tempfile("inputs_"), solver = "disbayes"),
    "optional `disbayes` package is not installed",
    fixed = TRUE
  )
})

test_that("disbayes bridge maps fake fitted output to canonical PMSLT columns", {
  spec <- pmslt_spec(
    intervention = "Tax",
    mechanism = "risk_factor",
    diseases = "CHD",
    risk_factors = "Smoking",
    risk_categories = list(Smoking = c("Never", "Current")),
    ages = data.frame(age_start = 20, age_end = 21, age_label = "20-21"),
    sexes = "male",
    strata = "total",
    horizon = 1
  )

  out <- tempfile("pmslt_inputs_")
  draft_input_templates(spec, output_dir = out)
  raw_path <- file.path(out, "05_disease_epidemiology_raw.csv")
  long_path <- file.path(out, "06_dismod_input_skeleton.csv")

  raw <- utils::read.csv(raw_path, stringsAsFactors = FALSE, na.strings = c("", "NA"))
  raw$disability_weight <- 0.20
  raw$source <- "test"
  utils::write.csv(raw, raw_path, row.names = FALSE, na = "")

  long <- utils::read.csv(long_path, stringsAsFactors = FALSE, na.strings = c("", "NA"))
  fill_param <- function(parameter, mean, lower, upper) {
    index <- long$parameter == parameter
    long$mean_value[index] <<- mean
    long$lower_95[index] <<- lower
    long$upper_95[index] <<- upper
    long$sample_size[index] <<- 1000
  }
  fill_param("incidence", 0.02, 0.015, 0.026)
  fill_param("prevalence", 0.10, 0.08, 0.12)
  fill_param("remission", 0.01, 0.007, 0.014)
  fill_param("mortality", 0.015, 0.011, 0.020)
  fill_param("case_fatality", 0.03, 0.022, 0.041)
  utils::write.csv(long, long_path, row.names = FALSE, na = "")

  fake_disbayes <- function(data, ...) {
    expect_true(all(c("age", "inc_prob", "prev_prob", "mort_prob", "rem_prob") %in% names(data)))
    expect_equal(nrow(data), length(unique(data$age)))
    ages <- sort(unique(data$age))
    data.frame(
      age = ages,
      inc = 1 - exp(-0.02),
      rem = 1 - exp(-0.01),
      cf = 1 - exp(-0.03),
      prev_prob = 0.10,
      stringsAsFactors = FALSE
    )
  }

  result <- solve_disease_consistency(
    out,
    solver = "disbayes",
    fit_function = fake_disbayes
  )
  disease_epi <- result$pmslt_disease_epi

  expect_equal(result$solver, "disbayes")
  expect_equal(names(disease_epi), pmslttools:::pmslt_disease_epi_schema()$columns$column)
  expect_equal(sort(unique(disease_epi$age)), 20:21)
  expect_equal(disease_epi$incidence_BAU[disease_epi$time_step == 0], rep(0.02, 2), tolerance = 1e-10)
  expect_equal(disease_epi$remission_rate[disease_epi$time_step == 0], rep(0.01, 2), tolerance = 1e-10)
  expect_equal(disease_epi$case_fatality_BAU[disease_epi$time_step == 0], rep(0.03, 2), tolerance = 1e-10)
  expect_equal(disease_epi$prevalence_initial[disease_epi$time_step == 0], rep(0.10, 2))
  expect_true(all(is.na(disease_epi$excess_mortality_BAU)))
  expect_equal(disease_epi$disability_weight, rep(0.20, nrow(disease_epi)))
  expect_true(validate_pmslt_disease_inputs(disease_epi))

  output_dir <- file.path(out, "disease_consistency_results")
  expect_true(file.exists(file.path(output_dir, "pmslt_disease_epi.csv")))
  expect_true(file.exists(file.path(output_dir, "disbayes_solver_long.csv")))
  expect_true(file.exists(file.path(output_dir, "disbayes_fit_summary.csv")))
  expect_true(file.exists(file.path(output_dir, "disbayes_rate_conversion_audit.csv")))
  expect_true(file.exists(file.path(output_dir, "disbayes_evidence_audit.csv")))
  expect_true(file.exists(file.path(output_dir, "disbayes_group_diagnostics.csv")))
})

test_that("disbayes bridge preserves explicit excess mortality when supplied", {
  spec <- pmslt_spec(
    intervention = "Tax",
    mechanism = "risk_factor",
    diseases = "CHD",
    risk_factors = "Smoking",
    risk_categories = list(Smoking = c("Never", "Current")),
    ages = data.frame(age_start = 20, age_end = 20, age_label = "20"),
    sexes = "male",
    strata = "total",
    horizon = 1
  )

  out <- tempfile("pmslt_inputs_")
  draft_input_templates(spec, output_dir = out)
  raw_path <- file.path(out, "05_disease_epidemiology_raw.csv")
  long_path <- file.path(out, "06_dismod_input_skeleton.csv")
  raw <- utils::read.csv(raw_path, stringsAsFactors = FALSE, na.strings = c("", "NA"))
  raw$excess_mortality_rate <- 0.04
  raw$disability_weight <- 0.20
  utils::write.csv(raw, raw_path, row.names = FALSE, na = "")

  long <- utils::read.csv(long_path, stringsAsFactors = FALSE, na.strings = c("", "NA"))
  fill_param <- function(parameter, mean, lower, upper) {
    index <- long$parameter == parameter
    long$mean_value[index] <<- mean
    long$lower_95[index] <<- lower
    long$upper_95[index] <<- upper
    long$sample_size[index] <<- 1000
  }
  fill_param("incidence", 0.02, 0.015, 0.026)
  fill_param("prevalence", 0.10, 0.08, 0.12)
  fill_param("remission", 0.01, 0.007, 0.014)
  fill_param("mortality", 0.015, 0.011, 0.020)
  fill_param("excess_mortality", 0.04, 0.030, 0.050)
  fill_param("case_fatality", 0.03, 0.022, 0.041)
  utils::write.csv(long, long_path, row.names = FALSE, na = "")

  fake_disbayes <- function(data, ...) {
    expect_true(all(c("age", "inc_prob", "prev_prob", "mort_prob", "rem_prob") %in% names(data)))
    expect_equal(nrow(data), length(unique(data$age)))
    data.frame(
      age = sort(unique(data$age)),
      inc = 1 - exp(-0.02),
      rem = 1 - exp(-0.01),
      cf = 1 - exp(-0.03),
      prev_prob = 0.10,
      stringsAsFactors = FALSE
    )
  }

  result <- solve_disease_consistency(
    out,
    solver = "disbayes",
    horizon = 0,
    fit_function = fake_disbayes
  )

  expect_equal(result$pmslt_disease_epi$excess_mortality_BAU, 0.04)
})
