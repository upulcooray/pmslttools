\name{predict_dismod_to_age_grid}
\alias{predict_dismod_to_age_grid}
\title{Predict continuous-age mock DisMod curves to a PMSLT age grid}
\usage{
predict_dismod_to_age_grid(
  dismod_output_dir,
  ages = NULL,
  continuous_file = file.path(dismod_output_dir, "mock_dismod_output_continuous.csv"),
  output_file = file.path(dismod_output_dir, "mock_dismod_output_pmslt_ages.csv"),
  method = c("band_mean", "midpoint"),
  overwrite = TRUE
)
}
\arguments{
\item{dismod_output_dir}{Directory created by \code{mock_dismod_output()}.}

\item{ages}{Age grid. Defaults to age bands inferred from
\code{mock_dismod_output_long.csv}.}

\item{continuous_file}{CSV path created by \code{smooth_dismod_age_curve()}.}

\item{output_file}{CSV path for PMSLT age-grid predictions.}

\item{method}{One of \code{"band_mean"} or \code{"midpoint"}.}

\item{overwrite}{Logical. Should existing output be overwritten?}
}
\value{
Invisibly returns the PMSLT-age data frame.
}
\description{
Converts single-year smoothed values into the PMSLT model age bands. By
default this averages all single-year ages inside each PMSLT age band.
}
