\name{validate_risk_prevalence_inputs}
\alias{validate_risk_prevalence_inputs}
\title{Validate risk-factor prevalence distributions}
\usage{
validate_risk_prevalence_inputs(
  risk_prevalence,
  tolerance = 0.001,
  stop_on_error = TRUE
)
}
\arguments{
\item{risk_prevalence}{Data frame or CSV path for
\code{08_risk_factor_prevalence.csv}.}

\item{tolerance}{Maximum allowed absolute difference from 1.}

\item{stop_on_error}{Logical. If \code{TRUE}, stop when invalid sums are found.
If \code{FALSE}, return an issue table.}
}
\value{
Invisibly returns an issue table when \code{stop_on_error = TRUE}; returns
the issue table directly when \code{stop_on_error = FALSE}.
}
\description{
Checks that every risk-factor category distribution in
\code{08_risk_factor_prevalence.csv} sums to 1. This is a focused validation used
before PIF calculation.
}
