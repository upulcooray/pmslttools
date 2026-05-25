valid_dismod_mr_outputs <- function(parameters = c("incidence", "prevalence")) {
  data.frame(
    disease = rep("ihd", length(parameters)),
    age = rep(45L, length(parameters)),
    sex = rep("female", length(parameters)),
    stratum = rep("total", length(parameters)),
    parameter = parameters,
    mean_value = seq_along(parameters) / 100,
    stringsAsFactors = FALSE
  )
}

valid_dismod_mr_target_grid <- function(parameters = c("incidence", "prevalence")) {
  data.frame(
    disease = rep("ihd", length(parameters)),
    age = rep(45L, length(parameters)),
    sex = rep("female", length(parameters)),
    stratum = rep("total", length(parameters)),
    parameter = parameters,
    stringsAsFactors = FALSE
  )
}

write_dismod_mr_outputs <- function(data) {
  path <- tempfile(fileext = ".csv")
  utils::write.csv(data, path, row.names = FALSE, na = "")
  path
}

test_that("valid minimal output reads and validates", {
  path <- write_dismod_mr_outputs(valid_dismod_mr_outputs())

  modelled <- read_dismod_mr_outputs(path)

  expect_s3_class(modelled, "dismod_mr_outputs")
  expect_true(modelled$validation$is_valid)
  expect_equal(nrow(modelled$outputs), 2)
})

test_that("validate returns validation object in non-strict mode", {
  validation <- validate_dismod_mr_outputs(valid_dismod_mr_outputs(), strict = FALSE)

  expect_s3_class(validation, "dismod_mr_output_validation")
  expect_true(validation$is_valid)
})

test_that("missing required columns fail in strict mode", {
  outputs <- valid_dismod_mr_outputs()
  outputs$mean_value <- NULL

  expect_error(
    validate_dismod_mr_outputs(outputs),
    "missing required column `mean_value`"
  )
})

test_that("unsupported parameters are rejected", {
  outputs <- valid_dismod_mr_outputs("disability_weight")

  expect_error(
    validate_dismod_mr_outputs(outputs),
    "unsupported parameter `disability_weight`"
  )
})

test_that("all allowed parameters are accepted", {
  outputs <- valid_dismod_mr_outputs(c(
    "incidence",
    "prevalence",
    "remission",
    "excess_mortality",
    "case_fatality"
  ))

  validation <- validate_dismod_mr_outputs(outputs)

  expect_true(validation$is_valid)
})

test_that("non-integer and age-band ages are rejected", {
  non_integer <- valid_dismod_mr_outputs("incidence")
  non_integer$age <- 45.5
  expect_error(validate_dismod_mr_outputs(non_integer), "exact integer")

  age_band <- valid_dismod_mr_outputs("incidence")
  age_band$age <- "45-49"
  expect_error(validate_dismod_mr_outputs(age_band), "exact integer")
})

test_that("missing or empty identifiers are rejected", {
  for (column in c("disease", "sex", "stratum", "parameter")) {
    outputs <- valid_dismod_mr_outputs("incidence")
    outputs[[column]] <- ""
    expect_error(
      validate_dismod_mr_outputs(outputs),
      paste0("missing or empty `", column, "`"),
      fixed = TRUE
    )
  }
})

test_that("negative and missing means are rejected", {
  negative <- valid_dismod_mr_outputs("incidence")
  negative$mean_value <- -0.01
  expect_error(validate_dismod_mr_outputs(negative), "negative `mean_value`")

  missing <- valid_dismod_mr_outputs("incidence")
  missing$mean_value <- NA_real_
  expect_error(validate_dismod_mr_outputs(missing), "`mean_value` must be present")
})

test_that("duplicate key rows are rejected", {
  outputs <- rbind(
    valid_dismod_mr_outputs("incidence"),
    valid_dismod_mr_outputs("incidence")
  )

  expect_error(validate_dismod_mr_outputs(outputs), "duplicates another")
})

test_that("valid uncertainty bounds are accepted", {
  outputs <- valid_dismod_mr_outputs("incidence")
  outputs$lower_95 <- 0.005
  outputs$upper_95 <- 0.02

  validation <- validate_dismod_mr_outputs(outputs)

  expect_true(validation$is_valid)
})

test_that("invalid uncertainty bounds are rejected", {
  lower_too_high <- valid_dismod_mr_outputs("incidence")
  lower_too_high$lower_95 <- 0.02
  lower_too_high$upper_95 <- 0.03
  expect_error(validate_dismod_mr_outputs(lower_too_high), "lower_95")

  upper_too_low <- valid_dismod_mr_outputs("incidence")
  upper_too_low$lower_95 <- 0.001
  upper_too_low$upper_95 <- 0.005
  expect_error(validate_dismod_mr_outputs(upper_too_low), "upper_95")

  negative <- valid_dismod_mr_outputs("incidence")
  negative$lower_95 <- -0.001
  negative$upper_95 <- 0.02
  expect_error(validate_dismod_mr_outputs(negative), "negative `lower_95`")
})

test_that("one-sided uncertainty is flagged", {
  outputs <- valid_dismod_mr_outputs("incidence")
  outputs$lower_95 <- 0.005

  validation <- validate_dismod_mr_outputs(outputs, strict = FALSE)

  expect_false(validation$is_valid)
  expect_true(any(validation$issues$issue == "one_sided_uncertainty"))
  expect_error(validate_dismod_mr_outputs(outputs), "both `lower_95` and `upper_95`")
})

test_that("target-grid complete outputs pass", {
  outputs <- valid_dismod_mr_outputs()
  target_grid <- valid_dismod_mr_target_grid()

  validation <- validate_dismod_mr_outputs(outputs, target_grid = target_grid)

  expect_true(validation$is_valid)
})

test_that("missing target-grid rows fail", {
  outputs <- valid_dismod_mr_outputs("incidence")
  target_grid <- valid_dismod_mr_target_grid(c("incidence", "prevalence"))

  expect_error(
    validate_dismod_mr_outputs(outputs, target_grid = target_grid),
    "missing target-grid combination"
  )
})

test_that("extra output rows are warnings and do not fail validation", {
  outputs <- valid_dismod_mr_outputs(c("incidence", "prevalence"))
  target_grid <- valid_dismod_mr_target_grid("incidence")

  validation <- validate_dismod_mr_outputs(outputs, target_grid = target_grid)

  expect_true(validation$is_valid)
  expect_true(any(validation$issues$severity == "warning"))
  expect_true(any(validation$issues$issue == "extra_output_row"))
})

test_that("target grid path is accepted", {
  outputs <- valid_dismod_mr_outputs()
  path <- write_dismod_mr_outputs(outputs)
  target_path <- write_dismod_mr_outputs(valid_dismod_mr_target_grid())

  modelled <- read_dismod_mr_outputs(path, target_grid = target_path)

  expect_s3_class(modelled, "dismod_mr_outputs")
  expect_true(modelled$validation$is_valid)
  expect_equal(nrow(modelled$target_grid), 2)
})

test_that("missing output path errors with the path", {
  missing <- file.path(tempdir(), "missing.csv")

  expect_error(read_dismod_mr_outputs(missing), missing, fixed = TRUE)
})

test_that("print methods show useful summaries", {
  path <- write_dismod_mr_outputs(valid_dismod_mr_outputs())
  modelled <- read_dismod_mr_outputs(path)
  validation <- validate_dismod_mr_outputs(valid_dismod_mr_outputs(), strict = FALSE)

  expect_output(print(modelled), "DisMod-MR outputs")
  expect_output(print(modelled), "Validation passed: yes")
  expect_output(print(validation), "DisMod-MR output validation")
  expect_output(print(validation), "Errors: 0")
})
