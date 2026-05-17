\name{run_pmslt_disease_lifetable}
\alias{run_pmslt_disease_lifetable}
\title{Run a PMSLT disease lifetable from post-DisMod inputs}
\usage{
run_pmslt_disease_lifetable(
  disease_epi,
  pif_data = NULL,
  direct_effect_data = NULL,
  intervention = NULL,
  cohort_size = 1000
)
}
\arguments{
\item{disease_epi}{Data frame from \code{read_pmslt_disease_inputs()} or path to
\code{pmslt_disease_epi.csv}.}

\item{pif_data}{Optional data frame with \code{age_start}, \code{sex}, \code{stratum},
\code{disease}, \code{time_step}, and \code{pif}. If omitted, intervention equals BAU.}

\item{direct_effect_data}{Optional data frame with direct disease effects.
Expected columns are \code{age_start}, \code{sex}, \code{stratum}, \code{disease},
\code{incidence_rr}, \code{cfr_rr}, \code{morbidity_rr}, and \code{coverage}. If an
\code{intervention} column is present, use \code{intervention} to select one arm.}

\item{intervention}{Optional intervention arm name used to filter PIF and
direct-effect data when those inputs contain multiple scenarios.}

\item{cohort_size}{Radix cohort size for each disease lifetable.}
}
\value{
A data frame with BAU/intervention disease lifetable outputs and
deltas.
}
\description{
This is the first downstream module after DisMod. It consumes
\code{pmslt_disease_epi.csv} directly and returns disease-specific mortality,
morbidity, and intervention deltas. It is intentionally narrow: main
all-cause lifetable integration is a later module.
}
