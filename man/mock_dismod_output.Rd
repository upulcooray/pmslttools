\name{mock_dismod_output}
\alias{mock_dismod_output}
\title{Generate mock DisMod-style corrected outputs}
\usage{
mock_dismod_output(
  input_dir = "mock_inputs_raw",
  output_dir = file.path(input_dir, "mock_dismod_output"),
  overwrite = TRUE
)
}
\arguments{
\item{input_dir}{Raw input directory created by \code{generate_mock_pmslt_inputs()}
or \code{draft_input_templates()}.}

\item{output_dir}{Directory where mock DisMod outputs should be written.}

\item{overwrite}{Logical. Should existing files be overwritten?}
}
\value{
Invisibly returns a list with \code{wide}, \code{long}, and \code{diagnostics}.
}
\description{
This function creates deterministic, teaching-only outputs that look like a
post-DisMod correction file. It uses simple illness-death consistency
equations and age smoothing. It is not a replacement for DisMod-MR.
}
