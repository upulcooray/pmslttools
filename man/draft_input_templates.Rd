\name{draft_input_templates}
\alias{draft_input_templates}
\title{Draft PMSLT input templates}
\usage{
draft_input_templates(spec, output_dir = "pmslt_inputs_raw", overwrite = FALSE)
}
\arguments{
\item{spec}{A \code{pmslt_spec} object.}
\item{output_dir}{Directory where templates should be written.}
\item{overwrite}{Logical. Should existing files be overwritten?}
}
\value{
Invisibly returns a named list of generated data frames.
}
\description{
Generates beginner-friendly CSV templates from a model specification. The
templates collect raw inputs before DisMod processing.
}
