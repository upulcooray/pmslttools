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
      risk_factors = character()
    ),
    "risk_factors"
  )
})

test_that("valid specification is created", {
  spec <- pmslt_spec(
    intervention = "Tax",
    mechanism = "risk_factor",
    diseases = "CHD",
    risk_factors = "Smoking"
  )
  expect_s3_class(spec, "pmslt_spec")
  expect_true(validate_spec(spec))
})
