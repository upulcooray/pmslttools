write_dismod_mr_raw_fixture <- function(path, remission = 0.02, incidence = 0.01) {
  raw <- data.frame(
    disease = "ihd",
    sex = "female",
    stratum = "total",
    age_start = c(45, 55),
    age_end = c(49, 59),
    age_label = c("45-49", "55-59"),
    incidence_rate = c(incidence, 0.02),
    prevalence = c(0.05, 0.08),
    remission_rate = c(remission, NA),
    excess_mortality_rate = c(0.10, 0.12),
    case_fatality_rate = c(0.03, 0.04),
    disability_weight = c(0.20, 0.25),
    source = "test source",
    notes = "",
    stringsAsFactors = FALSE
  )
  utils::write.csv(raw, path, row.names = FALSE, na = "")
}

write_dismod_mr_skeleton_fixture <- function(path, parameter = "incidence_rate", value = 0.015) {
  skeleton <- data.frame(
    disease = "ihd",
    sex = "female",
    stratum = "total",
    age_start = 45,
    age_end = 49,
    age_label = "45-49",
    parameter = parameter,
    mean_value = value,
    lower_95 = value * 0.8,
    upper_95 = value * 1.2,
    time_step = 1,
    data_source = "skeleton source",
    stringsAsFactors = FALSE
  )
  utils::write.csv(skeleton, path, row.names = FALSE, na = "")
}

test_that("raw disease evidence exports all four files and preserves age bands", {
  input_dir <- tempfile("dismod_mr_raw_")
  output_dir <- tempfile("dismod_mr_out_")
  dir.create(input_dir)
  write_dismod_mr_raw_fixture(file.path(input_dir, "05_disease_epidemiology_raw.csv"))

  prep <- prepare_dismod_mr_inputs(input_dir, output_dir)

  expect_s3_class(prep, "dismod_mr_input_preparation")
  expect_true(all(file.exists(unlist(prep$files, use.names = FALSE))))
  expect_named(prep$files, c("evidence", "target_grid", "omissions", "summary"))

  evidence <- utils::read.csv(prep$files$evidence, stringsAsFactors = FALSE)
  expect_true(all(c(
    "disease", "sex", "stratum", "age_start", "age_end", "age_label",
    "parameter", "mean_value", "source_file"
  ) %in% names(evidence)))
  expect_false(any(is.na(evidence$mean_value)))
  expect_true(any(evidence$age_start == 45 & evidence$age_end == 49 & evidence$age_label == "45-49"))
  expect_true("disability_weight" %in% evidence$parameter)

  target <- utils::read.csv(prep$files$target_grid, stringsAsFactors = FALSE)
  expect_true(all(target$age == as.integer(target$age)))
  expect_true(all(c("incidence", "prevalence", "remission", "excess_mortality", "case_fatality") %in% target$parameter))
  expect_false("disability_weight" %in% target$parameter)
})

test_that("skeleton-only evidence is accepted and parameter names are normalized", {
  input_dir <- tempfile("dismod_mr_skel_")
  output_dir <- tempfile("dismod_mr_out_")
  dir.create(input_dir)
  write_dismod_mr_skeleton_fixture(file.path(input_dir, "06_dismod_input_skeleton.csv"))

  prep <- prepare_dismod_mr_inputs(input_dir, output_dir)

  expect_equal(nrow(prep$evidence), 1)
  expect_equal(prep$evidence$parameter, "incidence")
  expect_equal(prep$evidence$source_file, "06_dismod_input_skeleton.csv")
  expect_equal(prep$evidence$lower_95, 0.012)
  expect_equal(prep$evidence$upper_95, 0.018)
})

test_that("skeleton evidence supersedes duplicate raw evidence", {
  input_dir <- tempfile("dismod_mr_both_")
  output_dir <- tempfile("dismod_mr_out_")
  dir.create(input_dir)
  write_dismod_mr_raw_fixture(file.path(input_dir, "05_disease_epidemiology_raw.csv"), incidence = 0.01)
  write_dismod_mr_skeleton_fixture(file.path(input_dir, "06_dismod_input_skeleton.csv"), value = 0.015)

  prep <- prepare_dismod_mr_inputs(input_dir, output_dir)
  incidence_45 <- prep$evidence[
    prep$evidence$parameter == "incidence" & prep$evidence$age_start == 45,
    ,
    drop = FALSE
  ]

  expect_equal(nrow(incidence_45), 1)
  expect_equal(incidence_45$mean_value, 0.015)
  expect_equal(incidence_45$source_file, "06_dismod_input_skeleton.csv")
  expect_true(any(prep$omissions$reason == "superseded_by_dismod_input_skeleton"))
})

test_that("blank and non-numeric values are omitted and audited", {
  input_dir <- tempfile("dismod_mr_missing_")
  output_dir <- tempfile("dismod_mr_out_")
  dir.create(input_dir)
  raw <- data.frame(
    disease = "ihd",
    sex = "female",
    stratum = "total",
    age_start = 45,
    age_end = 49,
    age_label = "45-49",
    incidence_rate = "not a number",
    prevalence = 0.05,
    remission_rate = "",
    excess_mortality_rate = 0.10,
    case_fatality_rate = 0.03,
    stringsAsFactors = FALSE
  )
  utils::write.csv(raw, file.path(input_dir, "05_disease_epidemiology_raw.csv"), row.names = FALSE, na = "")

  prep <- prepare_dismod_mr_inputs(input_dir, output_dir)

  expect_false(any(prep$evidence$parameter == "incidence"))
  expect_false(any(prep$evidence$parameter == "remission"))
  expect_true(any(prep$omissions$parameter == "incidence" & prep$omissions$reason == "non_numeric_value"))
  expect_true(any(prep$omissions$parameter == "remission" & prep$omissions$reason == "missing_value"))
  expect_true(all(dismod_mr_parameters() %in% prep$target_grid$parameter))
})

test_that("target grid can use exact ages derived from spec", {
  input_dir <- tempfile("dismod_mr_spec_")
  output_dir <- tempfile("dismod_mr_out_")
  dir.create(input_dir)
  write_dismod_mr_raw_fixture(file.path(input_dir, "05_disease_epidemiology_raw.csv"))
  spec <- pmslt_spec(
    intervention = "example",
    mechanism = "direct",
    diseases = "ihd",
    ages = age_bands(40, 50, by = 5, open_ended = FALSE),
    sexes = "female",
    strata = "total"
  )

  prep <- prepare_dismod_mr_inputs(input_dir, output_dir, spec = spec)

  expect_equal(sort(unique(prep$target_grid$age)), 40:50)
  expect_true(all(dismod_mr_parameters() %in% prep$target_grid$parameter))
  expect_false("disability_weight" %in% prep$target_grid$parameter)
})

test_that("target grid infers deterministic exact ages without spec", {
  input_dir <- tempfile("dismod_mr_infer_")
  output_dir <- tempfile("dismod_mr_out_")
  dir.create(input_dir)
  write_dismod_mr_raw_fixture(file.path(input_dir, "05_disease_epidemiology_raw.csv"))

  prep <- prepare_dismod_mr_inputs(input_dir, output_dir)

  expect_equal(sort(unique(prep$target_grid$age)), c(45:49, 55:59))
})

test_that("target grid flags extrapolation outside observed parameter coverage", {
  input_dir <- tempfile("dismod_mr_extra_")
  output_dir <- tempfile("dismod_mr_out_")
  dir.create(input_dir)
  write_dismod_mr_raw_fixture(file.path(input_dir, "05_disease_epidemiology_raw.csv"))
  spec <- pmslt_spec(
    intervention = "example",
    mechanism = "direct",
    diseases = "ihd",
    ages = data.frame(age_start = 40, age_end = 49, age_label = "40-49"),
    sexes = "female",
    strata = "total"
  )

  prep <- prepare_dismod_mr_inputs(input_dir, output_dir, spec = spec)
  incidence <- prep$target_grid[prep$target_grid$parameter == "incidence", , drop = FALSE]

  expect_true(all(incidence$requires_extrapolation[incidence$age < 45]))
  expect_false(any(incidence$requires_extrapolation[incidence$age >= 45 & incidence$age <= 49]))
  expect_true(any(prep$summary$n_extrapolation_targets > 0))
})

test_that("direct data-frame overrides do not require input_dir", {
  output_dir <- tempfile("dismod_mr_out_")
  disease_raw <- data.frame(
    disease = "ihd",
    sex = "female",
    stratum = "total",
    age_start = 45,
    age_end = 49,
    age_label = "45-49",
    incidence_rate = 0.01,
    prevalence = 0.05,
    stringsAsFactors = FALSE
  )

  prep <- prepare_dismod_mr_inputs(NULL, output_dir, disease_raw = disease_raw)

  expect_equal(nrow(prep$evidence), 2)
  expect_equal(prep$evidence$source_file, rep("05_disease_epidemiology_raw.csv", 2))
})

test_that("bad inputs have beginner-facing errors", {
  expect_error(
    prepare_dismod_mr_inputs(output_dir = tempfile("dismod_mr_out_")),
    "input_dir.*no direct disease evidence"
  )

  input_dir <- tempfile("dismod_mr_bad_")
  dir.create(input_dir)
  utils::write.csv(
    data.frame(disease = "ihd", incidence_rate = 0.1),
    file.path(input_dir, "05_disease_epidemiology_raw.csv"),
    row.names = FALSE
  )
  expect_error(
    prepare_dismod_mr_inputs(input_dir, tempfile("dismod_mr_out_")),
    "missing"
  )

  input_dir2 <- tempfile("dismod_mr_bad_values_")
  dir.create(input_dir2)
  raw <- data.frame(
    disease = "ihd",
    sex = "female",
    stratum = "total",
    age_start = 45,
    age_end = 49,
    incidence_rate = "not numeric",
    stringsAsFactors = FALSE
  )
  utils::write.csv(raw, file.path(input_dir2, "05_disease_epidemiology_raw.csv"), row.names = FALSE)
  expect_error(
    prepare_dismod_mr_inputs(input_dir2, tempfile("dismod_mr_out_")),
    "no usable disease evidence"
  )
})

test_that("summary is grouped by disease, sex, stratum, and parameter", {
  input_dir <- tempfile("dismod_mr_summary_")
  output_dir <- tempfile("dismod_mr_out_")
  dir.create(input_dir)
  write_dismod_mr_raw_fixture(file.path(input_dir, "05_disease_epidemiology_raw.csv"))

  prep <- prepare_dismod_mr_inputs(input_dir, output_dir)

  expect_true(all(c(
    "disease", "sex", "stratum", "parameter", "n_evidence_rows",
    "min_age_start", "max_age_end", "n_omitted_rows", "n_target_ages",
    "n_extrapolation_targets"
  ) %in% names(prep$summary)))
  expect_true(all(dismod_mr_parameters() %in% prep$summary$parameter))
})
