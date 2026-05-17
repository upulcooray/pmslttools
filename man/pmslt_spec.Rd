\name{pmslt_spec}
\alias{pmslt_spec}
\title{Create a PMSLT model specification}
\usage{
pmslt_spec(
  intervention,
  mechanism = c("risk_factor", "direct", "both"),
  diseases,
  risk_factors = character(),
  risk_categories = NULL,
  ages = age_bands(0, 100, by = 5),
  sexes = c("male", "female"),
  strata = "total",
  horizon = 80,
  base_year = NA_integer_,
  timestep = 1,
  cost_effectiveness = FALSE
)
}
\arguments{
\item{intervention}{Short description of the intervention.}
\item{mechanism}{One of \code{"risk_factor"}, \code{"direct"}, or \code{"both"}.}
\item{diseases}{Character vector of diseases modelled.}
\item{risk_factors}{Character vector of risk factors. Required when \code{mechanism} is \code{"risk_factor"} or \code{"both"}.}

\item{risk_categories}{Risk-factor exposure categories. Use a named list,
for example \code{list(Smoking = c("Never", "Current", "Former"))}. If the
model has one risk factor, a plain character vector is also accepted.}
\item{ages}{Data frame returned by \code{age_bands()}, or any data frame with \code{age_start} and \code{age_end} columns.}
\item{sexes}{Character vector of sex labels.}
\item{strata}{Character vector of population strata.}
\item{horizon}{Number of annual simulation cycles.}
\item{base_year}{Base year for the model.}
\item{timestep}{Length of each model cycle in years.}
\item{cost_effectiveness}{Logical. Should cost input templates be generated?}
}
\value{
An object of class \code{pmslt_spec}.
}
\description{
\code{pmslt_spec()} captures the minimum information needed to design
project-specific data collection templates for a PMSLT simulation.
}
