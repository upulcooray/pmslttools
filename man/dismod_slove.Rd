\name{dismod_slove}
\alias{dismod_slove}
\title{Solve simple DisMod-style epidemiological consistency equations}
\usage{
dismod_slove(
  input_dir = "pmslt_inputs_raw",
  output_dir = file.path(input_dir, "dismod_lite_results"),
  overwrite = FALSE,
  consistency_tolerance = 0.15,
  uncertainty = FALSE,
  draws = 2000,
  seed = NULL
)
}
\arguments{
\item{input_dir}{Directory created by \code{\link[=draft_input_templates]{draft_input_templates()}}.}

\item{output_dir}{Directory where solved CSV files should be written.}

\item{overwrite}{Logical. Should existing output files be overwritten?}

\item{consistency_tolerance}{Relative tolerance used when flagging supplied values that do not agree with the steady-state equations.}

\item{uncertainty}{Logical. If \code{TRUE}, propagate uncertainty by Monte Carlo sampling from rows with \code{lower_95} and \code{upper_95} values.}

\item{draws}{Number of Monte Carlo draws when \code{uncertainty = TRUE}.}

\item{seed}{Optional random seed for reproducible uncertainty intervals.}
}
\value{
Invisibly returns a list containing solved wide results, solved long results, and diagnostics.
}
\description{
Reads a PMSLT \code{input_raw} directory, expands coarse disease age groups to
exact single-year ages, and fills missing values where they can be identified
from simple steady-state illness-death equations. This is intentionally a small
deterministic teaching/local diagnostic helper, not a replacement for full
DisMod-MR.
}
