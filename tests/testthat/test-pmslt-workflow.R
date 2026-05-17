test_that("post-DisMod PMSLT disease inputs are canonical downstream inputs", {
  out <- tempfile("mock_inputs_")
  generate_mock_pmslt_inputs(output_dir = out)
  mock_dismod_output(input_dir = out)

  path <- file.path(out, "mock_dismod_output", "pmslt_disease_epi.csv")
  disease_epi <- read_pmslt_disease_inputs(path)

  expect_true(validate_pmslt_disease_inputs(disease_epi))
  expect_true(all(c("incidence_BAU", "prevalence_initial", "case_fatality_BAU") %in% names(disease_epi)))
  expect_true(any(disease_epi$time_step > 0))
})

test_that("disease lifetable consumes pmslt_disease_epi directly", {
  out <- tempfile("mock_inputs_")
  generate_mock_pmslt_inputs(output_dir = out)
  mock_dismod_output(input_dir = out)

  path <- file.path(out, "mock_dismod_output", "pmslt_disease_epi.csv")
  bau <- run_pmslt_disease_lifetable(path)

  expect_true(all(c("delta_mortality", "delta_morbidity") %in% names(bau)))
  expect_equal(max(abs(bau$delta_mortality), na.rm = TRUE), 0)
  expect_equal(max(abs(bau$delta_morbidity), na.rm = TRUE), 0)

  disease_epi <- read_pmslt_disease_inputs(path)
  pif <- unique(disease_epi[c("age_start", "sex", "stratum", "disease", "time_step")])
  pif$pif <- ifelse(pif$disease == "CHD" & pif$time_step > 0, 0.1, 0)
  intervention <- run_pmslt_disease_lifetable(disease_epi, pif_data = pif)

  expect_true(any(abs(intervention$delta_mortality) > 0, na.rm = TRUE))
  expect_true(any(abs(intervention$delta_morbidity) > 0, na.rm = TRUE))
})

test_that("risk prevalence and relative risks are converted to intervention PIFs", {
  out <- tempfile("mock_inputs_")
  generate_mock_pmslt_inputs(output_dir = out)

  prevalence_path <- file.path(out, "08_risk_factor_prevalence.csv")
  expect_equal(nrow(validate_risk_prevalence_inputs(prevalence_path, stop_on_error = FALSE)), 0)

  pif <- calculate_pif_from_inputs(
    prevalence_path,
    file.path(out, "09_relative_risks.csv")
  )

  expect_true(all(c("intervention", "disease", "time_step", "pif") %in% names(pif)))
  expect_equal(sort(unique(pif$intervention)), c("Tobacco tax", "Tobacco tax plus acute care"))
  expect_true(any(pif$pif > 0))
})

test_that("risk prevalence validation catches category sums that are not 1", {
  out <- tempfile("mock_inputs_")
  generate_mock_pmslt_inputs(output_dir = out)
  prevalence <- utils::read.csv(file.path(out, "08_risk_factor_prevalence.csv"))
  prevalence$prevalence_intervention[[1]] <- prevalence$prevalence_intervention[[1]] + 0.2

  issues <- validate_risk_prevalence_inputs(prevalence, stop_on_error = FALSE)

  expect_gt(nrow(issues), 0)
  expect_true("prevalence_sum" %in% names(issues))
  expect_error(
    calculate_pif_from_inputs(prevalence, file.path(out, "09_relative_risks.csv")),
    "must sum to 1"
  )
})

test_that("intervention runner supports PIF and direct disease effects", {
  out <- tempfile("mock_inputs_")
  generate_mock_pmslt_inputs(output_dir = out)
  mock_dismod_output(input_dir = out)

  disease_epi <- file.path(out, "mock_dismod_output", "pmslt_disease_epi.csv")
  results <- run_pmslt_interventions(
    disease_epi = disease_epi,
    risk_prevalence = file.path(out, "08_risk_factor_prevalence.csv"),
    relative_risks = file.path(out, "09_relative_risks.csv"),
    direct_effects = file.path(out, "10_direct_intervention_effects.csv")
  )

  expect_equal(sort(unique(results$intervention)), c("Tobacco tax", "Tobacco tax plus acute care"))
  expect_true(any(results$cfr_multiplier < 1))
  expect_true(any(abs(results$delta_mortality) > 0, na.rm = TRUE))
})
