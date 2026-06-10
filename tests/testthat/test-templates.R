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
  expect_true(all(c("validation_type", "allowed_values") %in% names(templates[["00_column_dictionary"]])))
  expect_equal(
    templates[["00_column_dictionary"]]$validation_type[
      templates[["00_column_dictionary"]]$file == "08_risk_factor_prevalence.csv" &
        templates[["00_column_dictionary"]]$column == "prevalence_intervention"
    ],
    "proportion_0_1"
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
  expect_true("disease_mortality_rate" %in% names(templates[["05_disease_epidemiology_raw"]]))
  expect_true("mortality" %in% templates[["06_dismod_input_skeleton"]]$parameter)
})

test_that("central schemas describe generated template columns", {
  spec <- pmslt_spec(
    intervention = "Tax",
    intervention_arms = c("Tax", "Tax plus cessation"),
    mechanism = "both",
    diseases = c("CHD", "Stroke"),
    risk_factors = "Smoking",
    risk_categories = list(Smoking = c("Never", "Current", "Former")),
    ages = age_bands(20, 30, by = 5),
    sexes = c("male", "female"),
    strata = c("least_deprived", "most_deprived"),
    horizon = 2,
    cost_effectiveness = TRUE
  )

  templates <- pmslttools:::build_input_templates(spec)
  schemas <- pmslttools:::pmslt_input_schemas()

  for (template_name in names(templates)) {
    expect_true(template_name %in% names(schemas))
    expect_setequal(names(templates[[template_name]]), schemas[[template_name]]$columns$column)
  }

  rr_schema <- schemas[["09_relative_risks"]]$columns
  expect_equal(
    rr_schema$validation_type[rr_schema$column == "rr"],
    "positive_number"
  )

  dismod_schema <- schemas[["06_dismod_input_skeleton"]]$columns
  expect_match(
    dismod_schema$allowed_values[dismod_schema$column == "parameter"],
    "incidence",
    fixed = TRUE
  )
  expect_match(
    dismod_schema$allowed_values[dismod_schema$column == "parameter"],
    "mortality",
    fixed = TRUE
  )

  raw_disease_schema <- schemas[["05_disease_epidemiology_raw"]]$columns
  expect_true(all(c("age_start", "age_end", "age_label") %in% raw_disease_schema$column))
  expect_true("disease_mortality_rate" %in% raw_disease_schema$column)
  expect_equal(
    raw_disease_schema$validation_type[raw_disease_schema$column == "disease_mortality_rate"],
    "non_negative_rate"
  )
  expect_false("age" %in% raw_disease_schema$column)
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
  expect_true(any(grepl("disease-specific mortality evidence", guide, fixed = TRUE)))
  expect_true(any(grepl("must not be inferred from `excess_mortality`", guide, fixed = TRUE)))
  expect_true(any(grepl("`prevalence_intervention` *", guide, fixed = TRUE)))
  expect_true(any(grepl("Validation: proportion_0_1.", guide, fixed = TRUE)))
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
