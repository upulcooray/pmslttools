write_dismod_mr_raw_fixture <- function(path, incidence = 0.01, unsupported_signal = NA_real_) {
  raw <- data.frame(
    disease = "ihd",
    age_start = 45,
    age_end = 49,
    sex = "female",
    stratum = "total",
    incidence_rate = incidence,
    prevalence = 0.05,
    remission_rate = 0.02,
    excess_mortality_rate = 0.10,
    case_fatality_rate = 0.03,
    disability_weight = 0.20,
    unsupported_signal = unsupported_signal,
    source = "test source",
    notes = "",
    stringsAsFactors = FALSE
  )
  utils::write.csv(raw, path, row.names = FALSE, na = "")
}

write_dismod_mr_skeleton_fixture <- function(path, value = 0.015) {
  skeleton <- data.frame(
    disease = "ihd",
    age_start = 45,
    age_end = 49,
    sex = "female",
    stratum = "total",
    parameter = "incidence",
    mean_value = value,
    stringsAsFactors = FALSE
  )
  utils::write.csv(skeleton, path, row.names = FALSE, na = "")
}

test_that("prepare_dismod_mr_inputs creates expected files and object", {
  input_dir <- tempfile("dismod_mr_inputs_")
  dir.create(input_dir)
  write_dismod_mr_raw_fixture(file.path(input_dir, "05_disease_epidemiology_raw.csv"))

  prep <- prepare_dismod_mr_inputs(input_dir)

  expect_s3_class(prep, "dismod_mr_input_preparation")
  expect_true(dir.exists(file.path(input_dir, "dismod_mr_inputs")))
  expect_true(all(file.exists(unlist(prep$files, use.names = FALSE))))
  expect_named(prep$files, c("input_long", "target_grid", "omissions", "summary"))
})

test_that("long input preserves raw age bands and required columns", {
  input_dir <- tempfile("dismod_mr_inputs_")
  dir.create(input_dir)
  write_dismod_mr_raw_fixture(file.path(input_dir, "05_disease_epidemiology_raw.csv"))

  prep <- prepare_dismod_mr_inputs(input_dir)
  long <- utils::read.csv(prep$files$input_long, stringsAsFactors = FALSE)

  expect_true(all(c(
    "disease", "parameter", "age_start", "age_end", "sex", "stratum",
    "mean_value", "source_file", "source_row", "is_skeleton_value"
  ) %in% names(long)))
  expect_equal(nrow(long[long$parameter == "incidence", , drop = FALSE]), 1)
  expect_equal(long$age_start[long$parameter == "incidence"], 45)
  expect_equal(long$age_end[long$parameter == "incidence"], 49)
})

test_that("target grid expands age bands to exact ages and excludes disability weight", {
  input_dir <- tempfile("dismod_mr_inputs_")
  dir.create(input_dir)
  write_dismod_mr_raw_fixture(file.path(input_dir, "05_disease_epidemiology_raw.csv"))

  prep <- prepare_dismod_mr_inputs(input_dir)
  target <- utils::read.csv(prep$files$target_grid, stringsAsFactors = FALSE)

  expect_true(all(45:49 %in% target$age))
  expect_true(all(c("incidence", "prevalence", "remission", "excess_mortality", "case_fatality") %in% target$parameter))
  expect_false("disability_weight" %in% target$parameter)
})

test_that("skeleton values take precedence over raw evidence", {
  input_dir <- tempfile("dismod_mr_inputs_")
  dir.create(input_dir)
  write_dismod_mr_raw_fixture(file.path(input_dir, "05_disease_epidemiology_raw.csv"), incidence = 0.01)
  write_dismod_mr_skeleton_fixture(file.path(input_dir, "06_dismod_input_skeleton.csv"), value = 0.015)

  prep <- prepare_dismod_mr_inputs(input_dir)
  incidence <- prep$input_long[prep$input_long$parameter == "incidence", , drop = FALSE]
  omissions <- prep$omissions[prep$omissions$parameter == "incidence", , drop = FALSE]

  expect_equal(nrow(incidence), 1)
  expect_equal(incidence$mean_value, 0.015)
  expect_true(incidence$is_skeleton_value)
  expect_true(any(omissions$reason == "skeleton value overrides raw value"))
})

test_that("unsupported parameters are omitted from active input", {
  input_dir <- tempfile("dismod_mr_inputs_")
  dir.create(input_dir)
  write_dismod_mr_raw_fixture(
    file.path(input_dir, "05_disease_epidemiology_raw.csv"),
    unsupported_signal = 0.4
  )

  prep <- prepare_dismod_mr_inputs(input_dir)

  expect_false("unsupported_signal" %in% prep$input_long$parameter)
  expect_true(any(prep$omissions$parameter == "unsupported_signal" & prep$omissions$reason == "unsupported parameter"))
})

test_that("overwrite protection names conflict and overwrite TRUE replaces files", {
  input_dir <- tempfile("dismod_mr_inputs_")
  dir.create(input_dir)
  write_dismod_mr_raw_fixture(file.path(input_dir, "05_disease_epidemiology_raw.csv"))
  prep <- prepare_dismod_mr_inputs(input_dir)

  expect_error(
    prepare_dismod_mr_inputs(input_dir),
    "dismod_mr_input_long.csv.*overwrite = TRUE"
  )
  expect_s3_class(
    prepare_dismod_mr_inputs(input_dir, output_dir = prep$output_dir, overwrite = TRUE),
    "dismod_mr_input_preparation"
  )
})

test_that("missing raw disease file has a beginner-facing error", {
  input_dir <- tempfile("dismod_mr_inputs_")
  dir.create(input_dir)

  expect_error(
    prepare_dismod_mr_inputs(input_dir),
    "05_disease_epidemiology_raw.csv.*not found"
  )
})

test_that("print method reports useful counts", {
  input_dir <- tempfile("dismod_mr_inputs_")
  dir.create(input_dir)
  write_dismod_mr_raw_fixture(file.path(input_dir, "05_disease_epidemiology_raw.csv"))

  prep <- prepare_dismod_mr_inputs(input_dir)

  expect_output(print(prep), "Output directory:")
  expect_output(print(prep), "Input rows:")
  expect_output(print(prep), "Target grid rows:")
  expect_output(print(prep), "Omitted rows:")
})
