test_that("canonical PMSLT-ready disease epidemiology schema exists", {
  schemas <- pmslttools:::pmslt_ready_input_schemas()
  schema <- schemas$pmslt_disease_epi

  expect_true("pmslt_disease_epi" %in% names(schemas))
  expect_equal(schema$file, "pmslt_disease_epi.csv")
  expect_equal(schema$input_stage, "pmslt_ready")
  expect_true(all(pmslttools:::pmslt_disease_epi_required_columns() %in% schema$columns$column))
  expect_true(all(c("column", "requirement", "description", "validation_type", "allowed_values") %in% names(schema$columns)))
  expect_true("age" %in% schema$columns$column)
  expect_false(any(c("age_start", "age_end", "age_label") %in% schema$columns$column))
  expect_equal(
    schema$columns$validation_type[schema$columns$column == "age"],
    "integer"
  )
  expect_equal(
    schema$columns$validation_type[schema$columns$column == "prevalence_initial"],
    "proportion_0_1"
  )
})

test_that("mock DisMod writes pmslt_disease_epi.csv matching canonical schema", {
  out <- tempfile("mock_inputs_")
  generate_mock_pmslt_inputs(output_dir = out)
  mock_dismod_output(input_dir = out)

  schema <- pmslttools:::pmslt_disease_epi_schema()
  path <- file.path(out, "mock_dismod_output", schema$file)
  disease_epi <- utils::read.csv(path, stringsAsFactors = FALSE, na.strings = c("", "NA"))

  expect_true(file.exists(path))
  expect_equal(names(disease_epi), schema$columns$column)
  expect_equal(disease_epi$age, floor(disease_epi$age))
  expect_false(any(c("age_start", "age_end", "age_label") %in% names(disease_epi)))
  expect_true(validate_pmslt_disease_inputs(disease_epi))
})

test_that("prepare_pmslt_disease_inputs returns one row per exact age and writes canonical schema columns", {
  out <- tempfile("mock_inputs_")
  generate_mock_pmslt_inputs(output_dir = out)
  mock_dismod_output(input_dir = out, continuous_age = FALSE)
  smooth_dismod_age_curve(file.path(out, "mock_dismod_output"))
  predict_dismod_to_age_grid(file.path(out, "mock_dismod_output"))

  schema <- pmslttools:::pmslt_disease_epi_schema()
  path <- file.path(out, "mock_dismod_output", schema$file)
  disease_epi <- prepare_pmslt_disease_inputs(input_dir = out, output_file = path)
  written <- utils::read.csv(path, stringsAsFactors = FALSE, na.strings = c("", "NA"))

  expect_equal(names(disease_epi), schema$columns$column)
  expect_equal(names(written), schema$columns$column)
  expect_equal(disease_epi$age, floor(disease_epi$age))
  expect_equal(
    nrow(unique(disease_epi[c("age", "sex", "stratum", "disease", "time_step")])),
    nrow(disease_epi)
  )
  expect_true(all(seq(min(disease_epi$age), max(disease_epi$age)) %in% disease_epi$age))
  expect_true(validate_pmslt_disease_inputs(disease_epi))
})

test_that("read_pmslt_disease_inputs accepts a valid canonical file", {
  out <- tempfile("mock_inputs_")
  generate_mock_pmslt_inputs(output_dir = out)
  mock_dismod_output(input_dir = out)

  path <- file.path(out, "mock_dismod_output", "pmslt_disease_epi.csv")
  disease_epi <- read_pmslt_disease_inputs(path)

  expect_equal(names(disease_epi), pmslttools:::pmslt_disease_epi_schema()$columns$column)
  expect_gt(nrow(disease_epi), 0)
})

test_that("validate_pmslt_disease_inputs accepts valid single-year disease inputs", {
  disease_epi <- data.frame(
    age = c(40L, 40L, 41L, 41L),
    sex = "female",
    stratum = "total",
    disease = "CHD",
    time_step = c(0L, 1L, 0L, 1L),
    incidence_BAU = 0.01,
    prevalence_initial = c(0.1, NA, 0.11, NA),
    remission_rate = 0.02,
    excess_mortality_BAU = 0.03,
    case_fatality_BAU = 0.03,
    disability_weight = 0.2,
    stringsAsFactors = FALSE
  )

  expect_true(validate_pmslt_disease_inputs(disease_epi))
})

test_that("validate_pmslt_disease_inputs rejects age bands in PMSLT-ready inputs", {
  disease_epi <- data.frame(
    age_start = 40L,
    age_end = 44L,
    age_label = "40-44",
    sex = "female",
    stratum = "total",
    disease = "CHD",
    time_step = 0L,
    incidence_BAU = 0.01,
    prevalence_initial = 0.1,
    remission_rate = 0.02,
    excess_mortality_BAU = 0.03,
    case_fatality_BAU = 0.03,
    disability_weight = 0.2,
    stringsAsFactors = FALSE
  )

  expect_error(
    validate_pmslt_disease_inputs(disease_epi),
    "must use exact single-year `age`, not age-band columns",
    fixed = TRUE
  )
  expect_error(
    validate_pmslt_disease_inputs(disease_epi),
    "05_disease_epidemiology_raw.csv",
    fixed = TRUE
  )
})

test_that("PMSLT-ready disease examples do not use age-band columns", {
  extract_code_blocks <- function(path) {
    if (!file.exists(path)) {
      path <- file.path("..", "..", path)
    }
    if (!file.exists(path)) {
      return(character())
    }
    lines <- readLines(path, warn = FALSE)
    fence <- grepl("^```", lines)
    if (!any(fence)) {
      return(character())
    }
    in_block <- cumsum(fence) %% 2 == 1
    lines[in_block & !fence]
  }

  example_lines <- unlist(lapply(c("README.md", "CODEX.md"), extract_code_blocks), use.names = FALSE)
  pmslt_ready_examples <- example_lines[
    grepl("pmslt_disease_epi|read_pmslt_disease_inputs|disease_epi", example_lines)
  ]

  expect_gt(length(pmslt_ready_examples), 0)
  expect_false(any(grepl("age_start|age_end|age_label", pmslt_ready_examples)))
})

test_that("validate_pmslt_disease_inputs rejects missing required columns", {
  out <- tempfile("mock_inputs_")
  generate_mock_pmslt_inputs(output_dir = out)
  mock_dismod_output(input_dir = out)
  disease_epi <- read_pmslt_disease_inputs(file.path(out, "mock_dismod_output", "pmslt_disease_epi.csv"))
  disease_epi$incidence_BAU <- NULL

  expect_error(
    validate_pmslt_disease_inputs(disease_epi),
    "incidence_BAU",
    fixed = TRUE
  )
})

test_that("validate_pmslt_disease_inputs rejects invalid numeric values", {
  out <- tempfile("mock_inputs_")
  generate_mock_pmslt_inputs(output_dir = out)
  mock_dismod_output(input_dir = out)
  disease_epi <- read_pmslt_disease_inputs(file.path(out, "mock_dismod_output", "pmslt_disease_epi.csv"))

  negative_rate <- disease_epi
  negative_rate$incidence_BAU[[1]] <- -0.01
  expect_error(
    validate_pmslt_disease_inputs(negative_rate),
    "non-negative",
    fixed = TRUE
  )

  bad_prevalence <- disease_epi
  bad_prevalence$prevalence_initial[bad_prevalence$time_step == 0][[1]] <- 1.5
  expect_error(
    validate_pmslt_disease_inputs(bad_prevalence),
    "between 0 and 1",
    fixed = TRUE
  )

  bad_numeric <- disease_epi
  bad_numeric$case_fatality_BAU[[1]] <- "not numeric"
  expect_error(
    validate_pmslt_disease_inputs(bad_numeric),
    "must be numeric",
    fixed = TRUE
  )

  bad_age <- disease_epi
  bad_age$age[[1]] <- 40.5
  expect_error(
    validate_pmslt_disease_inputs(bad_age),
    "whole-number",
    fixed = TRUE
  )

  missing_age <- disease_epi
  missing_age$age[[1]] <- NA_real_
  expect_error(
    validate_pmslt_disease_inputs(missing_age),
    "non-missing",
    fixed = TRUE
  )
})
