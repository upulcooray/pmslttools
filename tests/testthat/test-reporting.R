reporting_cost_rows <- function() {
  data.frame(
    time_step = c(0L, 0L, 0L, 0L),
    age = c(40L, 41L, 42L, 43L),
    sex = c("female", "female", "male", "male"),
    stratum = c("low", "low", "high", "high"),
    total_cost = c(100, 200, 300, 400),
    disease_cost = c(10, 20, 30, 40),
    stringsAsFactors = FALSE
  )
}

reporting_age_band_spec <- function() {
  pmslt_spec(
    intervention = "Reporting",
    mechanism = "direct",
    diseases = "CHD",
    ages = age_bands(40, 43, by = 2, open_ended = FALSE),
    sexes = c("female", "male"),
    strata = c("low", "high"),
    horizon = 1
  )
}

test_that("cost summaries total detected cost columns overall", {
  costs <- reporting_cost_rows()

  summary <- summarise_costs(costs)

  expect_equal(names(summary), c("total_cost", "disease_cost"))
  expect_equal(summary$total_cost, sum(costs$total_cost))
  expect_equal(summary$disease_cost, sum(costs$disease_cost))
})

test_that("cost summaries group by common reporting groups", {
  costs <- reporting_cost_rows()

  summary <- summarise_costs(costs, by = c("sex", "stratum"))

  expect_equal(names(summary), c("sex", "stratum", "total_cost", "disease_cost"))
  expect_equal(sum(summary$total_cost), sum(costs$total_cost))
  expect_equal(summary$total_cost[summary$sex == "female" & summary$stratum == "low"], 300)
  expect_equal(summary$total_cost[summary$sex == "male" & summary$stratum == "high"], 700)
})

test_that("cost summaries support reporting-only age bands", {
  costs <- reporting_cost_rows()

  summary <- summarise_costs(costs, by = "age_band", spec = reporting_age_band_spec())

  expect_equal(names(summary), c("age_band", "total_cost", "disease_cost"))
  expect_equal(summary$age_band, c("40-41", "42-43"))
  expect_equal(summary$total_cost, c(300, 700))
})

test_that("generic PMSLT summaries include costs when lifetable outputs carry cost columns", {
  population <- data.frame(
    age = c(40L, 41L),
    sex = "female",
    stratum = "total",
    population = c(1000, 800),
    stringsAsFactors = FALSE
  )
  mortality <- data.frame(
    age = c(40L, 41L),
    sex = "female",
    stratum = "total",
    mortality_rate = c(0.01, 0.02),
    stringsAsFactors = FALSE
  )
  bau <- run_pmslt_lifetable_bau(population, mortality, horizon = 1)
  bau$total_cost <- c(100, 200)

  summary <- summarise_pmslt_results(bau)

  expect_true("total_cost" %in% names(summary))
  expect_equal(summary$total_cost, 300)
})

test_that("cost comparison uses intervention minus BAU convention", {
  bau <- reporting_cost_rows()
  intervention <- bau
  intervention$total_cost <- intervention$total_cost + c(5, 10, -20, -30)
  intervention$disease_cost <- intervention$disease_cost + c(1, 2, 3, 4)

  comparison <- compare_costs(bau, intervention, by = "sex")

  expect_equal(names(comparison), c("sex", "total_cost_difference", "disease_cost_difference"))
  expect_equal(comparison$total_cost_difference[comparison$sex == "female"], 15)
  expect_equal(comparison$total_cost_difference[comparison$sex == "male"], -50)
  expect_equal(sum(comparison$disease_cost_difference), 10)
})

test_that("cost comparison rejects incompatible BAU and intervention structures", {
  bau <- reporting_cost_rows()
  intervention <- bau[-1, , drop = FALSE]

  expect_error(
    compare_costs(bau, intervention),
    "missing a row found in `bau_results`"
  )
})

test_that("ICER calculation requires both incremental costs and incremental HALYs", {
  expect_error(
    calculate_icers(data.frame(total_cost_difference = 100)),
    "no incremental HALY column"
  )
  expect_error(
    calculate_icers(data.frame(haly_difference = 2)),
    "no incremental cost column"
  )
})

test_that("ICER calculation reports positive zero and negative HALY cases explicitly", {
  incremental <- data.frame(
    group = c("A", "B", "C"),
    total_cost_difference = c(100, 50, -25),
    haly_difference = c(2, 0, -1),
    stringsAsFactors = FALSE
  )

  icers <- calculate_icers(incremental)

  expect_equal(icers$icer, c(50, NA_real_, NA_real_))
  expect_equal(
    icers$icer_status,
    c("positive_incremental_halys", "zero_incremental_halys", "negative_incremental_halys")
  )
})
