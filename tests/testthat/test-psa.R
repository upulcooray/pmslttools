test_that("PSA parameter draw schema is explicit before sampling", {
  schema <- psa_parameter_draw_schema()

  expect_true(all(c(
    "parameter_group", "source_file", "key_columns",
    "mean_column", "distribution", "deterministic_consumer"
  ) %in% names(schema)))
  expect_true("relative_risk" %in% schema$parameter_group)
  expect_equal(
    schema$source_file[schema$parameter_group == "relative_risk"],
    "09_relative_risks.csv"
  )
})

test_that("PSA draws are reproducible and schema-backed", {
  out <- tempfile("mock_inputs_")
  generate_mock_pmslt_inputs(output_dir = out)
  rr <- utils::read.csv(file.path(out, "09_relative_risks.csv"), stringsAsFactors = FALSE)
  rr$rr_lower <- rr$rr * 0.8
  rr$rr_upper <- rr$rr * 1.2
  rr$rr_lower[rr$rr == 1] <- 1
  rr$rr_upper[rr$rr == 1] <- 1

  first <- draw_psa_parameters(draws = 5, seed = 123, relative_risks = rr)
  second <- draw_psa_parameters(draws = 5, seed = 123, relative_risks = rr)

  expect_equal(first, second)
  expect_equal(sort(unique(first$draw)), 1:5)
  expect_true(any(first$distribution == "lognormal_95ci"))
  expect_true(all(first$parameter_group == "relative_risk"))
})

test_that("PSA rejects non-schema intervention inputs", {
  bad_rr <- data.frame(
    age_start = 40,
    sex = "male",
    stratum = "total",
    risk_factor = "Smoking",
    disease = "CHD",
    risk_category = "Current",
    rr = 2,
    stringsAsFactors = FALSE
  )

  expect_error(
    draw_psa_parameters(draws = 2, relative_risks = bad_rr),
    "missing"
  )
})

test_that("PSA runner repeats deterministic intervention workflow by draw", {
  out <- tempfile("mock_inputs_")
  generate_mock_pmslt_inputs(output_dir = out)
  mock_dismod_output(input_dir = out)

  rr <- utils::read.csv(file.path(out, "09_relative_risks.csv"), stringsAsFactors = FALSE)
  rr$rr_lower <- rr$rr * 0.85
  rr$rr_upper <- rr$rr * 1.15
  rr$rr_lower[rr$rr == 1] <- 1
  rr$rr_upper[rr$rr == 1] <- 1

  psa <- run_psa_interventions(
    disease_epi = file.path(out, "mock_dismod_output", "pmslt_disease_epi.csv"),
    risk_prevalence = file.path(out, "08_risk_factor_prevalence.csv"),
    relative_risks = rr,
    direct_effects = file.path(out, "10_direct_intervention_effects.csv"),
    draws = 4,
    seed = 42
  )
  psa_again <- run_psa_interventions(
    disease_epi = file.path(out, "mock_dismod_output", "pmslt_disease_epi.csv"),
    risk_prevalence = file.path(out, "08_risk_factor_prevalence.csv"),
    relative_risks = rr,
    direct_effects = file.path(out, "10_direct_intervention_effects.csv"),
    draws = 4,
    seed = 42
  )

  expect_equal(psa$draw_outputs, psa_again$draw_outputs)
  expect_equal(psa$parameter_draws, psa_again$parameter_draws)
  expect_equal(nrow(psa$failures), 0)
  expect_equal(sort(unique(psa$draw_outputs$draw)), 1:4)
  expect_true(all(c("intervention", "delta_mortality_mean", "delta_mortality_lower", "delta_mortality_upper") %in% names(psa$summary)))
})

test_that("PSA draw failures are returned without hiding deterministic errors", {
  out <- tempfile("mock_inputs_")
  generate_mock_pmslt_inputs(output_dir = out)
  mock_dismod_output(input_dir = out)

  rr <- utils::read.csv(file.path(out, "09_relative_risks.csv"), stringsAsFactors = FALSE, na.strings = c("", "NA"))
  rr$rr <- NA_real_
  rr$rr_lower <- NA_real_
  rr$rr_upper <- NA_real_

  psa <- run_psa_interventions(
    disease_epi = file.path(out, "mock_dismod_output", "pmslt_disease_epi.csv"),
    risk_prevalence = file.path(out, "08_risk_factor_prevalence.csv"),
    relative_risks = rr,
    draws = 2,
    seed = 1
  )

  expect_equal(nrow(psa$draw_outputs), 0)
  expect_equal(psa$failures$draw, 1:2)
  expect_true(all(psa$failures$parameter_group == "intervention_workflow"))
  expect_true(any(grepl("Missing relative risk rows", psa$failures$message)))
})

test_that("solver uncertainty fields can be drawn without Bayesian dependencies", {
  out <- tempfile("mock_inputs_")
  generate_mock_pmslt_inputs(output_dir = out)
  long <- utils::read.csv(file.path(out, "06_dismod_input_skeleton.csv"), stringsAsFactors = FALSE)
  long$mean_value[long$parameter == "incidence"] <- 0.02
  long$lower_95[long$parameter == "incidence"] <- 0.015
  long$upper_95[long$parameter == "incidence"] <- 0.026

  draws <- draw_psa_parameters(draws = 3, seed = 99, solver_evidence = long)
  incidence <- draws[
    draws$parameter_group == "solver_evidence" &
      draws$parameter == "incidence",
    ,
    drop = FALSE
  ]

  expect_equal(sort(unique(incidence$draw)), 1:3)
  expect_true(all(incidence$source_file == "06_dismod_input_skeleton.csv"))
  expect_true(any(incidence$distribution == "lognormal_95ci"))
})
