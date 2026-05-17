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
disease modules.
}
