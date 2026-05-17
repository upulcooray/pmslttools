\name{calculate_pif_from_inputs}
\alias{calculate_pif_from_inputs}
\title{Calculate population impact fractions from raw template inputs}
\usage{
calculate_pif_from_inputs(risk_prevalence, relative_risks)
}
\arguments{
\item{risk_prevalence}{Data frame or CSV path for
\code{08_risk_factor_prevalence.csv}.}

\item{relative_risks}{Data frame or CSV path for \code{09_relative_risks.csv}.}
}
\value{
A data frame with one PIF per intervention, age, sex, stratum,
disease, and time step.
}
\description{
This converts \code{08_risk_factor_prevalence.csv} and \code{09_relative_risks.csv}
into the compact PIF table used by the disease lifetable. It supports
multiple intervention arms in the same prevalence file. When there is more
than one risk factor, PIFs are calculated separately by risk factor and then
combined as \code{1 - prod(1 - pif)}, an independence-style approximation.
}
