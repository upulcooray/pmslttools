test_that("mock inputs and mock DisMod outputs are generated", {
  out <- tempfile("mock_inputs_")
  generate_mock_pmslt_inputs(output_dir = out)

  expect_true(file.exists(file.path(out, "05_disease_epidemiology_raw.csv")))
  expect_true(file.exists(file.path(out, "README_inputs_raw.md")))

  result <- mock_dismod_output(input_dir = out)
  expect_true(file.exists(file.path(out, "mock_dismod_output", "mock_dismod_output_long.csv")))
  expect_true(file.exists(file.path(out, "mock_dismod_output", "mock_dismod_output_wide.csv")))
  expect_true(file.exists(file.path(out, "mock_dismod_output", "mock_dismod_diagnostics.csv")))

  prevalence <- result$long[result$long$parameter == "prevalence", ]
  expect_true(any(abs(prevalence$absolute_change) > 0))
  expect_true(all(!is.na(prevalence$dismod_mean)))
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
