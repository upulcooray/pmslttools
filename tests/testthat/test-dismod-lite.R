test_that("dismod_slove solves prevalence and disaggregates coarse ages", {
  spec <- pmslt_spec(
    intervention = "Tax",
    mechanism = "risk_factor",
    diseases = "CHD",
    risk_factors = "Smoking",
    risk_categories = list(Smoking = c("Never", "Current")),
    ages = age_bands(20, 30, by = 5),
    sexes = "male",
    strata = "total",
    horizon = 2
  )

  out <- tempfile("pmslt_inputs_")
  draft_input_templates(spec, output_dir = out)

  raw <- data.frame(
    age_start = 20,
    age_end = 29,
    age_label = "20-29",
    sex = "male",
    stratum = "total",
    disease = "CHD",
    incidence_rate = 0.02,
    prevalence = NA_real_,
    remission_rate = 0.01,
    excess_mortality_rate = 0.03,
    case_fatality_rate = NA_real_,
    disability_weight = NA_real_,
    source = "test",
    notes = "",
    stringsAsFactors = FALSE
  )
  utils::write.csv(raw, file.path(out, "05_disease_epidemiology_raw.csv"), row.names = FALSE, na = "")

  result <- dismod_slove(out)

  solved <- result$solved_wide
  solved_20 <- solved[solved$age_start == 20 & solved$disease == "CHD", ]
  solved_25 <- solved[solved$age_start == 25 & solved$disease == "CHD", ]

  expect_true(all(solved$age_start == solved$age_end))
  expect_true(all(as.numeric(solved$age_start) == floor(as.numeric(solved$age_start))))
  expect_true(all(20:29 %in% solved$age_start))
  expect_equal(solved_20$prevalence, 0.02 / (0.02 + 0.01 + 0.03))
  expect_equal(solved_25$prevalence, 0.02 / (0.02 + 0.01 + 0.03))
  expect_equal(solved_20$incidence_source, "disaggregated_constant")
  expect_equal(solved_20$prevalence_source, "solved")
  expect_equal(solved_20$case_fatality_source, "derived_from_excess_mortality")
  expect_true(file.exists(file.path(out, "dismod_lite_results", "dismod_lite_solved_wide.csv")))
})

test_that("dismod_slove prefers filled long input over raw input", {
  spec <- pmslt_spec(
    intervention = "Tax",
    mechanism = "risk_factor",
    diseases = "CHD",
    risk_factors = "Smoking",
    risk_categories = list(Smoking = c("Never", "Current")),
    ages = data.frame(age_start = 20, age_end = 24, age_label = "20-24"),
    sexes = "male",
    strata = "total",
    horizon = 2
  )

  out <- tempfile("pmslt_inputs_")
  draft_input_templates(spec, output_dir = out)
  raw_path <- file.path(out, "05_disease_epidemiology_raw.csv")
  long_path <- file.path(out, "06_dismod_input_skeleton.csv")

  raw <- utils::read.csv(raw_path, stringsAsFactors = FALSE, na.strings = c("", "NA"))
  raw$incidence_rate <- 0.01
  raw$remission_rate <- 0.01
  raw$excess_mortality_rate <- 0.01
  utils::write.csv(raw, raw_path, row.names = FALSE, na = "")

  long <- utils::read.csv(long_path, stringsAsFactors = FALSE, na.strings = c("", "NA"))
  long$mean_value[long$parameter == "incidence"] <- 0.04
  utils::write.csv(long, long_path, row.names = FALSE, na = "")

  result <- dismod_slove(out)

  expect_true(all(result$solved_wide$incidence_rate == 0.04))
  expect_true(all(result$solved_wide$incidence_source == "disaggregated_constant"))
})

test_that("dismod_slove propagates uncertainty when bounds are available", {
  spec <- pmslt_spec(
    intervention = "Tax",
    mechanism = "risk_factor",
    diseases = "CHD",
    risk_factors = "Smoking",
    risk_categories = list(Smoking = c("Never", "Current")),
    ages = data.frame(age_start = 20, age_end = 24, age_label = "20-24"),
    sexes = "male",
    strata = "total",
    horizon = 2
  )

  out <- tempfile("pmslt_inputs_")
  draft_input_templates(spec, output_dir = out)
  long_path <- file.path(out, "06_dismod_input_skeleton.csv")
  long <- utils::read.csv(long_path, stringsAsFactors = FALSE, na.strings = c("", "NA"))

  fill_param <- function(parameter, mean, lower, upper) {
    index <- long$parameter == parameter
    long$mean_value[index] <<- mean
    long$lower_95[index] <<- lower
    long$upper_95[index] <<- upper
  }
  fill_param("incidence", 0.02, 0.015, 0.026)
  fill_param("remission", 0.01, 0.007, 0.014)
  fill_param("excess_mortality", 0.03, 0.022, 0.041)
  utils::write.csv(long, long_path, row.names = FALSE, na = "")

  result <- dismod_slove(out, uncertainty = TRUE, draws = 1000, seed = 1)

  solved <- result$solved_wide
  long_result <- result$solved_long[result$solved_long$parameter == "prevalence", ]

  expect_true(all(solved$prevalence == 0.02 / (0.02 + 0.01 + 0.03)))
  expect_true(all(!is.na(solved$prevalence_lower_95)))
  expect_true(all(!is.na(solved$prevalence_upper_95)))
  expect_true(all(solved$prevalence_lower_95 < solved$prevalence))
  expect_true(all(solved$prevalence_upper_95 > solved$prevalence))
  expect_equal(long_result$lower_95, solved$prevalence_lower_95)
  expect_equal(long_result$upper_95, solved$prevalence_upper_95)
})
