\name{plot_dismod_corrections}
\alias{plot_dismod_corrections}
\title{Plot raw versus mock DisMod-corrected epidemiological parameters}
\usage{
plot_dismod_corrections(
  dismod_output_dir,
  output_file = file.path(dismod_output_dir, "epi_parameter_corrections.png"),
  parameters = c("incidence_rate", "prevalence", "remission_rate",
    "excess_mortality_rate", "case_fatality_rate"),
  disease = NULL,
  sex = NULL
)
}
\arguments{
\item{dismod_output_dir}{Directory created by \code{mock_dismod_output()}.}

\item{output_file}{Optional PNG path. If \code{NULL}, plot on the active device.}

\item{parameters}{Character vector of parameters to plot. Defaults to all.}

\item{disease}{Optional disease filter.}

\item{sex}{Optional sex filter.}
}
\value{
Invisibly returns the plotted data.
}
\description{
Creates simple before/after plots from \code{mock_dismod_output_long.csv}.
}
