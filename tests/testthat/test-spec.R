test_that("age_bands creates labelled bands", {
  ages <- age_bands(0, 10, by = 5)
  expect_equal(ages$age_label, c("0-4", "5-9", "10+"))
})

test_that("risk factor specifications require risk factors", {
  expect_error(
    pmslt_spec(
      intervention = "Tax",
      mechanism = "risk_factor",
      diseases = "CHD",
      risk_factors = character(),
      risk_categories = character()
    ),
    "risk_factors"
  )
})

test_that("risk factor specifications require categories", {
  expect_error(
    pmslt_spec(
      intervention = "Tax",
      mechanism = "risk_factor",
      diseases = "CHD",
      risk_factors = "Smoking"
    ),
    "risk_categories"
  )
})

test_that("valid specification is created", {
  spec <- pmslt_spec(
    intervention = "Tax",
    intervention_arms = c("Tax", "Tax plus cessation"),
    mechanism = "risk_factor",
    diseases = "CHD",
    risk_factors = "Smoking",
    risk_categories = list(Smoking = c("Never", "Current"))
  )
  expect_s3_class(spec, "pmslt_spec")
  expect_equal(spec$intervention_arms, c("Tax", "Tax plus cessation"))
  expect_true(validate_spec(spec))
})

test_that("single risk factor accepts character risk_categories", {
  spec <- pmslt_spec(
    intervention = "Tax",
    mechanism = "risk_factor",
    diseases = "CHD",
    risk_factors = "Smoking",
    risk_categories = c("Never", "Current")
  )
  expect_equal(spec$risk_categories$Smoking, c("Never", "Current"))
})
