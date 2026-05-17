\name{prepare_pmslt_disease_inputs}
\alias{prepare_pmslt_disease_inputs}
\title{Prepare PMSLT-ready disease epidemiology inputs}
\usage{
prepare_pmslt_disease_inputs(
  input_dir = "mock_inputs_raw",
  dismod_output_dir = file.path(input_dir, "mock_dismod_output"),
  output_file = file.path(dismod_output_dir, "pmslt_disease_epi.csv"),
  horizon = NULL,
  overwrite = TRUE
)
}
\arguments{
\item{input_dir}{Raw input directory containing \code{05_disease_epidemiology_raw.csv}
and optionally \code{07_bau_trends.csv} and \code{08_risk_factor_prevalence.csv}.}

\item{dismod_output_dir}{Directory containing \code{mock_dismod_output_pmslt_ages.csv}.}

\item{output_file}{CSV path for PMSLT-ready disease inputs.}

\item{horizon}{Optional simulation horizon. If \code{NULL}, inferred from
\code{08_risk_factor_prevalence.csv} when available; otherwise 0.}

\item{overwrite}{Logical. Should an existing output file be overwritten?}
}
\value{
Invisibly returns the PMSLT-ready disease input data frame.
}
\description{
Converts post-DisMod PMSLT age-grid predictions into a wide, time-expanded
disease epidemiology file that can be passed to a PMSLT disease lifetable.
}
