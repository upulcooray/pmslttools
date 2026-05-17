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
