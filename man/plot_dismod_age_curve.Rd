\name{plot_dismod_age_curve}
\alias{plot_dismod_age_curve}
\title{Plot raw points, continuous DisMod curve, and PMSLT age predictions}
\usage{
plot_dismod_age_curve(
  dismod_output_dir,
  output_file = file.path(dismod_output_dir, "dismod_continuous_age_curve.png"),
  parameters = c("incidence_rate", "prevalence"),
  disease = NULL,
  sex = NULL
)
}
\arguments{
\item{dismod_output_dir}{Directory created by \code{mock_dismod_output()}.}

\item{output_file}{Optional PNG output path.}

\item{parameters}{Parameters to plot.}

\item{disease}{Optional disease filter.}

\item{sex}{Optional sex filter.}
}
\value{
Invisibly returns a list with raw, continuous, and PMSLT-age data.
}
\description{
Plot raw points, continuous DisMod curve, and PMSLT age predictions
}
