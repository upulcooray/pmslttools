test_that("prepare_lifetable_inputs expands bands to exact ages and preserves totals", {
  out <- tempfile("pmslt_inputs_")
  generate_mock_pmslt_inputs(output_dir = out)

  inputs <- prepare_lifetable_inputs(input_dir = out)

  # Exact single-year ages with no band columns left behind.
  expect_true("age" %in% names(inputs$population))
  expect_false(any(c("age_start", "age_end", "age_label") %in% names(inputs$population)))
  ages <- sort(unique(inputs$population$age))
  expect_equal(ages, seq(min(ages), max(ages)))

  # Population counts are split uniformly, so the band total is preserved.
  raw_total <- sum(utils::read.csv(file.path(out, "01_population.csv"))$initial_population)
  expect_equal(sum(inputs$population$initial_population), raw_total)

  # Rates are constant within each source band.
  raw_mort <- utils::read.csv(file.path(out, "02_all_cause_mortality.csv"))
  band1 <- raw_mort[1, ]
  expanded_band1 <- inputs$mortality[
    inputs$mortality$sex == band1$sex &
      inputs$mortality$stratum == band1$stratum &
      inputs$mortality$age >= band1$age_start &
      inputs$mortality$age <= band1$age_end,
  ]
  expect_true(all(expanded_band1$acmr_BAU == band1$acmr_BAU))
})

test_that("prepare_lifetable_inputs leaves exact-age inputs unchanged", {
  population <- data.frame(
    age = c(40L, 41L),
    sex = "female",
    stratum = "total",
    population = c(1000, 900),
    stringsAsFactors = FALSE
  )
  mortality <- data.frame(
    age = c(40L, 41L),
    sex = "female",
    stratum = "total",
    mortality_rate = c(0.01, 0.02),
    stringsAsFactors = FALSE
  )

  inputs <- prepare_lifetable_inputs(population = population, mortality = mortality)

  expect_equal(inputs$population, population)
  expect_equal(inputs$mortality, mortality)
  expect_null(inputs$morbidity)
})

test_that("prepare_lifetable_inputs rejects overlapping bands", {
  population <- data.frame(
    age_start = c(40L, 45L),
    age_end = c(50L, 55L),
    sex = "female",
    stratum = "total",
    initial_population = c(1000, 1000),
    stringsAsFactors = FALSE
  )

  expect_error(
    prepare_lifetable_inputs(population = population, mortality = population),
    "overlapping age bands"
  )
})
