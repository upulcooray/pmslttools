test_that("cost schema validates required economic fields", {
  spec <- pmslt_spec(
    intervention = "Screening",
    mechanism = "direct",
    diseases = "CHD",
    ages = age_bands(40, 42, by = 2, open_ended = FALSE),
    sexes = "female",
    strata = "total",
    horizon = 1,
    cost_effectiveness = TRUE
  )
  costs <- pmslttools:::build_input_templates(spec)[["12_costs"]]
  costs$disease_cost <- 200
  costs$background_cost <- 100
  costs$currency <- "aud"
  costs$price_year <- 2024
  costs$source <- "Unit test"

  issues <- validate_cost_inputs(costs, spec)

  expect_s3_class(issues, "pmslt_validation_issues")
  expect_true(any(issues$column == "currency" & grepl("three-letter currency code", issues$message)))
})

test_that("cost validation catches inconsistent repeated fields", {
  costs <- data.frame(
    age_start = c(40, 40),
    age_end = c(41, 41),
    age_label = c("40-41", "40-41"),
    sex = c("female", "female"),
    stratum = c("total", "total"),
    disease = c("CHD", "Stroke"),
    disease_cost = c(200, 300),
    background_cost = c(100, 120),
    currency = c("AUD", "NZD"),
    price_year = c(2024, 2025),
    source = c("Unit test", "Unit test"),
    notes = c("", ""),
    stringsAsFactors = FALSE
  )

  issues <- validate_cost_inputs(costs)

  expect_true(any(issues$column == "background_cost" & grepl("differs across disease rows", issues$message)))
  expect_true(any(issues$column == "currency" & grepl("inconsistent", issues$message)))
  expect_true(any(issues$column == "price_year" & grepl("inconsistent", issues$message)))
})

test_that("costs attach to lifetable rows and summarise overall and by disease", {
  population <- data.frame(
    age = c(40L, 41L),
    sex = "female",
    stratum = "total",
    population = c(1000, 900)
  )
  mortality <- data.frame(
    age = c(40L, 41L),
    sex = "female",
    stratum = "total",
    mortality_rate = c(0.01, 0.02)
  )
  spec <- pmslt_spec(
    intervention = "Screening",
    mechanism = "direct",
    diseases = "CHD",
    ages = age_bands(40, 42, by = 2, open_ended = FALSE),
    sexes = "female",
    strata = "total",
    horizon = 1
  )
  lifetable <- run_pmslt_lifetable_bau(population, mortality, horizon = 1, spec = spec)
  disease_epi <- data.frame(
    time_step = 0L,
    age = c(40L, 41L),
    sex = "female",
    stratum = "total",
    disease = "CHD",
    incidence_BAU = 0.01,
    prevalence_initial = 0.10,
    remission_rate = 0,
    excess_mortality_BAU = 0.01,
    case_fatality_BAU = 0.02,
    disability_weight = 0.20,
    stringsAsFactors = FALSE
  )
  integrated <- integrate_disease_deltas(lifetable, disease_epi)
  costs <- data.frame(
    age_start = 40,
    age_end = 41,
    age_label = "40-41",
    sex = "female",
    stratum = "total",
    disease = "CHD",
    disease_cost = 200,
    background_cost = 100,
    currency = "AUD",
    price_year = 2024,
    source = "Unit test",
    notes = "",
    stringsAsFactors = FALSE
  )

  costed <- attach_pmslt_costs(integrated, costs, spec = spec)
  overall <- summarise_pmslt_costs(costed)
  by_disease <- summarise_pmslt_costs(costed, by = c("time_step", "sex", "stratum", "disease"))

  expected_person_years <- sum(lifetable$person_years)
  expected_disease_costs <- expected_person_years * 0.10 * 200
  expected_background_costs <- expected_person_years * 100
  expect_equal(overall$background_costs, expected_background_costs)
  expect_equal(overall$total_disease_costs, expected_disease_costs)
  expect_equal(overall$total_costs, expected_background_costs + expected_disease_costs)
  expect_equal(overall$currency, "AUD")
  expect_equal(overall$price_year, 2024)
  expect_equal(by_disease$disease, "CHD")
  expect_equal(by_disease$disease_costs, expected_disease_costs)
})

test_that("cost comparison reports intervention minus BAU", {
  population <- data.frame(
    age = c(40L, 41L),
    sex = "female",
    stratum = "total",
    population = c(1000, 900)
  )
  mortality <- data.frame(
    age = c(40L, 41L),
    sex = "female",
    stratum = "total",
    mortality_rate = c(0.01, 0.02)
  )
  lifetable <- run_pmslt_lifetable_bau(population, mortality, horizon = 1)
  costs <- data.frame(
    age_start = 40,
    age_end = 41,
    age_label = "40-41",
    sex = "female",
    stratum = "total",
    disease = "CHD",
    disease_cost = 200,
    background_cost = 100,
    currency = "AUD",
    price_year = 2024,
    source = "Unit test",
    notes = "",
    stringsAsFactors = FALSE
  )
  bau <- attach_pmslt_costs(lifetable, costs)
  intervention <- bau
  intervention$background_costs <- intervention$background_costs + 5
  intervention$total_costs <- intervention$total_costs + 5

  comparison <- compare_pmslt_costs(bau, intervention)

  expect_equal(comparison$background_costs_difference, 10)
  expect_equal(comparison$total_costs_difference, 10)
  expect_equal(comparison$total_disease_costs_difference, 0)
  expect_equal(comparison$currency, "AUD")
  expect_equal(comparison$price_year, 2024)
})
