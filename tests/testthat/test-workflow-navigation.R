test_that("next_pmslt_step gives start guidance with no arguments", {
  guidance <- next_pmslt_step()

  expect_s3_class(guidance, "pmslt_next_step")
  expect_identical(guidance$current_stage, "start")
  expect_identical(guidance$recommended_function, "pmslt_spec")
  expect_named(
    guidance,
    c("current_stage", "next_step", "recommended_function", "why", "example")
  )
})

test_that("next_pmslt_step supports all explicit workflow stages", {
  stages <- c(
    "spec",
    "templates",
    "raw_inputs",
    "raw_validation",
    "dismod_lite",
    "pmslt_disease_inputs",
    "disease_lifetable",
    "interventions",
    "halys"
  )

  for (stage in stages) {
    guidance <- next_pmslt_step(stage)

    expect_s3_class(guidance, "pmslt_next_step")
    expect_identical(guidance$current_stage, stage)
    expect_named(
      guidance,
      c("current_stage", "next_step", "recommended_function", "why", "example")
    )
    expect_type(guidance$next_step, "character")
    expect_type(guidance$recommended_function, "character")
    expect_type(guidance$why, "character")
    expect_type(guidance$example, "character")
    expect_equal(length(guidance$example), 1)
  }
})

test_that("unsupported stages give a clear beginner-facing error", {
  expect_error(
    next_pmslt_step("made_up_stage"),
    "Supported stages are: spec, templates, raw_inputs, raw_validation, dismod_lite, pmslt_disease_inputs, disease_lifetable, interventions, halys",
    fixed = TRUE
  )
})

test_that("explicit stage takes precedence over object inference", {
  readiness <- list(can_proceed = TRUE)
  class(readiness) <- "raw_input_readiness_check"

  guidance <- next_pmslt_step(stage = "raw_inputs", object = readiness)

  expect_identical(guidance$current_stage, "raw_inputs")
  expect_identical(guidance$recommended_function, "check_raw_input_readiness")
})

test_that("next_pmslt_step infers raw input readiness check objects", {
  readiness <- list(can_proceed = TRUE)
  class(readiness) <- "raw_input_readiness_check"

  guidance <- next_pmslt_step(object = readiness)

  expect_identical(guidance$current_stage, "raw_validation")
  expect_identical(guidance$recommended_function, "dismod_slove")
})

test_that("next_pmslt_step infers summarised raw input issue objects", {
  summary <- list(can_proceed = FALSE)
  class(summary) <- "summarised_raw_input_issues"

  guidance <- next_pmslt_step(object = summary)

  expect_identical(guidance$current_stage, "raw_validation")
  expect_match(guidance$next_step, "fix errors")
})

test_that("next_pmslt_step infers stable pmslt_spec objects", {
  spec <- pmslt_spec(
    intervention = "Tobacco tax",
    mechanism = "direct",
    diseases = "CHD"
  )

  guidance <- next_pmslt_step(object = spec)

  expect_identical(guidance$current_stage, "spec")
  expect_identical(guidance$recommended_function, "draft_input_templates")
})

test_that("print.pmslt_next_step includes the recommended function", {
  guidance <- next_pmslt_step("raw_inputs")

  printed <- capture.output(expect_error(print(guidance), NA))

  expect_true(any(grepl("PMSLT workflow guidance", printed, fixed = TRUE)))
  expect_true(any(grepl("check_raw_input_readiness", printed, fixed = TRUE)))
})
