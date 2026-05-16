\name{age_bands}
\alias{age_bands}
\title{Create age bands}
\usage{
age_bands(min = 0, max = 100, by = 5, open_ended = TRUE)
}
\arguments{
\item{min}{Minimum age.}
\item{max}{Maximum age.}
\item{by}{Age-band width.}
\item{open_ended}{Logical. Should the final age band be open ended?}
}
\value{
A data frame with \code{age_start}, \code{age_end}, and \code{age_label}.
}
\description{
Create age bands for PMSLT model specifications and input templates.
}
