equity_spec <- function() {
  pmslt_spec(
    intervention = "Equity test",
    mechanism = "direct",
    diseases = "CHD",
    ages = age_bands(40, 41, by = 1, open_ended = FALSE),
    sexes = "female",
    strata = c("least", "most"),
    horizon = 1
  )
}

equity_population <- function() {
  data.frame(
    age = c(40L, 40L, 41L, 41L),
    sex = "female",
    stratum = c("least", "most", "least", "most"),
    population = c(1000, 800, 900, 700),
    stringsAsFactors = FALSE
  )
}

equity_aggregate_mortality <- function() {
  data.frame(
    age = c(40L, 41L),
    sex = "female",
    stratum = "total",
    mortality_rate = c(0.01, 0.02),
    stringsAsFactors = FALSE
  )
}

equity_aggregate_morbidity <- function() {
  data.frame(
    age = c(40L, 41L),
    sex = "female",
    stratum = "total",
    morbidity_rate = c(0.10, 0.20),
    stringsAsFactors = FALSE
  )
}

equity_rate_ratios <- function(parameters = stratum_rate_ratio_parameter_names()) {
  grid <- expand.grid(
    age_start = c(40L, 41L),
    sex = "female",
    stratum = c("least", "most"),
    parameter = parameters,
    stringsAsFactors = FALSE
  )
  grid$rate_ratio <- ifelse(grid$stratum == "least", 1, 2)
  grid$reference_stratum <- "least"
  grid$source <- "Unit test source"
  grid$notes <- ""
  grid
}

equity_disease_epi <- function() {
  data.frame(
    age = c(40L, 41L),
    sex = "female",
    stratum = "total",
    disease = "CHD",
    time_step = 0L,
    incidence_BAU = c(0.01, 0.02),
    prevalence_initial = c(0.10, 0.20),
    remission_rate = c(0, 0),
    excess_mortality_BAU = c(0.02, 0.03),
    case_fatality_BAU = c(0.03, 0.04),
    disability_weight = c(0.20, 0.30),
    stringsAsFactors = FALSE
  )
}

write_equity_raw_inputs <- function(spec = equity_spec()) {
  input_dir <- tempfile("equity_raw_inputs_")
  draft_input_templates(spec, output_dir = input_dir, write_guide = FALSE)
  templates <- pmslttools:::build_input_templates(spec)
  for (template_name in names(templates)) {
    data <- templates[[template_name]]
    for (column in names(data)) {
      if (column %in% c("source", "data_source")) data[[column]] <- "Unit test source"
      if (column == "initial_population") data[[column]] <- 1000
      if (column == "acmr_BAU") data[[column]] <- 0.01
      if (column == "pYLD_BAU") data[[column]] <- 0.10
      if (column == "expected_years_remaining") data[[column]] <- 80 - as.numeric(data$age)
      if (column %in% c("disability_weight", "coverage")) data[[column]] <- 0.10
      if (column %in% c("incidence_rate", "prevalence", "remission_rate", "excess_mortality_rate", "disease_mortality_rate", "case_fatality_rate")) {
        data[[column]] <- if (column == "prevalence") 0.10 else 0.01
      }
      if (column %in% c("incidence_apc", "cfr_apc", "prevalence_apc")) data[[column]] <- 0
      if (column %in% c("incidence_rr", "cfr_rr", "morbidity_rr")) data[[column]] <- 1
      if (column == "rate_ratio") data[[column]] <- 1
      if (column == "reference_stratum") data[[column]] <- spec$strata[[1]]
    }
    utils::write.csv(data, file.path(input_dir, paste0(template_name, ".csv")), row.names = FALSE, na = "")
  }
  input_dir
}

test_that("stratum rate-ratio definitions list explicit supported targets", {
  definitions <- stratum_rate_ratio_definitions()

  expect_equal(
    definitions$parameter,
    c("acmr", "morbidity", "incidence", "remission", "excess_mortality", "case_fatality", "mortality")
  )
  expect_true(any(grepl("mortality_rate", definitions$columns)))
  expect_true(any(grepl("incidence_BAU", definitions$columns)))
})

test_that("all-cause mortality and morbidity are disaggregated before lifetable execution", {
  result <- run_pmslt_lifetable_bau(
    equity_population(),
    equity_aggregate_mortality(),
    equity_aggregate_morbidity(),
    horizon = 1,
    spec = equity_spec(),
    stratum_rate_ratios = equity_rate_ratios()
  )

  most_age40 <- result[result$age == 40L & result$stratum == "most", ]
  least_age40 <- result[result$age == 40L & result$stratum == "least", ]

  expect_equal(least_age40$mortality_rate, 0.01)
  expect_equal(most_age40$mortality_rate, 0.02)
  expect_equal(most_age40$morbidity_rate, 0.20)
  expect_equal(most_age40$mortality_rate_original_aggregate, 0.01)
  expect_equal(most_age40$mortality_rate_rate_ratio, 2)
  expect_equal(most_age40$mortality_rate_rate_ratio_parameter, "acmr")
  expect_equal(most_age40$mortality_rate_reference_stratum, "least")
})

test_that("one-step lifetable keeps audit columns for disaggregated rates", {
  result <- initialize_pmslt_lifetable(
    equity_population(),
    equity_aggregate_mortality(),
    morbidity = equity_aggregate_morbidity(),
    spec = equity_spec(),
    stratum_rate_ratios = equity_rate_ratios()
  )

  expect_true(all(c(
    "mortality_rate_original_aggregate",
    "mortality_rate_rate_ratio",
    "morbidity_rate_original_aggregate",
    "morbidity_rate_rate_ratio"
  ) %in% names(result)))
  expect_equal(result$deaths[result$age == 41L & result$stratum == "most"], 700 * 0.04)
})

test_that("missing rate-ratio rows fail before lifetable execution", {
  ratios <- equity_rate_ratios()
  ratios <- ratios[!(ratios$age_start == 41L & ratios$stratum == "most" & ratios$parameter == "acmr"), ]

  expect_error(
    run_pmslt_lifetable_bau(
      equity_population(),
      equity_aggregate_mortality(),
      horizon = 1,
      spec = equity_spec(),
      stratum_rate_ratios = ratios
    ),
    "missing a row needed to disaggregate `mortality_rate`"
  )
})

test_that("invalid strata outside pmslt_spec are rejected", {
  ratios <- equity_rate_ratios()
  ratios$stratum[[1]] <- "outside_spec"

  expect_error(
    disaggregate_stratum_rates(
      equity_aggregate_mortality(),
      ratios,
      target_keys = equity_population()[c("age", "sex", "stratum")],
      spec = equity_spec(),
      label = "mortality"
    ),
    "not in `spec\\$strata`"
  )
})

test_that("disease rates can be disaggregated before disease deltas are calculated", {
  lifetable <- run_pmslt_lifetable_bau(
    equity_population(),
    data.frame(
      age = c(40L, 40L, 41L, 41L),
      sex = "female",
      stratum = c("least", "most", "least", "most"),
      mortality_rate = 0.01,
      stringsAsFactors = FALSE
    ),
    horizon = 1,
    spec = equity_spec()
  )

  result <- integrate_disease_deltas(
    lifetable,
    equity_disease_epi(),
    stratum_rate_ratios = equity_rate_ratios()
  )
  long <- attr(result, "disease_deltas")
  most_age40 <- long[long$age == 40L & long$stratum == "most", ]

  expect_equal(most_age40$incidence_BAU, 0.02)
  expect_equal(most_age40$case_fatality_BAU, 0.06)
  expect_equal(most_age40$incidence_BAU_original_aggregate, 0.01)
  expect_equal(most_age40$incidence_BAU_rate_ratio, 2)
})

test_that("raw validation checks stratum rate-ratio completeness across age sex stratum and parameter", {
  spec <- equity_spec()
  input_dir <- write_equity_raw_inputs(spec)
  ratios <- utils::read.csv(
    file.path(input_dir, "11_stratum_rate_ratios.csv"),
    stringsAsFactors = FALSE,
    na.strings = c("", "NA"),
    check.names = FALSE
  )
  ratios <- ratios[!(ratios$age_start == 41L & ratios$stratum == "most" & ratios$parameter == "morbidity"), ]
  utils::write.csv(ratios, file.path(input_dir, "11_stratum_rate_ratios.csv"), row.names = FALSE, na = "")

  issues <- validate_raw_inputs(input_dir, spec)

  expect_true(any(
    issues$file == "11_stratum_rate_ratios.csv" &
      issues$column == "age_start, sex, stratum, parameter" &
      grepl("parameter=morbidity", issues$message)
  ))
})
