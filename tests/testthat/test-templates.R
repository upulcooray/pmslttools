test_that("template builder includes risk factor files", {
  spec <- pmslt_spec(
    intervention = "Tax",
    mechanism = "risk_factor",
    diseases = c("CHD", "Stroke"),
    risk_factors = "Smoking",
    ages = age_bands(20, 30, by = 5),
    sexes = c("male", "female"),
    strata = "total",
    horizon = 2
  )

  templates <- pmslttools:::build_input_templates(spec)

  expect_true("08_risk_factor_prevalence" %in% names(templates))
  expect_true("09_relative_risks" %in% names(templates))
  expect_true(all(c("acmr_BAU", "source", "notes") %in% names(templates[["02_all_cause_mortality"]])))
})

test_that("draft_input_templates writes a beginner guide", {
  spec <- pmslt_spec(
    intervention = "Tax",
    mechanism = "risk_factor",
    diseases = c("CHD", "Stroke"),
    risk_factors = "Smoking",
    ages = age_bands(20, 30, by = 5),
    sexes = c("male", "female"),
    strata = "total",
    horizon = 2
  )

  out <- tempfile("pmslt_inputs_")
  draft_input_templates(spec, output_dir = out)
  guide_path <- file.path(out, "README_inputs_raw.md")
  guide <- readLines(guide_path)

  expect_true(file.exists(guide_path))
  expect_true(any(grepl("05_disease_epidemiology_raw.csv", guide, fixed = TRUE)))
  expect_true(any(grepl("incidence_rate", guide, fixed = TRUE)))
  expect_true(any(grepl("per person-year", guide, fixed = TRUE)))
})

test_that("missing parameter diagnostics are plain-language", {
  spec <- pmslt_spec(
    intervention = "Tax",
    mechanism = "risk_factor",
    diseases = "CHD",
    risk_factors = "Smoking"
  )

  diagnosis <- diagnose_missing_parameters(spec = spec)

  expect_equal(diagnosis$disease, "CHD")
  expect_false(diagnosis$dismod_ready)
  expect_match(diagnosis$message, "Collect at least 3")
})
