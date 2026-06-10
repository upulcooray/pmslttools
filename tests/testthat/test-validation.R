# Numeric validation guards for documented modelling properties. These are
# deliberately analytic: they assert exact, hand-checkable reproduction so the
# core maths cannot silently drift.

validation_aggregate_mortality <- function() {
  data.frame(
    age = c(40L, 41L),
    sex = "female",
    stratum = "total",
    mortality_rate = c(0.01, 0.02),
    stringsAsFactors = FALSE
  )
}

validation_target_keys <- function() {
  expand.grid(
    age = c(40L, 41L),
    sex = "female",
    stratum = c("least", "most"),
    stringsAsFactors = FALSE
  )
}

validation_rate_ratios <- function(most = 2) {
  grid <- expand.grid(
    age_start = c(40L, 41L),
    sex = "female",
    stratum = c("least", "most"),
    parameter = "acmr",
    stringsAsFactors = FALSE
  )
  grid$rate_ratio <- ifelse(grid$stratum == "least", 1, most)
  grid$reference_stratum <- "least"
  grid$source <- "validation"
  grid$notes <- ""
  grid
}

test_that("equity disaggregation reproduces the aggregate at the reference stratum", {
  disaggregated <- disaggregate_stratum_rates(
    validation_aggregate_mortality(),
    rate_ratios = validation_rate_ratios(most = 2),
    target_keys = validation_target_keys()
  )

  least <- disaggregated[disaggregated$stratum == "least", ]
  most <- disaggregated[disaggregated$stratum == "most", ]

  # Reference stratum exactly reproduces the aggregate rate.
  expect_equal(least$mortality_rate, c(0.01, 0.02))
  # Non-reference stratum is the aggregate scaled by its rate ratio, exactly.
  expect_equal(most$mortality_rate, c(0.02, 0.04))
  # The original aggregate is preserved as an audit trail.
  expect_equal(most$mortality_rate_original_aggregate, c(0.01, 0.02))
})

test_that("identity disaggregation (all ratios 1) leaves every stratum at the aggregate", {
  disaggregated <- disaggregate_stratum_rates(
    validation_aggregate_mortality(),
    rate_ratios = validation_rate_ratios(most = 1),
    target_keys = validation_target_keys()
  )

  for (s in c("least", "most")) {
    expect_equal(
      disaggregated$mortality_rate[disaggregated$stratum == s],
      c(0.01, 0.02)
    )
  }
})

