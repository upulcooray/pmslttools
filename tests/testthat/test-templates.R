test_that("template builder includes risk factor files", {
  spec <- pmslt_spec(
    intervention = "Tax",
    intervention_arms = c("Tax", "Tax plus cessation"),
    mechanism = "risk_factor",
    diseases = c("CHD", "Stroke"),
    risk_factors = "Smoking",
    risk_categories = list(Smoking = c("Never", "Current", "Former")),
    ages = age_bands(20, 30, by = 5),
    sexes = c("male", "female"),
    strata = "total",
    horizon = 2
  )

  templates <- pmslttools:::build_input_templates(spec)

  expect_true("08_risk_factor_prevalence" %in% names(templates))
  expect_true("09_relative_risks" %in% names(templates))
  expect_true("00_column_dictionary" %in% names(templates))
  expect_true(all(c("acmr_BAU", "source", "notes") %in% names(templates[["02_all_cause_mortality"]])))
  expect_equal(
    templates[["00_column_dictionary"]]$requirement[
      templates[["00_column_dictionary"]]$file == "08_risk_factor_prevalence.csv" &
        templates[["00_column_dictionary"]]$column == "prevalence_intervention"
    ],
    "required"
  )
  expect_equal(
    sort(unique(templates[["08_risk_factor_prevalence"]]$risk_category)),
    c("Current", "Former", "Never")
  )
  expect_equal(
    sort(unique(templates[["08_risk_factor_prevalence"]]$intervention)),
    c("Tax", "Tax plus cessation")
  )
  expect_equal(
    sort(unique(templates[["09_relative_risks"]]$risk_category)),
    c("Current", "Former", "Never")
  )
})

test_that("draft_input_templates writes a beginner guide", {
  spec <- pmslt_spec(
    intervention = "Tax",
    mechanism = "risk_factor",
    diseases = c("CHD", "Stroke"),
    risk_factors = "Smoking",
    risk_categories = list(Smoking = c("Never", "Current", "Former")),
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
  expect_true(any(grepl("`prevalence_intervention` *", guide, fixed = TRUE)))
  expect_true(any(grepl("per person-year", guide, fixed = TRUE)))
})

test_that("missing parameter diagnostics are plain-language", {
  spec <- pmslt_spec(
    intervention = "Tax",
    mechanism = "risk_factor",
    diseases = "CHD",
    risk_factors = "Smoking",
    risk_categories = list(Smoking = c("Never", "Current"))
  )

  diagnosis <- diagnose_missing_parameters(spec = spec)

  expect_equal(diagnosis$disease, "CHD")
  expect_false(diagnosis$dismod_ready)
  expect_match(diagnosis$message, "Collect at least 3")
})
