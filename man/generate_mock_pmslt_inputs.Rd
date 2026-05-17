\name{generate_mock_pmslt_inputs}
\alias{generate_mock_pmslt_inputs}
\title{Generate mock PMSLT input files}
\usage{
generate_mock_pmslt_inputs(
  output_dir = "mock_inputs_raw",
  spec = mock_pmslt_spec(),
  overwrite = TRUE
)
}
\arguments{
\item{output_dir}{Directory where mock raw input files should be written.}

\item{spec}{Optional \code{pmslt_spec}. Defaults to \code{mock_pmslt_spec()}.}

\item{overwrite}{Logical. Should existing files be overwritten?}
}
\value{
Invisibly returns a list containing \code{spec} and generated templates.
}
\description{
Creates a complete \code{inputs_raw} folder with plausible demonstration values.
Disease epidemiology values are intentionally not perfectly coherent so that
\code{mock_dismod_output()} has visible before/after corrections to plot.
}
