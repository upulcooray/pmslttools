valid_direct_spec <- function() {
  pmslt_spec(
    intervention = "Screening",
    mechanism = "direct",
    diseases = "CHD",
    ages = age_bands(0, 5, by = 5, open_ended = FALSE),
    sexes = "male",
    strata = "total",
    horizon = 1
  )
}

write_valid_raw_inputs <- function(spec = valid_direct_spec()) {
  input_dir <- tempfile("raw_inputs_")
  draft_input_templates(spec, output_dir = input_dir, write_guide = FALSE)
  templates <- pmslttools:::build_input_templates(spec)

  for (template_name in names(templates)) {
    data <- templates[[template_name]]
    data <- fill_required_template_values(data, template_name, spec)
    utils::write.csv(data, file.path(input_dir, paste0(template_name, ".csv")), row.names = FALSE, na = "")
  }

  input_dir
}

fill_required_template_values <- function(data, template_name, spec) {
  for (column in names(data)) {
    if (column %in% c("source", "data_source")) {
      data[[column]] <- "Unit test source"
    }
    if (column == "initial_population") data[[column]] <- 1000
    if (column == "acmr_BAU") data[[column]] <- 0.01
    if (column == "pYLD_BAU") data[[column]] <- 0.10
    if (column == "expected_years_remaining") data[[column]] <- 80 - as.numeric(data$age)
    if (column %in% c("disability_weight", "coverage")) data[[column]] <- 0.10
    if (column %in% c("incidence_rate", "prevalence", "remission_rate", "excess_mortality_rate", "case_fatality_rate")) {
      data[[column]] <- if (column == "prevalence") 0.10 else 0.01
    }
    if (column %in% c("incidence_apc", "cfr_apc", "prevalence_apc")) data[[column]] <- 0
    if (column %in% c("incidence_rr", "cfr_rr", "morbidity_rr", "rr", "rr_lower", "rr_upper")) data[[column]] <- 1
    if (column %in% c("prevalence_BAU", "prevalence_intervention")) data[[column]] <- 1
    if (column == "reference_category") data[[column]] <- "Reference"
    if (column %in% c("acmr_rate_ratio", "morbidity_rate_ratio")) data[[column]] <- 1
    if (column == "reference_stratum") data[[column]] <- spec$strata[[1]]
    if (column %in% c("disease_cost", "background_cost")) data[[column]] <- 100
    if (column == "currency") data[[column]] <- "AUD"
    if (column == "price_year") data[[column]] <- 2024
  }
  data
}

read_raw_csv <- function(input_dir, file) {
  utils::read.csv(
    file.path(input_dir, file),
    stringsAsFactors = FALSE,
    na.strings = c("", "NA"),
    check.names = FALSE
  )
}

write_raw_csv <- function(input_dir, file, data) {
  utils::write.csv(data, file.path(input_dir, file), row.names = FALSE, na = "")
}

expect_validation_columns <- function(issues) {
  expect_s3_class(issues, "pmslt_validation_issues")
  expect_equal(
    names(issues),
    c("file", "row", "column", "severity", "message", "suggested_fix")
  )
}

test_that("valid minimal raw templates return a zero-row issue table", {
  spec <- valid_direct_spec()
  input_dir <- write_valid_raw_inputs(spec)

  issues <- validate_raw_inputs(input_dir, spec)

  expect_validation_columns(issues)
  expect_equal(nrow(issues), 0)
})

test_that("missing required files are reported", {
  spec <- valid_direct_spec()
  input_dir <- write_valid_raw_inputs(spec)
  unlink(file.path(input_dir, "01_population.csv"))

  issues <- validate_raw_inputs(input_dir, spec)

  missing_issue <- issues[issues$file == "01_population.csv" & grepl("missing", issues$message), ]
  expect_equal(nrow(missing_issue), 1)
  expect_true(is.na(missing_issue$row))
  expect_true(is.na(missing_issue$column))
  expect_equal(missing_issue$severity, "error")
  expect_match(missing_issue$message, "Required raw input file")
  expect_match(missing_issue$suggested_fix, "Regenerate")
})

test_that("missing required columns are reported", {
  spec <- valid_direct_spec()
  input_dir <- write_valid_raw_inputs(spec)
  population <- read_raw_csv(input_dir, "01_population.csv")
  population$source <- NULL
  write_raw_csv(input_dir, "01_population.csv", population)

  issues <- validate_raw_inputs(input_dir, spec)

  expect_true(any(issues$file == "01_population.csv" & issues$column == "source" & grepl("missing", issues$message)))
})

test_that("unexpected extra columns are reported as warnings", {
  spec <- valid_direct_spec()
  input_dir <- write_valid_raw_inputs(spec)
  population <- read_raw_csv(input_dir, "01_population.csv")
  population$extra_comment <- "extra"
  write_raw_csv(input_dir, "01_population.csv", population)

  issues <- validate_raw_inputs(input_dir, spec)

  expect_true(any(
    issues$file == "01_population.csv" &
      issues$column == "extra_comment" &
      issues$severity == "warning" &
      grepl("not part of this raw input template", issues$message)
  ))
})

test_that("duplicated column names are reported", {
  spec <- valid_direct_spec()
  input_dir <- write_valid_raw_inputs(spec)
  population <- read_raw_csv(input_dir, "01_population.csv")
  duplicated_population <- population[, c("age_start", names(population))]
  names(duplicated_population)[1:2] <- "age_start"
  utils::write.table(
    duplicated_population,
    file.path(input_dir, "01_population.csv"),
    sep = ",",
    row.names = FALSE,
    col.names = TRUE,
    na = ""
  )

  issues <- validate_raw_inputs(input_dir, spec)

  expect_true(any(issues$file == "01_population.csv" & issues$column == "age_start" & grepl("more than once", issues$message)))
})

test_that("invalid numeric values are reported", {
  spec <- valid_direct_spec()
  input_dir <- write_valid_raw_inputs(spec)
  mortality <- read_raw_csv(input_dir, "02_all_cause_mortality.csv")
  mortality$acmr_BAU[[1]] <- "not a number"
  write_raw_csv(input_dir, "02_all_cause_mortality.csv", mortality)

  issues <- validate_raw_inputs(input_dir, spec)

  expect_true(any(issues$file == "02_all_cause_mortality.csv" & issues$column == "acmr_BAU" & grepl("non-numeric", issues$message)))
})

test_that("invalid categorical values are reported from the spec", {
  spec <- valid_direct_spec()
  input_dir <- write_valid_raw_inputs(spec)
  population <- read_raw_csv(input_dir, "01_population.csv")
  population$sex[[1]] <- "unknown"
  write_raw_csv(input_dir, "01_population.csv", population)

  issues <- validate_raw_inputs(input_dir, spec)

  expect_true(any(issues$file == "01_population.csv" & issues$column == "sex" & grepl("not expected", issues$message)))
})

test_that("invalid allowed values from the schema are reported", {
  spec <- valid_direct_spec()
  input_dir <- write_valid_raw_inputs(spec)
  dismod <- read_raw_csv(input_dir, "06_dismod_input_skeleton.csv")
  dismod$parameter[[1]] <- "not_a_parameter"
  write_raw_csv(input_dir, "06_dismod_input_skeleton.csv", dismod)

  issues <- validate_raw_inputs(input_dir, spec)

  expect_true(any(
    issues$file == "06_dismod_input_skeleton.csv" &
      issues$row == 1 &
      issues$column == "parameter" &
      grepl("not expected", issues$message)
  ))
})

test_that("missing required values are reported", {
  spec <- valid_direct_spec()
  input_dir <- write_valid_raw_inputs(spec)
  population <- read_raw_csv(input_dir, "01_population.csv")
  population$initial_population[[1]] <- NA
  write_raw_csv(input_dir, "01_population.csv", population)

  issues <- validate_raw_inputs(input_dir, spec)

  expect_true(any(issues$file == "01_population.csv" & issues$row == 1 & issues$column == "initial_population" & grepl("blank", issues$message)))
})

test_that("duplicate key rows are reported where schema defines keys", {
  spec <- valid_direct_spec()
  input_dir <- write_valid_raw_inputs(spec)
  population <- read_raw_csv(input_dir, "01_population.csv")
  population <- rbind(population, population[1, ])
  write_raw_csv(input_dir, "01_population.csv", population)

  issues <- validate_raw_inputs(input_dir, spec)

  expect_true(any(
    issues$file == "01_population.csv" &
      issues$row == 3 &
      issues$column == "age_start, sex, stratum" &
      grepl("repeats the same identifying values", issues$message)
  ))
})

test_that("invalid bounds are reported for rates and proportions", {
  spec <- valid_direct_spec()
  input_dir <- write_valid_raw_inputs(spec)
  mortality <- read_raw_csv(input_dir, "02_all_cause_mortality.csv")
  mortality$acmr_BAU[[1]] <- -0.1
  write_raw_csv(input_dir, "02_all_cause_mortality.csv", mortality)
  disease <- read_raw_csv(input_dir, "05_disease_epidemiology_raw.csv")
  disease$prevalence[[1]] <- 1.5
  write_raw_csv(input_dir, "05_disease_epidemiology_raw.csv", disease)

  issues <- validate_raw_inputs(input_dir, spec)

  expect_true(any(issues$file == "02_all_cause_mortality.csv" & issues$column == "acmr_BAU" & grepl("negative", issues$message)))
  expect_true(any(issues$file == "05_disease_epidemiology_raw.csv" & issues$column == "prevalence" & grepl("between 0 and 1", issues$message)))
})

test_that("multiple simultaneous issues accumulate", {
  spec <- valid_direct_spec()
  input_dir <- write_valid_raw_inputs(spec)
  unlink(file.path(input_dir, "04_life_expectancy.csv"))
  population <- read_raw_csv(input_dir, "01_population.csv")
  population$source[[1]] <- NA
  population$sex[[1]] <- "other"
  write_raw_csv(input_dir, "01_population.csv", population)
  mortality <- read_raw_csv(input_dir, "02_all_cause_mortality.csv")
  mortality$acmr_BAU[[1]] <- -0.1
  write_raw_csv(input_dir, "02_all_cause_mortality.csv", mortality)

  issues <- validate_raw_inputs(input_dir, spec)

  expect_gt(nrow(issues), 2)
  expect_true(any(issues$file == "04_life_expectancy.csv"))
  expect_true(any(issues$column == "source"))
  expect_true(any(issues$column == "sex"))
  expect_true(any(issues$column == "acmr_BAU"))
})

test_that("issue table structure is stable", {
  spec <- valid_direct_spec()
  input_dir <- write_valid_raw_inputs(spec)
  unlink(file.path(input_dir, "01_population.csv"))

  issues <- validate_raw_inputs(input_dir, spec)

  expect_validation_columns(issues)
  expect_type(issues$file, "character")
  expect_type(issues$row, "integer")
  expect_type(issues$column, "character")
  expect_type(issues$severity, "character")
  expect_type(issues$message, "character")
  expect_type(issues$suggested_fix, "character")
})

test_that("missing folders and file paths return issue tables", {
  missing_dir <- file.path(tempdir(), "raw_inputs_that_do_not_exist")
  issues <- validate_raw_inputs(missing_dir)

  expect_validation_columns(issues)
  expect_equal(nrow(issues), 1)
  expect_equal(issues$severity, "error")
  expect_match(issues$message, "does not exist")

  file_path <- tempfile(fileext = ".csv")
  writeLines("x", file_path)
  file_issues <- validate_raw_inputs(file_path)

  expect_validation_columns(file_issues)
  expect_equal(nrow(file_issues), 1)
  expect_equal(file_issues$severity, "error")
  expect_match(file_issues$message, "not a folder")
})

test_that("validation issue ordering is deterministic", {
  spec <- valid_direct_spec()
  input_dir <- write_valid_raw_inputs(spec)
  population <- read_raw_csv(input_dir, "01_population.csv")
  population$source[[1]] <- NA
  population$sex[[1]] <- "other"
  write_raw_csv(input_dir, "01_population.csv", population)

  first <- validate_raw_inputs(input_dir, spec)
  second <- validate_raw_inputs(input_dir, spec)

  expect_identical(first, second)
})

test_that("print method summarises issue counts", {
  spec <- valid_direct_spec()
  input_dir <- write_valid_raw_inputs(spec)
  unlink(file.path(input_dir, "01_population.csv"))

  issues <- validate_raw_inputs(input_dir, spec)

  expect_output(print(issues), "PMSLT raw input validation issues")
  expect_output(print(issues), "Issues: 1")
})

test_that("unexpected duplicate files are reported", {
  spec <- valid_direct_spec()
  input_dir <- write_valid_raw_inputs(spec)
  file.copy(
    file.path(input_dir, "01_population.csv"),
    file.path(input_dir, "01_population copy.csv")
  )

  issues <- validate_raw_inputs(input_dir, spec)

  expect_true(any(issues$file == "01_population copy.csv" & grepl("duplicate", issues$message)))
})
