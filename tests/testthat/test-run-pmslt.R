# Build a mock input directory plus exact-age main-lifetable inputs derived from
# the mock disease epidemiology, mirroring the documented intervention bridge.
run_pmslt_fixture <- function(horizon = 2) {
  out <- tempfile("pmslt_inputs_")
  generate_mock_pmslt_inputs(output_dir = out)
  mock_dismod_output(input_dir = out)

  disease_epi <- read_pmslt_disease_inputs(
    file.path(out, "mock_dismod_output", "pmslt_disease_epi.csv")
  )
  population <- unique(disease_epi[disease_epi$time_step == 0, c("age", "sex", "stratum")])
  population <- population[order(population$sex, population$stratum, population$age), ]
  population$population <- 1000
  mortality <- population[c("age", "sex", "stratum")]
  mortality$mortality_rate <- 0.02
  morbidity <- population[c("age", "sex", "stratum")]
  morbidity$morbidity_rate <- 0.10

  list(
    dir = out,
    disease_epi = disease_epi,
    population = population,
    mortality = mortality,
    morbidity = morbidity,
    horizon = horizon
  )
}

test_that("run_pmslt chains the full pipeline into a pmslt_run object", {
  fx <- run_pmslt_fixture()

  run <- run_pmslt(
    input_dir = fx$dir,
    disease_epi = fx$disease_epi,
    population = fx$population,
    mortality = fx$mortality,
    morbidity = fx$morbidity,
    horizon = fx$horizon
  )

  expect_s3_class(run, "pmslt_run")
  expect_equal(sort(run$arms), c("Tobacco tax", "Tobacco tax plus acute care"))
  expect_s3_class(run$lifetable$bau, "pmslt_lifetable")
  expect_true(is.data.frame(run$halys$bau))
  expect_true("halys" %in% names(run$halys$bau))
  expect_true(all(run$arms %in% names(run$halys$comparisons)))
  expect_true("haly_difference" %in% names(run$halys$comparisons[[1]]))
  # No cost inputs were supplied here.
  expect_null(run$icers)
  expect_equal(run$metadata$solver, "supplied_disease_epi")

  expect_output(print(run), "pmslt_run")
  expect_output(summary(run), "PMSLT run summary")
})

test_that("run_pmslt equals the equivalent manual layer-by-layer chaining", {
  fx <- run_pmslt_fixture()

  run <- run_pmslt(
    input_dir = fx$dir,
    disease_epi = fx$disease_epi,
    population = fx$population,
    mortality = fx$mortality,
    morbidity = fx$morbidity,
    horizon = fx$horizon
  )

  deltas <- run_pmslt_interventions(
    disease_epi = fx$disease_epi,
    risk_prevalence = file.path(fx$dir, "08_risk_factor_prevalence.csv"),
    relative_risks = file.path(fx$dir, "09_relative_risks.csv"),
    direct_effects = file.path(fx$dir, "10_direct_intervention_effects.csv")
  )
  bridge <- run_pmslt_lifetable_interventions(
    population = fx$population,
    mortality = fx$mortality,
    morbidity = fx$morbidity,
    intervention_effects = deltas,
    horizon = fx$horizon
  )
  manual_bau_halys <- calculate_halys(bridge$bau)

  expect_equal(run$halys$bau, manual_bau_halys)
  expect_equal(run$lifetable$bau$yld, bridge$bau$yld)
})

# A cost table covering every disease/sex/stratum across one wide age band.
run_pmslt_cost_fixture <- function(fx) {
  diseases <- sort(unique(fx$disease_epi$disease))
  keys <- unique(fx$population[c("sex", "stratum")])
  grid <- merge(data.frame(disease = diseases, stringsAsFactors = FALSE), keys)
  grid$age_start <- min(fx$population$age)
  grid$age_end <- max(fx$population$age)
  grid$age_label <- paste0(grid$age_start, "-", grid$age_end)
  grid$disease_cost <- 200
  grid$background_cost <- 100
  grid$currency <- "AUD"
  grid$price_year <- 2024
  grid$source <- "test"
  grid$notes <- ""
  grid
}

test_that("run_pmslt attaches costs and ICERs when cost inputs are present", {
  fx <- run_pmslt_fixture()

  run <- run_pmslt(
    input_dir = fx$dir,
    disease_epi = fx$disease_epi,
    population = fx$population,
    mortality = fx$mortality,
    morbidity = fx$morbidity,
    costs = run_pmslt_cost_fixture(fx),
    horizon = fx$horizon
  )

  expect_false(is.null(run$icers))
  expect_true(all(c("intervention", "icer", "icer_status") %in% names(run$icers)))
  expect_equal(sort(run$icers$intervention), sort(run$arms))
  expect_false(is.null(run$costs))
  expect_true("total_costs" %in% names(run$costs$bau))
})

test_that("run_pmslt runs an optional probabilistic sensitivity analysis", {
  fx <- run_pmslt_fixture()

  run <- run_pmslt(
    input_dir = fx$dir,
    disease_epi = fx$disease_epi,
    population = fx$population,
    mortality = fx$mortality,
    morbidity = fx$morbidity,
    horizon = fx$horizon,
    psa = TRUE,
    psa_draws = 5,
    psa_seed = 1
  )

  expect_false(is.null(run$psa))
  expect_true(is.data.frame(run$psa$draw_outputs))
  expect_true(is.data.frame(run$psa$summary))
})

test_that("run_pmslt solves disease consistency from input_dir with dismod_slove", {
  fx <- run_pmslt_fixture()

  run <- run_pmslt(
    input_dir = fx$dir,
    solver = "dismod_slove",
    population = fx$population,
    mortality = fx$mortality,
    morbidity = fx$morbidity,
    horizon = fx$horizon,
    overwrite = TRUE
  )

  expect_s3_class(run, "pmslt_run")
  expect_equal(run$metadata$solver, "dismod_slove")
  expect_true(validate_pmslt_disease_inputs(run$disease_epi))
})

test_that("run_pmslt errors clearly when required population is missing", {
  expect_error(
    run_pmslt(disease_epi = data.frame()),
    "Cannot find `population`"
  )
})
