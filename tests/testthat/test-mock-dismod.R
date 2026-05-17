test_that("mock inputs and mock DisMod outputs are generated", {
  out <- tempfile("mock_inputs_")
  generate_mock_pmslt_inputs(output_dir = out)

  expect_true(file.exists(file.path(out, "05_disease_epidemiology_raw.csv")))
  expect_true(file.exists(file.path(out, "README_inputs_raw.md")))

  result <- mock_dismod_output(input_dir = out)
  expect_true(file.exists(file.path(out, "mock_dismod_output", "mock_dismod_output_long.csv")))
  expect_true(file.exists(file.path(out, "mock_dismod_output", "mock_dismod_output_wide.csv")))
  expect_true(file.exists(file.path(out, "mock_dismod_output", "mock_dismod_diagnostics.csv")))
  expect_true(file.exists(file.path(out, "mock_dismod_output", "mock_dismod_output_continuous.csv")))
  expect_true(file.exists(file.path(out, "mock_dismod_output", "mock_dismod_output_pmslt_ages.csv")))

  prevalence <- result$long[result$long$parameter == "prevalence", ]
  expect_true(any(abs(prevalence$absolute_change) > 0))
  expect_true(all(!is.na(prevalence$dismod_mean)))
  expect_true(all(result$continuous$age == floor(result$continuous$age)))
  expect_true(all(!is.na(result$pmslt_ages$dismod_age_grid_mean)))
})

test_that("mock DisMod correction plots are written", {
  out <- tempfile("mock_inputs_")
  generate_mock_pmslt_inputs(output_dir = out)
  mock_dismod_output(input_dir = out)

  plot_file <- file.path(out, "mock_dismod_output", "test_plot.png")
  plotted <- plot_dismod_corrections(
    file.path(out, "mock_dismod_output"),
    output_file = plot_file,
    parameters = "prevalence",
    disease = "CHD",
    sex = "male"
  )

  expect_true(file.exists(plot_file))
  expect_gt(file.info(plot_file)$size, 0)
  expect_true(all(plotted$parameter == "prevalence"))
})

test_that("continuous age curve plot is written", {
  out <- tempfile("mock_inputs_")
  generate_mock_pmslt_inputs(output_dir = out)
  mock_dismod_output(input_dir = out)

  plot_file <- file.path(out, "mock_dismod_output", "age_curve.png")
  plotted <- plot_dismod_age_curve(
    file.path(out, "mock_dismod_output"),
    output_file = plot_file,
    parameters = "prevalence",
    disease = "CHD",
    sex = "male"
  )

  expect_true(file.exists(plot_file))
  expect_gt(file.info(plot_file)$size, 0)
  expect_true(all(plotted$continuous$parameter == "prevalence"))
  expect_true(all(plotted$pmslt_ages$parameter == "prevalence"))
})
