\name{diagnose_missing_parameters}
\alias{diagnose_missing_parameters}
\title{Diagnose missing disease parameters}
\usage{
diagnose_missing_parameters(raw_disease_data = NULL, spec)
}
\arguments{
\item{raw_disease_data}{Optional data frame containing disease rows and epidemiological parameter columns.}
\item{spec}{A \code{pmslt_spec} object.}
}
\value{
A data frame with one row per disease and plain-language guidance.
}
\description{
Explains the minimum epidemiological parameters needed before DisMod
processing. This function is intentionally plain-language because it is aimed
at users who are new to simulation modelling.
}
