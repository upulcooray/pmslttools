bridge_dismod_outputs <- function(ages = 47L,
                                  disease = "ihd",
                                  sex = "female",
                                  stratum = "total",
                                  uncertainty = FALSE) {
  parameters <- c(
    "incidence",
    "prevalence",
    "remission",
    "excess_mortality",
    "case_fatality"
  )
  values <- c(0.01, 0.05, 0.02, 0.10, 0.03)
  rows <- lapply(ages, function(age) {
    data.frame(
      disease = rep(disease, length(parameters)),
      age = rep(age, length(parameters)),
      sex = rep(sex, length(parameters)),
      stratum = rep(stratum, length(parameters)),
      parameter = parameters,
      mean_value = values,
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  row.names(out) <- NULL
  if (isTRUE(uncertainty)) {
    out$lower_95 <- pmax(out$mean_value - 0.001, 0)
    out$upper_95 <- out$mean_value + 0.001
  }
  out
}

bridge_raw_disease_inputs <- function(disability_weight = 0.2,
                                      age_start = 45L,
                                      age_end = 49L,
                                      disease = "ihd",
                                      sex = "female",
                                      stratum = "total") {
  data.frame(
    disease = disease,
    age_start = age_start,
    age_end = age_end,
    sex = sex,
    stratum = stratum,
    disability_weight = disability_weight,
    stringsAsFactors = FALSE
  )
}

bridge_write_csv <- function(data) {
  path <- tempfile(fileext = ".csv")
  utils::write.csv(data, path, row.names = FALSE, na = "")
  path
}

test_that("valid DisMod-MR data frame converts to PMSLT disease inputs", {
  disease_inputs <- prepare_pmslt_disease_inputs_from_dismod_mr(
    bridge_dismod_outputs(),
    bridge_raw_disease_inputs()
  )

  expect_s3_class(disease_inputs, "pmslt_disease_inputs_from_dismod_mr")
  expect_true(validate_pmslt_disease_inputs(disease_inputs))
  expect_equal(nrow(disease_inputs), 1)
  expect_equal(disease_inputs$disease, "ihd")
  expect_equal(disease_inputs$age, 47L)
  expect_equal(disease_inputs$time_step, 0L)
  expect_equal(disease_inputs$disability_weight, 0.2)
})

test_that("path inputs are read and converted", {
  outputs_path <- bridge_write_csv(bridge_dismod_outputs())
  raw_path <- bridge_write_csv(bridge_raw_disease_inputs())

  disease_inputs <- prepare_pmslt_disease_inputs_from_dismod_mr(
    outputs_path,
    raw_disease_inputs = raw_path
  )

  expect_equal(disease_inputs$incidence_BAU, 0.01)
  expect_equal(disease_inputs$prevalence_initial, 0.05)
  expect_true(validate_pmslt_disease_inputs(disease_inputs))
})

test_that("dismod_mr_outputs objects are accepted", {
  outputs_path <- bridge_write_csv(bridge_dismod_outputs())
  modelled <- read_dismod_mr_outputs(outputs_path)

  disease_inputs <- prepare_pmslt_disease_inputs_from_dismod_mr(
    modelled,
    raw_disease_inputs = bridge_raw_disease_inputs()
  )

  expect_s3_class(disease_inputs, "pmslt_disease_inputs_from_dismod_mr")
  expect_equal(nrow(disease_inputs), 1)
})

test_that("parameter mapping is exact", {
  disease_inputs <- prepare_pmslt_disease_inputs_from_dismod_mr(
    bridge_dismod_outputs(),
    bridge_raw_disease_inputs()
  )

  expect_equal(disease_inputs$incidence_BAU, 0.01)
  expect_equal(disease_inputs$prevalence_initial, 0.05)
  expect_equal(disease_inputs$remission_rate, 0.02)
  expect_equal(disease_inputs$excess_mortality_BAU, 0.10)
  expect_equal(disease_inputs$case_fatality_BAU, 0.03)
})

test_that("disability weights join from raw age bands", {
  disease_inputs <- prepare_pmslt_disease_inputs_from_dismod_mr(
    bridge_dismod_outputs(ages = 47L),
    bridge_raw_disease_inputs(age_start = 45L, age_end = 49L, disability_weight = 0.2)
  )

  expect_equal(disease_inputs$disability_weight, 0.2)
})

test_that("multiple exact ages can use one raw disability-weight age band", {
  disease_inputs <- prepare_pmslt_disease_inputs_from_dismod_mr(
    bridge_dismod_outputs(ages = 45:49),
    bridge_raw_disease_inputs(age_start = 45L, age_end = 49L, disability_weight = 0.2)
  )

  expect_equal(disease_inputs$age, 45:49)
  expect_equal(disease_inputs$disability_weight, rep(0.2, 5))
})

test_that("missing disability-weight match fails clearly", {
  expect_error(
    prepare_pmslt_disease_inputs_from_dismod_mr(
      bridge_dismod_outputs(ages = 47L),
      bridge_raw_disease_inputs(age_start = 40L, age_end = 44L)
    ),
    "Cannot join disability_weight for disease `ihd`, age 47, sex `female`, stratum `total`"
  )
})

test_that("ambiguous disability-weight matches fail clearly", {
  raw <- rbind(
    bridge_raw_disease_inputs(age_start = 45L, age_end = 49L),
    bridge_raw_disease_inputs(age_start = 47L, age_end = 50L)
  )

  expect_error(
    prepare_pmslt_disease_inputs_from_dismod_mr(bridge_dismod_outputs(), raw),
    "multiple matching raw disease rows"
  )
})

test_that("invalid DisMod-MR outputs fail before conversion", {
  outputs <- bridge_dismod_outputs()
  outputs$parameter[[1]] <- "disability_weight"

  expect_error(
    prepare_pmslt_disease_inputs_from_dismod_mr(outputs, bridge_raw_disease_inputs()),
    "unsupported parameter `disability_weight`"
  )

  outputs <- bridge_dismod_outputs()
  outputs$age[[1]] <- 47.5
  expect_error(
    prepare_pmslt_disease_inputs_from_dismod_mr(outputs, bridge_raw_disease_inputs()),
    "exact integer"
  )
})

test_that("missing required DisMod-MR parameter fails clearly", {
  outputs <- bridge_dismod_outputs()
  outputs <- outputs[outputs$parameter != "remission", , drop = FALSE]

  expect_error(
    prepare_pmslt_disease_inputs_from_dismod_mr(outputs, bridge_raw_disease_inputs()),
    "required parameter\\(s\\) are missing: remission"
  )
})

test_that("canonical PMSLT validation runs by default", {
  expect_error(
    prepare_pmslt_disease_inputs_from_dismod_mr(
      bridge_dismod_outputs(),
      bridge_raw_disease_inputs(disability_weight = 1.2)
    ),
    "`disability_weight` should be between 0 and 1",
    fixed = TRUE
  )
})

test_that("canonical PMSLT validation can be disabled for conversion debugging", {
  disease_inputs <- prepare_pmslt_disease_inputs_from_dismod_mr(
    bridge_dismod_outputs(),
    bridge_raw_disease_inputs(disability_weight = 1.2),
    validate = FALSE
  )

  expect_equal(disease_inputs$disability_weight, 1.2)
  expect_false(attr(disease_inputs, "pmslt_validation_passed"))
})

test_that("uncertainty provenance is preserved when supplied", {
  disease_inputs <- prepare_pmslt_disease_inputs_from_dismod_mr(
    bridge_dismod_outputs(uncertainty = TRUE),
    bridge_raw_disease_inputs()
  )

  expect_true("incidence_BAU_lower_95" %in% names(disease_inputs))
  expect_true("incidence_BAU_upper_95" %in% names(disease_inputs))
  expect_equal(disease_inputs$incidence_BAU_lower_95, 0.009)
  expect_equal(disease_inputs$incidence_BAU_upper_95, 0.011)
})

test_that("uncertainty columns are not required", {
  disease_inputs <- prepare_pmslt_disease_inputs_from_dismod_mr(
    bridge_dismod_outputs(uncertainty = FALSE),
    bridge_raw_disease_inputs()
  )

  expect_false("incidence_BAU_lower_95" %in% names(disease_inputs))
  expect_true(validate_pmslt_disease_inputs(disease_inputs))
})

test_that("output path writing works", {
  output_path <- tempfile(fileext = ".csv")

  disease_inputs <- prepare_pmslt_disease_inputs_from_dismod_mr(
    bridge_dismod_outputs(),
    bridge_raw_disease_inputs(),
    output_path = output_path
  )
  written <- read_pmslt_disease_inputs(output_path)

  expect_true(file.exists(output_path))
  expect_equal(written$incidence_BAU, disease_inputs$incidence_BAU)
})

test_that("output path overwrite protection works", {
  output_path <- tempfile(fileext = ".csv")
  writeLines("already here", output_path)

  expect_error(
    prepare_pmslt_disease_inputs_from_dismod_mr(
      bridge_dismod_outputs(),
      bridge_raw_disease_inputs(),
      output_path = output_path
    ),
    "overwrite = TRUE"
  )
})

test_that("output path overwrite can replace existing files", {
  output_path <- tempfile(fileext = ".csv")
  writeLines("already here", output_path)

  disease_inputs <- prepare_pmslt_disease_inputs_from_dismod_mr(
    bridge_dismod_outputs(),
    bridge_raw_disease_inputs(),
    output_path = output_path,
    overwrite = TRUE
  )
  written <- read_pmslt_disease_inputs(output_path)

  expect_equal(written$prevalence_initial, disease_inputs$prevalence_initial)
})

test_that("returned class and print method show useful summary", {
  disease_inputs <- prepare_pmslt_disease_inputs_from_dismod_mr(
    bridge_dismod_outputs(ages = 45:46),
    bridge_raw_disease_inputs()
  )

  expect_s3_class(disease_inputs, "pmslt_disease_inputs_from_dismod_mr")
  expect_output(print(disease_inputs), "PMSLT disease inputs from DisMod-MR")
  expect_output(print(disease_inputs), "Canonical PMSLT validation passed: yes")
})
