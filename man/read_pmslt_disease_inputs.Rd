\name{read_pmslt_disease_inputs}
\alias{read_pmslt_disease_inputs}
\title{Read PMSLT-ready disease epidemiology inputs}
\usage{
read_pmslt_disease_inputs(path = "pmslt_disease_epi.csv", validate = TRUE)
}
\arguments{
\item{path}{CSV path. Defaults to \code{pmslt_disease_epi.csv}.}

\item{validate}{Logical. Should required columns and basic values be checked?}
}
\value{
A data frame containing PMSLT-ready disease epidemiology inputs.
}
\description{
Reads the post-DisMod disease epidemiology file used by downstream PMSLT
disease lifetable modules. This is the canonical disease input after DisMod
processing, not the raw \code{05_disease_epidemiology_raw.csv} file and not an
intermediate DisMod-lite diagnostic output. It uses exact single-year integer
\code{age}; age-banded inputs belong upstream or in reporting summaries.
}
