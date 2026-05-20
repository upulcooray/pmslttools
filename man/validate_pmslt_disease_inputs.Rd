\name{validate_pmslt_disease_inputs}
\alias{validate_pmslt_disease_inputs}
\title{Validate PMSLT-ready disease epidemiology inputs}
\usage{
validate_pmslt_disease_inputs(data)
}
\arguments{
\item{data}{Data frame, usually read from \code{pmslt_disease_epi.csv}.}
}
\value{
Invisibly returns \code{TRUE} if valid.
}
\description{
Checks the post-DisMod disease input structure expected by downstream PMSLT
disease modules. The required columns come from the central
\code{pmslt_disease_epi.csv} schema. The canonical PMSLT-ready file uses exact
single-year integer \code{age}; age-banded raw inputs should be checked with
\code{\link[=validate_raw_inputs]{validate_raw_inputs()}} before DisMod processing.
}
