\name{run_pmslt_interventions}
\alias{run_pmslt_interventions}
\title{Run PMSLT disease lifetables for one or more intervention arms}
\usage{
run_pmslt_interventions(
  disease_epi,
  risk_prevalence = NULL,
  relative_risks = NULL,
  direct_effects = NULL,
  interventions = NULL,
  cohort_size = 1000
)
}
\arguments{
\item{disease_epi}{Data frame from \code{read_pmslt_disease_inputs()} or path to
\code{pmslt_disease_epi.csv}.}

\item{risk_prevalence}{Optional data frame or CSV path for
\code{08_risk_factor_prevalence.csv}.}

\item{relative_risks}{Optional data frame or CSV path for
\code{09_relative_risks.csv}.}

\item{direct_effects}{Optional data frame or CSV path for
\code{10_direct_intervention_effects.csv}.}

\item{interventions}{Optional character vector of intervention arms to run.
Defaults to every arm found in PIF or direct-effect inputs.}

\item{cohort_size}{Radix cohort size for each disease lifetable.}
}
\value{
A data frame of disease lifetable outputs with an \code{intervention}
column.
}
\description{
This is the beginner-facing intervention runner. It accepts post-DisMod
exact-age disease inputs, optional raw risk-factor prevalence plus relative
risks, and optional direct disease effects. Risk-factor inputs are converted to
PIFs automatically. Direct effects can be used alone or alongside PIFs.
Age-banded intervention rows are expanded to the exact ages present in
\code{pmslt_disease_epi.csv} where that expansion is intentional.
}
