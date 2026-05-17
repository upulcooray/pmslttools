\name{smooth_dismod_age_curve}
\alias{smooth_dismod_age_curve}
\title{Smooth mock DisMod outputs over continuous age}
\usage{
smooth_dismod_age_curve(
  dismod_output_dir,
  output_file = file.path(dismod_output_dir, "mock_dismod_output_continuous.csv"),
  age_min = NULL,
  age_max = NULL,
  parameters = c("incidence_rate", "prevalence", "remission_rate",
    "excess_mortality_rate", "case_fatality_rate"),
  overwrite = TRUE
)
}
\arguments{
\item{dismod_output_dir}{Directory created by \code{mock_dismod_output()}.}

\item{output_file}{CSV path for continuous-age predictions.}

\item{age_min}{Minimum single-year age to predict. Defaults to the minimum
raw age start.}

\item{age_max}{Maximum single-year age to predict. Defaults to the maximum
raw age end.}

\item{parameters}{Parameters to smooth.}

\item{overwrite}{Logical. Should existing output be overwritten?}
}
\value{
Invisibly returns the continuous-age data frame.
}
\description{
Fits simple parameter-specific age curves from mock DisMod corrected values
and predicts single-year age values. This represents the conceptual step
where DisMod smooths epidemiological parameters across continuous age.
}
