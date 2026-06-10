lifetable_population <- function() {
  data.frame(
    age = c(40L, 41L),
    sex = c("female", "female"),
    stratum = c("total", "total"),
    population = c(1000, 800),
    stringsAsFactors = FALSE
  )
}

lifetable_mortality <- function() {
  data.frame(
    age = c(40L, 41L),
    sex = c("female", "female"),
    stratum = c("total", "total"),
    mortality_rate = c(0.01, 0.02),
    stringsAsFactors = FALSE
  )
}

lifetable_morbidity <- function() {
  data.frame(
    age = c(40L, 41L),
    sex = c("female", "female"),
    stratum = c("total", "total"),
    morbidity_rate = c(0.10, 0.20),
    stringsAsFactors = FALSE
  )
}

lifetable_disease_epi <- function(diseases = "CHD") {
  rows <- lapply(diseases, function(disease) {
    data.frame(
      age = c(40L, 41L),
      sex = "female",
      stratum = "total",
      disease = disease,
      time_step = 0L,
      incidence_BAU = c(0.01, 0.02),
      prevalence_initial = c(0.10, 0.20),
      remission_rate = 0,
      excess_mortality_BAU = c(0.02, 0.03),
      case_fatality_BAU = c(0.03, 0.04),
      disability_weight = c(0.20, 0.30),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  row.names(out) <- NULL
  out
}

lifetable_intervention_effects <- function(interventions = "Care pathway",
                                           diseases = "CHD",
                                           horizon = 1) {
  grid <- expand.grid(
    intervention = interventions,
    disease = diseases,
    time_step = seq_len(horizon) - 1L,
    age = c(40L, 41L),
    sex = "female",
    stratum = "total",
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  )
  grid$incidence_BAU <- ifelse(grid$age == 40L, 0.010, 0.020)
  grid$incidence_Int <- grid$incidence_BAU * 0.90
  grid$disease_mortality_BAU <- ifelse(grid$age == 40L, 0.006, 0.008)
  grid$disease_mortality_Int <- grid$disease_mortality_BAU - ifelse(grid$age == 40L, 0.002, 0.003)
  grid$disease_morbidity_BAU <- ifelse(grid$age == 40L, 0.020, 0.060)
  grid$disease_morbidity_Int <- grid$disease_morbidity_BAU - ifelse(grid$age == 40L, 0.010, 0.020)
  grid$delta_mortality <- grid$disease_mortality_Int - grid$disease_mortality_BAU
  grid$delta_morbidity <- grid$disease_morbidity_Int - grid$disease_morbidity_BAU
  grid
}

age_band_summary_spec <- function() {
  pmslt_spec(
    intervention = "Test",
    mechanism = "direct",
    diseases = c("CHD", "Stroke"),
    ages = age_bands(40, 45, by = 3, open_ended = FALSE),
    sexes = "female",
    strata = "total",
    horizon = 1
  )
}

age_band_lifetable_population <- function() {
  data.frame(
    age = 40:45,
    sex = "female",
    stratum = "total",
    population = c(1000, 900, 800, 700, 600, 500),
    stringsAsFactors = FALSE
  )
}

age_band_lifetable_mortality <- function() {
  data.frame(
    age = 40:45,
    sex = "female",
    stratum = "total",
    mortality_rate = seq(0.01, 0.06, by = 0.01),
    stringsAsFactors = FALSE
  )
}

age_band_lifetable_disease_epi <- function(diseases = "CHD") {
  rows <- lapply(diseases, function(disease) {
    data.frame(
      age = 40:45,
      sex = "female",
      stratum = "total",
      disease = disease,
      time_step = 0L,
      incidence_BAU = seq(0.01, 0.06, by = 0.01),
      prevalence_initial = seq(0.10, 0.35, by = 0.05),
      remission_rate = 0,
      excess_mortality_BAU = seq(0.02, 0.07, by = 0.01),
      case_fatality_BAU = seq(0.03, 0.08, by = 0.01),
      disability_weight = seq(0.20, 0.45, by = 0.05),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  row.names(out) <- NULL
  out
}

test_that("valid single-year inputs initialize deterministic lifetable quantities", {
  result <- initialize_pmslt_lifetable(lifetable_population(), lifetable_mortality())

  expect_s3_class(result, "pmslt_lifetable")
  expect_equal(result$time_step, c(0L, 0L))
  expect_equal(result$deaths, c(10, 16))
  expect_equal(result$alive_end, c(990, 784))
  expect_equal(result$person_years, c(995, 792))
  expect_equal(result$morbidity_rate, c(0, 0))
  expect_equal(result$yld_rate, result$morbidity_rate)
})

test_that("file path inputs and data frame inputs both work", {
  population_path <- tempfile(fileext = ".csv")
  mortality_path <- tempfile(fileext = ".csv")
  utils::write.csv(lifetable_population(), population_path, row.names = FALSE)
  utils::write.csv(lifetable_mortality(), mortality_path, row.names = FALSE)

  from_paths <- initialize_pmslt_lifetable(population_path, mortality_path)
  from_data <- initialize_pmslt_lifetable(lifetable_population(), lifetable_mortality())

  expect_equal(unclass(from_paths), unclass(from_data), ignore_attr = TRUE)
})

test_that("template-style all-cause input column names are accepted", {
  population <- lifetable_population()
  names(population)[names(population) == "population"] <- "initial_population"
  mortality <- lifetable_mortality()
  names(mortality)[names(mortality) == "mortality_rate"] <- "acmr_BAU"

  result <- initialize_pmslt_lifetable(population, mortality)

  expect_equal(result$population, c(1000, 800))
  expect_equal(result$mortality_rate, c(0.01, 0.02))
})

test_that("missing required columns produce clear errors", {
  population <- lifetable_population()
  population$population <- NULL

  expect_error(
    initialize_pmslt_lifetable(population, lifetable_mortality()),
    "population.*missing.*population"
  )
})

test_that("non-integer ages are rejected", {
  population <- lifetable_population()
  population$age[[1]] <- 40.5

  expect_error(
    initialize_pmslt_lifetable(population, lifetable_mortality()),
    "whole-number single-year age"
  )
})

test_that("negative population is rejected", {
  population <- lifetable_population()
  population$population[[1]] <- -1

  expect_error(
    initialize_pmslt_lifetable(population, lifetable_mortality()),
    "population.*non-negative"
  )
})

test_that("mortality_rate outside 0 to 1 is rejected", {
  mortality <- lifetable_mortality()
  mortality$mortality_rate[[1]] <- 1.2

  expect_error(
    initialize_pmslt_lifetable(lifetable_population(), mortality),
    "mortality_rate.*between 0 and 1"
  )
})

test_that("incomplete mortality joins are rejected", {
  mortality <- lifetable_mortality()[1, ]

  expect_error(
    initialize_pmslt_lifetable(lifetable_population(), mortality),
    "mortality.*missing rows for population keys"
  )
})

test_that("optional morbidity is joined when supplied", {
  morbidity <- data.frame(
    age = c(40L, 41L),
    sex = c("female", "female"),
    stratum = c("total", "total"),
    morbidity_rate = c(0.12, 0.15),
    stringsAsFactors = FALSE
  )

  result <- initialize_pmslt_lifetable(
    lifetable_population(),
    lifetable_mortality(),
    morbidity = morbidity
  )

  expect_equal(result$morbidity_rate, c(0.12, 0.15))
  expect_equal(result$yld_rate, c(0.12, 0.15))
})

test_that("incomplete morbidity joins are rejected when morbidity is supplied", {
  morbidity <- data.frame(
    age = 40L,
    sex = "female",
    stratum = "total",
    morbidity_rate = 0.12,
    stringsAsFactors = FALSE
  )

  expect_error(
    initialize_pmslt_lifetable(
      lifetable_population(),
      lifetable_mortality(),
      morbidity = morbidity
    ),
    "morbidity.*missing rows for population keys"
  )
})

test_that("horizon 1 BAU runner reproduces one-step initializer results", {
  one_step <- initialize_pmslt_lifetable(lifetable_population(), lifetable_mortality())
  bau <- run_pmslt_lifetable_bau(lifetable_population(), lifetable_mortality(), horizon = 1)

  expect_s3_class(bau, "pmslt_lifetable")
  expect_equal(
    bau[names(one_step)],
    one_step,
    ignore_attr = TRUE
  )
  expect_equal(bau$yld, c(0, 0))
})

test_that("horizon defaults to spec horizon when supplied", {
  spec <- pmslt_spec(
    intervention = "Test",
    mechanism = "risk_factor",
    diseases = "CHD",
    risk_factors = "Smoking",
    risk_categories = list(Smoking = c("Never", "Current")),
    ages = data.frame(age_start = 40, age_end = 41, age_label = "40-41"),
    sexes = "female",
    strata = "total",
    horizon = 2
  )

  bau <- run_pmslt_lifetable_bau(lifetable_population(), lifetable_mortality(), spec = spec)

  expect_equal(sort(unique(bau$time_step)), c(0L, 1L))
  expect_equal(attr(bau, "spec"), spec)
})

test_that("horizon greater than 1 ages survivors forward correctly", {
  population <- data.frame(
    age = c(40L, 41L, 42L),
    sex = "female",
    stratum = "total",
    population = c(100, 200, 300),
    stringsAsFactors = FALSE
  )
  mortality <- data.frame(
    age = c(40L, 41L, 42L),
    sex = "female",
    stratum = "total",
    mortality_rate = 0.1,
    stringsAsFactors = FALSE
  )

  bau <- run_pmslt_lifetable_bau(population, mortality, horizon = 3)
  t1 <- bau[bau$time_step == 1, ]
  t2 <- bau[bau$time_step == 2, ]

  expect_equal(t1$population[t1$age == 40], 0)
  expect_equal(t1$population[t1$age == 41], 90)
  expect_equal(t1$population[t1$age == 42], 450)
  expect_equal(t2$population[t2$age == 40], 0)
  expect_equal(t2$population[t2$age == 41], 0)
  expect_equal(t2$population[t2$age == 42], 486)
})

test_that("maximum age is retained as open-ended", {
  population <- data.frame(
    age = c(40L, 41L),
    sex = "female",
    stratum = "total",
    population = c(100, 200),
    stringsAsFactors = FALSE
  )
  mortality <- data.frame(
    age = c(40L, 41L),
    sex = "female",
    stratum = "total",
    mortality_rate = c(0, 0),
    stringsAsFactors = FALSE
  )

  bau <- run_pmslt_lifetable_bau(population, mortality, horizon = 2)
  t1 <- bau[bau$time_step == 1, ]

  expect_equal(t1$population[t1$age == 40], 0)
  expect_equal(t1$population[t1$age == 41], 300)
  expect_equal(attr(bau, "ageing_rule"), "open_ended_max_age")
})

test_that("static mortality rates are reused when time_step is absent", {
  population <- data.frame(
    age = c(40L, 41L),
    sex = "female",
    stratum = "total",
    population = c(100, 0),
    stringsAsFactors = FALSE
  )
  mortality <- data.frame(
    age = c(40L, 41L),
    sex = "female",
    stratum = "total",
    mortality_rate = c(0.1, 0.2),
    stringsAsFactors = FALSE
  )

  bau <- run_pmslt_lifetable_bau(population, mortality, horizon = 2)
  t1_age41 <- bau[bau$time_step == 1 & bau$age == 41, ]

  expect_equal(t1_age41$population, 90)
  expect_equal(t1_age41$mortality_rate, 0.2)
  expect_equal(t1_age41$deaths, 18)
})

test_that("time-varying mortality rates are matched by time_step", {
  population <- data.frame(
    age = c(40L, 41L),
    sex = "female",
    stratum = "total",
    population = c(100, 0),
    stringsAsFactors = FALSE
  )
  mortality <- data.frame(
    time_step = c(0L, 0L, 1L, 1L),
    age = c(40L, 41L, 40L, 41L),
    sex = "female",
    stratum = "total",
    mortality_rate = c(0.1, 0.2, 0.3, 0.4),
    stringsAsFactors = FALSE
  )

  bau <- run_pmslt_lifetable_bau(population, mortality, horizon = 2)
  t1_age41 <- bau[bau$time_step == 1 & bau$age == 41, ]

  expect_equal(t1_age41$population, 90)
  expect_equal(t1_age41$mortality_rate, 0.4)
  expect_equal(t1_age41$deaths, 36)
})

test_that("morbidity rates are joined and carried through each cycle", {
  population <- data.frame(
    age = c(40L, 41L),
    sex = "female",
    stratum = "total",
    population = c(100, 0),
    stringsAsFactors = FALSE
  )
  mortality <- data.frame(
    age = c(40L, 41L),
    sex = "female",
    stratum = "total",
    mortality_rate = c(0.1, 0.2),
    stringsAsFactors = FALSE
  )
  morbidity <- data.frame(
    time_step = c(0L, 0L, 1L, 1L),
    age = c(40L, 41L, 40L, 41L),
    sex = "female",
    stratum = "total",
    morbidity_rate = c(0.01, 0.02, 0.03, 0.04),
    stringsAsFactors = FALSE
  )

  bau <- run_pmslt_lifetable_bau(population, mortality, morbidity, horizon = 2)
  t1_age41 <- bau[bau$time_step == 1 & bau$age == 41, ]

  expect_equal(t1_age41$morbidity_rate, 0.04)
  expect_equal(t1_age41$yld_rate, 0.04)
  expect_equal(t1_age41$person_years, 81)
  expect_equal(t1_age41$yld, 81 * 0.04)
})

test_that("invalid horizon is rejected", {
  expect_error(
    run_pmslt_lifetable_bau(lifetable_population(), lifetable_mortality(), horizon = 1.5),
    "horizon.*positive whole number"
  )
  expect_error(
    run_pmslt_lifetable_bau(lifetable_population(), lifetable_mortality(), horizon = 0),
    "horizon.*positive whole number"
  )
})

test_that("incomplete time-varying rate joins are rejected", {
  mortality <- data.frame(
    time_step = c(0L, 0L, 1L),
    age = c(40L, 41L, 40L),
    sex = "female",
    stratum = "total",
    mortality_rate = c(0.01, 0.02, 0.03),
    stringsAsFactors = FALSE
  )

  expect_error(
    run_pmslt_lifetable_bau(lifetable_population(), mortality, horizon = 2),
    "mortality at time_step 1.*missing rows"
  )
})

test_that("no births migration or new entrants are introduced", {
  population <- data.frame(
    age = c(40L, 41L),
    sex = "female",
    stratum = "total",
    population = c(100, 0),
    stringsAsFactors = FALSE
  )
  mortality <- data.frame(
    age = c(40L, 41L),
    sex = "female",
    stratum = "total",
    mortality_rate = c(0, 0),
    stringsAsFactors = FALSE
  )

  bau <- run_pmslt_lifetable_bau(population, mortality, horizon = 3)

  expect_equal(bau$population[bau$time_step > 0 & bau$age == 40], c(0, 0))
  expect_equal(
    as.numeric(tapply(bau$population, bau$time_step, sum)),
    c(100, 100, 100)
  )
})

test_that("population ages must be consecutive single-year ages", {
  population <- data.frame(
    age = c(40L, 42L),
    sex = "female",
    stratum = "total",
    population = c(100, 200),
    stringsAsFactors = FALSE
  )
  mortality <- data.frame(
    age = c(40L, 42L),
    sex = "female",
    stratum = "total",
    mortality_rate = c(0.1, 0.2),
    stringsAsFactors = FALSE
  )

  expect_error(
    run_pmslt_lifetable_bau(population, mortality, horizon = 2),
    "consecutive single-year ages"
  )
})

test_that("single disease joins to BAU lifetable and preserves long disease output", {
  lifetable <- run_pmslt_lifetable_bau(lifetable_population(), lifetable_mortality(), horizon = 1)
  result <- integrate_disease_deltas(lifetable, lifetable_disease_epi())
  long <- attr(result, "disease_deltas")

  expect_s3_class(result, "pmslt_lifetable")
  expect_true(all(c("total_disease_cases", "total_disease_deaths", "total_disease_yld") %in% names(result)))
  expect_true(is.data.frame(long))
  expect_equal(long$disease, c("CHD", "CHD"))
  expect_equal(long$age, c(40L, 41L))
})

test_that("disease cases deaths and YLD use deterministic formulas", {
  lifetable <- run_pmslt_lifetable_bau(lifetable_population(), lifetable_mortality(), horizon = 1)
  disease_epi <- lifetable_disease_epi()

  result <- integrate_disease_deltas(lifetable, disease_epi)
  long <- attr(result, "disease_deltas")

  expect_equal(long$disease_cases, lifetable$person_years * disease_epi$incidence_BAU)
  expect_equal(
    long$disease_deaths,
    lifetable$person_years * disease_epi$prevalence_initial * disease_epi$case_fatality_BAU
  )
  expect_equal(
    long$disease_yld,
    lifetable$person_years * disease_epi$prevalence_initial * disease_epi$disability_weight
  )
  expect_equal(result$total_disease_cases, long$disease_cases)
  expect_equal(result$total_disease_deaths, long$disease_deaths)
  expect_equal(result$total_disease_yld, long$disease_yld)
})

test_that("multiple diseases aggregate to lifetable row totals", {
  lifetable <- run_pmslt_lifetable_bau(lifetable_population(), lifetable_mortality(), horizon = 1)
  disease_epi <- lifetable_disease_epi(c("CHD", "Stroke"))
  disease_epi$incidence_BAU[disease_epi$disease == "Stroke"] <- c(0.03, 0.04)
  disease_epi$case_fatality_BAU[disease_epi$disease == "Stroke"] <- c(0.05, 0.06)
  disease_epi$disability_weight[disease_epi$disease == "Stroke"] <- c(0.40, 0.50)

  result <- integrate_disease_deltas(lifetable, disease_epi)
  long <- attr(result, "disease_deltas")
  expected_cases <- as.numeric(tapply(long$disease_cases, long$age, sum))
  expected_deaths <- as.numeric(tapply(long$disease_deaths, long$age, sum))
  expected_yld <- as.numeric(tapply(long$disease_yld, long$age, sum))

  expect_equal(result$total_disease_cases, expected_cases)
  expect_equal(result$total_disease_deaths, expected_deaths)
  expect_equal(result$total_disease_yld, expected_yld)
})

test_that("incomplete disease and lifetable joins are rejected", {
  lifetable <- run_pmslt_lifetable_bau(lifetable_population(), lifetable_mortality(), horizon = 1)
  disease_epi <- lifetable_disease_epi()
  disease_epi <- disease_epi[disease_epi$age == 40L, ]

  expect_error(
    integrate_disease_deltas(lifetable, disease_epi),
    "missing disease rows for a lifetable row"
  )
})

test_that("invalid disease inputs are rejected by existing disease validation", {
  lifetable <- run_pmslt_lifetable_bau(lifetable_population(), lifetable_mortality(), horizon = 1)
  disease_epi <- lifetable_disease_epi()
  disease_epi$incidence_BAU[[1]] <- -0.01

  expect_error(
    integrate_disease_deltas(lifetable, disease_epi),
    "non-negative",
    fixed = TRUE
  )
})

test_that("intervention disease effects bridge into adjusted all-cause lifetable rates", {
  result <- run_pmslt_lifetable_interventions(
    lifetable_population(),
    lifetable_mortality(),
    lifetable_morbidity(),
    intervention_effects = lifetable_intervention_effects(),
    horizon = 1
  )
  intervention <- result$interventions[["Care pathway"]]
  comparison <- result$comparisons[["Care pathway"]]
  long <- attr(intervention, "disease_deltas")

  expect_s3_class(intervention, "pmslt_lifetable")
  expect_equal(intervention$mortality_rate, lifetable_mortality()$mortality_rate + c(-0.002, -0.003))
  expect_equal(intervention$morbidity_rate, lifetable_morbidity()$morbidity_rate + c(-0.010, -0.020))
  expect_equal(intervention$deaths, intervention$population * intervention$mortality_rate)
  expect_equal(intervention$person_years, intervention$population - 0.5 * intervention$deaths)
  expect_equal(intervention$yld, intervention$person_years * intervention$morbidity_rate)
  expect_true(comparison$deaths_difference < 0)
  expect_true(is.data.frame(long))
  expect_equal(long$scenario, c("Care pathway", "Care pathway"))
})

test_that("intervention disease deltas aggregate across multiple diseases and arms", {
  effects <- lifetable_intervention_effects(
    interventions = c("Care pathway", "Care pathway plus prevention"),
    diseases = c("CHD", "Stroke"),
    horizon = 1
  )
  effects$delta_mortality[effects$disease == "Stroke"] <- effects$delta_mortality[effects$disease == "Stroke"] / 2
  effects$disease_mortality_Int <- effects$disease_mortality_BAU + effects$delta_mortality

  result <- run_pmslt_lifetable_interventions(
    lifetable_population(),
    lifetable_mortality(),
    lifetable_morbidity(),
    intervention_effects = effects,
    horizon = 1
  )
  intervention <- result$interventions[["Care pathway"]]

  expected_delta <- as.numeric(tapply(
    effects$delta_mortality[effects$intervention == "Care pathway"],
    effects$age[effects$intervention == "Care pathway"],
    sum
  ))
  expect_equal(names(result$interventions), c("Care pathway", "Care pathway plus prevention"))
  expect_equal(intervention$total_delta_mortality, expected_delta)
  expect_true(all(c("total_disease_cases", "total_disease_deaths", "total_disease_yld") %in% names(intervention)))
})

test_that("intervention lifetable ageing uses intervention survivors", {
  population <- data.frame(
    age = c(40L, 41L),
    sex = "female",
    stratum = "total",
    population = c(100, 0),
    stringsAsFactors = FALSE
  )
  mortality <- data.frame(
    age = c(40L, 41L),
    sex = "female",
    stratum = "total",
    mortality_rate = c(0.1, 0.2),
    stringsAsFactors = FALSE
  )
  effects <- lifetable_intervention_effects(horizon = 2)
  effects$delta_mortality <- ifelse(effects$time_step == 0 & effects$age == 40L, -0.05, 0)
  effects$disease_mortality_BAU <- 0.06
  effects$disease_mortality_Int <- effects$disease_mortality_BAU + effects$delta_mortality

  result <- run_pmslt_lifetable_interventions(
    population,
    mortality,
    intervention_effects = effects,
    horizon = 2
  )
  t1_age41 <- result$interventions[["Care pathway"]][
    result$interventions[["Care pathway"]]$time_step == 1 &
      result$interventions[["Care pathway"]]$age == 41,
  ]

  expect_equal(t1_age41$population, 95)
})

test_that("overall BAU summary totals all-cause lifetable metrics", {
  bau <- run_pmslt_lifetable_bau(lifetable_population(), lifetable_mortality(), horizon = 1)

  summary <- summarise_pmslt_results(bau)

  expect_s3_class(summary, "data.frame")
  expect_equal(names(summary), c("population", "deaths", "person_years", "yld"))
  expect_equal(summary$population, sum(bau$population))
  expect_equal(summary$deaths, sum(bau$deaths))
  expect_equal(summary$person_years, sum(bau$person_years))
  expect_equal(summary$yld, sum(bau$yld))
})

test_that("BAU summary can group by time_step", {
  bau <- run_pmslt_lifetable_bau(lifetable_population(), lifetable_mortality(), horizon = 2)

  summary <- summarise_pmslt_results(bau, by = "time_step")
  expected_population <- as.numeric(tapply(bau$population, bau$time_step, sum))

  expect_equal(names(summary), c("time_step", "population", "deaths", "person_years", "yld"))
  expect_equal(summary$time_step, c(0L, 1L))
  expect_equal(summary$population, expected_population)
})

test_that("BAU summary can group by sex and stratum", {
  population <- data.frame(
    age = c(40L, 40L, 40L),
    sex = c("female", "male", "female"),
    stratum = c("low", "low", "high"),
    population = c(100, 200, 300),
    stringsAsFactors = FALSE
  )
  mortality <- data.frame(
    age = c(40L, 40L, 40L),
    sex = c("female", "male", "female"),
    stratum = c("low", "low", "high"),
    mortality_rate = c(0.01, 0.02, 0.03),
    stringsAsFactors = FALSE
  )
  bau <- run_pmslt_lifetable_bau(population, mortality, horizon = 1)

  summary <- summarise_pmslt_results(bau, by = c("sex", "stratum"))

  expect_equal(names(summary), c("sex", "stratum", "population", "deaths", "person_years", "yld"))
  expect_equal(sum(summary$population), sum(population$population))
  expect_equal(summary$population[summary$sex == "female" & summary$stratum == "high"], 300)
  expect_equal(summary$population[summary$sex == "female" & summary$stratum == "low"], 100)
  expect_equal(summary$population[summary$sex == "male" & summary$stratum == "low"], 200)
})

test_that("BAU summary can group by exact age", {
  bau <- run_pmslt_lifetable_bau(lifetable_population(), lifetable_mortality(), horizon = 1)

  summary <- summarise_pmslt_results(bau, by = "age")

  expect_equal(names(summary), c("age", "population", "deaths", "person_years", "yld"))
  expect_equal(summary$age, c(40L, 41L))
  expect_equal(summary$population, lifetable_population()$population)
})

test_that("BAU summary can group by configured age bands", {
  spec <- age_band_summary_spec()
  bau <- run_pmslt_lifetable_bau(
    age_band_lifetable_population(),
    age_band_lifetable_mortality(),
    spec = spec
  )

  summary <- summarise_pmslt_results(bau, group_by = "age_band")

  expect_equal(names(summary), c("age_band", "population", "deaths", "person_years", "yld"))
  expect_equal(summary$age_band, c("40-42", "43-45"))
  expect_equal(summary$population, c(2700, 1800))
})

test_that("age-band BAU totals equal exact-age totals when summed", {
  spec <- age_band_summary_spec()
  bau <- run_pmslt_lifetable_bau(
    age_band_lifetable_population(),
    age_band_lifetable_mortality(),
    spec = spec
  )

  exact_age <- summarise_pmslt_results(bau, by = "age")
  age_band <- summarise_pmslt_results(bau, by = "age_band")

  expect_equal(sum(age_band$population), sum(exact_age$population))
  expect_equal(sum(age_band$deaths), sum(exact_age$deaths))
  expect_equal(sum(age_band$person_years), sum(exact_age$person_years))
  expect_equal(sum(age_band$yld), sum(exact_age$yld))
})

test_that("integrated disease totals are included in non-disease summaries", {
  lifetable <- run_pmslt_lifetable_bau(lifetable_population(), lifetable_mortality(), horizon = 1)
  integrated <- integrate_disease_deltas(lifetable, lifetable_disease_epi(c("CHD", "Stroke")))

  summary <- summarise_pmslt_results(integrated)

  expect_true(all(c("total_disease_cases", "total_disease_deaths", "total_disease_yld") %in% names(summary)))
  expect_equal(summary$total_disease_cases, sum(integrated$total_disease_cases))
  expect_equal(summary$total_disease_deaths, sum(integrated$total_disease_deaths))
  expect_equal(summary$total_disease_yld, sum(integrated$total_disease_yld))
})

test_that("disease-specific summary uses disease_deltas attribute", {
  lifetable <- run_pmslt_lifetable_bau(lifetable_population(), lifetable_mortality(), horizon = 1)
  integrated <- integrate_disease_deltas(lifetable, lifetable_disease_epi(c("CHD", "Stroke")))
  disease_deltas <- attr(integrated, "disease_deltas")

  summary <- summarise_pmslt_results(integrated, by = "disease")
  expected_cases <- as.numeric(tapply(disease_deltas$disease_cases, disease_deltas$disease, sum))

  expect_equal(names(summary), c("disease", "disease_cases", "disease_deaths", "disease_yld"))
  expect_equal(summary$disease, c("CHD", "Stroke"))
  expect_equal(summary$disease_cases, expected_cases)
})

test_that("integrated disease summaries can group by age band", {
  spec <- age_band_summary_spec()
  lifetable <- run_pmslt_lifetable_bau(
    age_band_lifetable_population(),
    age_band_lifetable_mortality(),
    spec = spec
  )
  integrated <- integrate_disease_deltas(
    lifetable,
    age_band_lifetable_disease_epi(c("CHD", "Stroke"))
  )

  summary <- summarise_pmslt_results(integrated, by = "age_band")
  exact_age <- summarise_pmslt_results(integrated, by = "age")

  expect_equal(
    names(summary),
    c(
      "age_band", "population", "deaths", "person_years", "yld",
      "total_disease_cases", "total_disease_deaths", "total_disease_yld"
    )
  )
  expect_equal(summary$age_band, c("40-42", "43-45"))
  expect_equal(sum(summary$total_disease_cases), sum(exact_age$total_disease_cases))
  expect_equal(sum(summary$total_disease_deaths), sum(exact_age$total_disease_deaths))
  expect_equal(sum(summary$total_disease_yld), sum(exact_age$total_disease_yld))
})

test_that("disease-specific summaries can group by disease and age band", {
  spec <- age_band_summary_spec()
  lifetable <- run_pmslt_lifetable_bau(
    age_band_lifetable_population(),
    age_band_lifetable_mortality(),
    spec = spec
  )
  integrated <- integrate_disease_deltas(
    lifetable,
    age_band_lifetable_disease_epi(c("CHD", "Stroke"))
  )
  exact_age <- summarise_pmslt_results(integrated, by = c("disease", "age"))

  summary <- summarise_pmslt_results(integrated, by = c("disease", "age_band"))

  expect_equal(names(summary), c("disease", "age_band", "disease_cases", "disease_deaths", "disease_yld"))
  expect_equal(sort(unique(summary$age_band)), c("40-42", "43-45"))
  expect_equal(sum(summary$disease_cases), sum(exact_age$disease_cases))
  expect_equal(sum(summary$disease_deaths), sum(exact_age$disease_deaths))
  expect_equal(sum(summary$disease_yld), sum(exact_age$disease_yld))
})

test_that("requesting disease summary without disease_deltas gives clear error", {
  bau <- run_pmslt_lifetable_bau(lifetable_population(), lifetable_mortality(), horizon = 1)

  expect_error(
    summarise_pmslt_results(bau, by = "disease"),
    "Run `integrate_disease_deltas\\(\\)` first"
  )
})

test_that("missing age-band information gives clear error", {
  bau <- run_pmslt_lifetable_bau(lifetable_population(), lifetable_mortality(), horizon = 1)

  expect_error(
    summarise_pmslt_results(bau, by = "age_band"),
    "does not include age-band information"
  )
})

test_that("invalid summary grouping variable gives clear error", {
  bau <- run_pmslt_lifetable_bau(lifetable_population(), lifetable_mortality(), horizon = 1)

  expect_error(
    summarise_pmslt_results(bau, by = "calendar_year"),
    "Unknown summary grouping variable"
  )
})

test_that("overall comparison returns intervention minus BAU deltas", {
  bau <- run_pmslt_lifetable_bau(lifetable_population(), lifetable_mortality(), horizon = 1)
  intervention <- bau
  intervention$population <- intervention$population - c(10, 20)
  intervention$deaths <- intervention$deaths - c(1, 2)
  intervention$person_years <- intervention$person_years - c(9, 18)
  intervention$yld <- intervention$yld + c(0.5, 1.5)

  comparison <- compare_pmslt_results(bau, intervention)

  expect_equal(
    names(comparison),
    c("population_difference", "deaths_difference", "person_years_difference", "yld_difference")
  )
  expect_equal(comparison$population_difference, -30)
  expect_equal(comparison$deaths_difference, -3)
  expect_equal(comparison$person_years_difference, -27)
  expect_equal(comparison$yld_difference, 2)
})

test_that("age-band comparison aggregates reporting differences", {
  spec <- age_band_summary_spec()
  bau <- run_pmslt_lifetable_bau(
    age_band_lifetable_population(),
    age_band_lifetable_mortality(),
    spec = spec
  )
  intervention <- bau
  intervention$population <- intervention$population - c(1, 2, 3, 4, 5, 6)
  intervention$deaths <- intervention$deaths - 1
  intervention$person_years <- intervention$person_years - 2
  intervention$yld <- intervention$yld

  comparison <- compare_pmslt_results(bau, intervention, by = "age_band")

  expect_equal(names(comparison), c("age_band", "population_difference", "deaths_difference", "person_years_difference", "yld_difference"))
  expect_equal(comparison$age_band, c("40-42", "43-45"))
  expect_equal(comparison$population_difference, c(-6, -15))
  expect_equal(comparison$deaths_difference, c(-3, -3))
  expect_equal(comparison$person_years_difference, c(-6, -6))
})

test_that("comparison can group by sex and stratum", {
  population <- data.frame(
    age = c(40L, 40L, 40L),
    sex = c("female", "male", "female"),
    stratum = c("low", "low", "high"),
    population = c(100, 200, 300),
    stringsAsFactors = FALSE
  )
  mortality <- data.frame(
    age = c(40L, 40L, 40L),
    sex = c("female", "male", "female"),
    stratum = c("low", "low", "high"),
    mortality_rate = c(0.01, 0.02, 0.03),
    stringsAsFactors = FALSE
  )
  bau <- run_pmslt_lifetable_bau(population, mortality, horizon = 1)
  intervention <- bau
  intervention$population <- intervention$population + c(1, 2, 3)
  intervention$deaths <- intervention$deaths
  intervention$person_years <- intervention$person_years
  intervention$yld <- intervention$yld

  comparison <- compare_pmslt_results(bau, intervention, by = c("sex", "stratum"))

  expect_equal(names(comparison), c("sex", "stratum", "population_difference", "deaths_difference", "person_years_difference", "yld_difference"))
  expect_equal(sum(comparison$population_difference), 6)
  expect_equal(comparison$population_difference[comparison$sex == "female" & comparison$stratum == "high"], 1)
  expect_equal(comparison$population_difference[comparison$sex == "female" & comparison$stratum == "low"], 2)
  expect_equal(comparison$population_difference[comparison$sex == "male" & comparison$stratum == "low"], 3)
})

test_that("mismatched comparison structures fail clearly", {
  bau <- run_pmslt_lifetable_bau(lifetable_population(), lifetable_mortality(), horizon = 1)
  intervention <- bau[1, , drop = FALSE]

  expect_error(
    compare_pmslt_results(bau, intervention),
    "missing a row found in `bau_results`"
  )
})

test_that("disease totals compare correctly", {
  lifetable <- run_pmslt_lifetable_bau(lifetable_population(), lifetable_mortality(), horizon = 1)
  bau <- integrate_disease_deltas(lifetable, lifetable_disease_epi(c("CHD", "Stroke")))
  intervention <- bau
  intervention$total_disease_cases <- intervention$total_disease_cases - c(10, 20)
  intervention$total_disease_deaths <- intervention$total_disease_deaths - c(1, 2)
  intervention$total_disease_yld <- intervention$total_disease_yld + c(3, 4)

  comparison <- compare_pmslt_results(bau, intervention)

  expect_true(all(c(
    "total_disease_cases_difference",
    "total_disease_deaths_difference",
    "total_disease_yld_difference"
  ) %in% names(comparison)))
  expect_equal(comparison$total_disease_cases_difference, -30)
  expect_equal(comparison$total_disease_deaths_difference, -3)
  expect_equal(comparison$total_disease_yld_difference, 7)
})

test_that("comparison returns zero deltas for identical inputs", {
  lifetable <- run_pmslt_lifetable_bau(lifetable_population(), lifetable_mortality(), horizon = 1)
  integrated <- integrate_disease_deltas(lifetable, lifetable_disease_epi(c("CHD", "Stroke")))

  comparison <- compare_pmslt_results(integrated, integrated, by = "age")

  difference_cols <- grep("_difference$", names(comparison), value = TRUE)
  expect_true(length(difference_cols) > 0)
  expect_true(all(unlist(comparison[difference_cols], use.names = FALSE) == 0))
})

test_that("HALY summaries calculate person-years minus YLD", {
  bau <- run_pmslt_lifetable_bau(
    lifetable_population(),
    lifetable_mortality(),
    lifetable_morbidity(),
    horizon = 1
  )

  halys <- calculate_halys(bau)

  expect_equal(names(halys), c("halys", "person_years", "yld"))
  expect_equal(halys$person_years, sum(bau$person_years))
  expect_equal(halys$yld, sum(bau$yld))
  expect_equal(halys$halys, sum(bau$person_years) - sum(bau$yld))
})

test_that("HALY summaries can group by sex and stratum", {
  population <- data.frame(
    age = c(40L, 40L, 40L),
    sex = c("female", "male", "female"),
    stratum = c("low", "low", "high"),
    population = c(100, 200, 300),
    stringsAsFactors = FALSE
  )
  mortality <- data.frame(
    age = c(40L, 40L, 40L),
    sex = c("female", "male", "female"),
    stratum = c("low", "low", "high"),
    mortality_rate = c(0.01, 0.02, 0.03),
    stringsAsFactors = FALSE
  )
  morbidity <- data.frame(
    age = c(40L, 40L, 40L),
    sex = c("female", "male", "female"),
    stratum = c("low", "low", "high"),
    morbidity_rate = c(0.10, 0.20, 0.30),
    stringsAsFactors = FALSE
  )
  bau <- run_pmslt_lifetable_bau(population, mortality, morbidity, horizon = 1)

  halys <- calculate_halys(bau, by = c("sex", "stratum"))

  expect_equal(names(halys), c("sex", "stratum", "halys", "person_years", "yld"))
  expect_equal(sum(halys$halys), sum(bau$person_years) - sum(bau$yld))
  expect_equal(
    halys$halys[halys$sex == "female" & halys$stratum == "high"],
    bau$person_years[bau$stratum == "high"] - bau$yld[bau$stratum == "high"]
  )
})

test_that("HALY summaries can group by configured age bands", {
  spec <- age_band_summary_spec()
  morbidity <- age_band_lifetable_mortality()
  names(morbidity)[names(morbidity) == "mortality_rate"] <- "morbidity_rate"
  morbidity$morbidity_rate <- seq(0.01, 0.06, by = 0.01)
  bau <- run_pmslt_lifetable_bau(
    age_band_lifetable_population(),
    age_band_lifetable_mortality(),
    morbidity,
    spec = spec
  )

  halys <- calculate_halys(bau, by = "age_band")

  expect_equal(names(halys), c("age_band", "halys", "person_years", "yld"))
  expect_equal(halys$age_band, c("40-42", "43-45"))
  expect_equal(sum(halys$halys), sum(bau$person_years) - sum(bau$yld))
})

test_that("HALY summaries preserve integrated disease totals", {
  lifetable <- run_pmslt_lifetable_bau(
    lifetable_population(),
    lifetable_mortality(),
    lifetable_morbidity(),
    horizon = 1
  )
  integrated <- integrate_disease_deltas(lifetable, lifetable_disease_epi(c("CHD", "Stroke")))

  halys <- calculate_halys(integrated)

  expect_equal(
    names(halys),
    c("halys", "person_years", "yld", "total_disease_cases", "total_disease_deaths", "total_disease_yld")
  )
  expect_equal(halys$total_disease_yld, sum(integrated$total_disease_yld))
})

test_that("HALY comparison returns intervention minus BAU differences", {
  bau <- run_pmslt_lifetable_bau(
    lifetable_population(),
    lifetable_mortality(),
    lifetable_morbidity(),
    horizon = 1
  )
  intervention <- bau
  intervention$person_years <- intervention$person_years + c(10, 20)
  intervention$yld <- intervention$yld - c(1, 2)

  comparison <- compare_halys(bau, intervention)

  expect_equal(names(comparison), c("haly_difference", "person_years_difference", "yld_difference"))
  expect_equal(comparison$person_years_difference, 30)
  expect_equal(comparison$yld_difference, -3)
  expect_equal(comparison$haly_difference, 33)
})

test_that("HALY comparison returns zero differences for identical inputs", {
  bau <- run_pmslt_lifetable_bau(
    lifetable_population(),
    lifetable_mortality(),
    lifetable_morbidity(),
    horizon = 1
  )

  comparison <- compare_halys(bau, bau, by = "age")

  difference_cols <- grep("_difference$", names(comparison), value = TRUE)
  expect_true(all(unlist(comparison[difference_cols], use.names = FALSE) == 0))
})

test_that("HALY calculation requires YLD data", {
  one_step <- initialize_pmslt_lifetable(lifetable_population(), lifetable_mortality())

  expect_error(
    calculate_halys(one_step),
    "Cannot calculate HALYs.*`yld` is missing"
  )
})
