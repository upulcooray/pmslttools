#' Draft PMSLT input templates
#'
#' Generates beginner-friendly CSV templates from a model specification. The
#' templates collect raw inputs before DisMod processing.
#'
#' @param spec A `pmslt_spec` object.
#' @param output_dir Directory where templates should be written.
#' @param overwrite Logical. Should existing files be overwritten?
#'
#' @return Invisibly returns a named list of generated data frames.
#' @export
draft_input_templates <- function(spec,
                                  output_dir = "pmslt_inputs_raw",
                                  overwrite = FALSE) {
  validate_spec(spec)

  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  templates <- build_input_templates(spec)

  for (name in names(templates)) {
    path <- file.path(output_dir, paste0(name, ".csv"))
    if (file.exists(path) && !isTRUE(overwrite)) {
      stop(
        "File already exists: ", path,
        ". Use `overwrite = TRUE` to replace it.",
        call. = FALSE
      )
    }
    utils::write.csv(templates[[name]], path, row.names = FALSE, na = "")
  }

  message("PMSLT input templates written to: ", normalizePath(output_dir))
  invisible(templates)
}

build_input_templates <- function(spec) {
  base_grid <- expand_base_grid(spec)
  disease_grid <- expand_disease_grid(spec)
  time_grid <- expand_time_grid(spec)

  templates <- list(
    "00_model_specification" = model_spec_template(spec),
    "01_population" = population_template(base_grid),
    "02_all_cause_mortality" = all_cause_mortality_template(base_grid),
    "03_all_cause_morbidity" = all_cause_morbidity_template(base_grid),
    "04_life_expectancy" = life_expectancy_template(spec),
    "05_disease_epidemiology_raw" = disease_epidemiology_template(disease_grid),
    "06_dismod_input_skeleton" = dismod_input_template(disease_grid),
    "07_bau_trends" = bau_trends_template(disease_grid)
  )

  if (spec$mechanism %in% c("risk_factor", "both")) {
    templates[["08_risk_factor_prevalence"]] <- risk_factor_prevalence_template(spec, time_grid)
    templates[["09_relative_risks"]] <- relative_risk_template(spec, base_grid)
  }

  if (spec$mechanism %in% c("direct", "both")) {
    templates[["10_direct_intervention_effects"]] <- direct_effect_template(spec, disease_grid)
  }

  if (length(spec$strata) > 1 || !identical(tolower(spec$strata), "total")) {
    templates[["11_stratum_rate_ratios"]] <- stratum_rate_ratio_template(spec)
  }

  if (isTRUE(spec$cost_effectiveness)) {
    templates[["12_costs"]] <- cost_template(disease_grid)
  }

  templates
}

expand_base_grid <- function(spec) {
  expand.grid(
    age_start = spec$ages$age_start,
    sex = spec$sexes,
    stratum = spec$strata,
    stringsAsFactors = FALSE
  ) |>
    merge(spec$ages, by = "age_start", sort = FALSE) |>
    subset(select = c("age_start", "age_end", "age_label", "sex", "stratum"))
}

expand_time_grid <- function(spec) {
  base <- expand_base_grid(spec)
  merge(
    base,
    data.frame(time_step = seq.int(0, spec$horizon), stringsAsFactors = FALSE),
    all = TRUE
  )
}

expand_disease_grid <- function(spec) {
  base <- expand_base_grid(spec)
  merge(
    base,
    data.frame(disease = spec$diseases, stringsAsFactors = FALSE),
    all = TRUE
  )
}

model_spec_template <- function(spec) {
  data.frame(
    field = c(
      "intervention", "mechanism", "diseases", "risk_factors", "sexes",
      "strata", "horizon", "base_year", "cost_effectiveness"
    ),
    value = c(
      spec$intervention,
      spec$mechanism,
      paste(spec$diseases, collapse = "; "),
      paste(spec$risk_factors, collapse = "; "),
      paste(spec$sexes, collapse = "; "),
      paste(spec$strata, collapse = "; "),
      as.character(spec$horizon),
      as.character(spec$base_year),
      as.character(spec$cost_effectiveness)
    ),
    notes = c(
      "Short name of the intervention being modelled.",
      "risk_factor, direct, or both.",
      "Diseases causally affected by the intervention.",
      "Risk factors changed by the intervention, if relevant.",
      "Sex groups included in the model.",
      "Equity or population strata included in the model.",
      "Number of annual cycles.",
      "Base year for population and epidemiological inputs.",
      "Whether cost templates were generated."
    ),
    stringsAsFactors = FALSE
  )
}

population_template <- function(base_grid) {
  transform(
    base_grid,
    initial_population = NA_real_,
    source = NA_character_,
    notes = NA_character_
  )
}

all_cause_mortality_template <- function(base_grid) {
  transform(
    base_grid,
    acmr_BAU = NA_real_,
    source = NA_character_,
    notes = "Rate per person-year, not per 100,000."
  )
}

all_cause_morbidity_template <- function(base_grid) {
  transform(
    base_grid,
    pYLD_BAU = NA_real_,
    source = NA_character_,
    notes = "All-cause morbidity as prevalent YLD per person."
  )
}

life_expectancy_template <- function(spec) {
  data.frame(
    age = spec$ages$age_start,
    expected_years_remaining = NA_real_,
    source = NA_character_,
    notes = "Used for YLL and DALY calculations.",
    stringsAsFactors = FALSE
  )
}

disease_epidemiology_template <- function(disease_grid) {
  transform(
    disease_grid,
    incidence_rate = NA_real_,
    prevalence = NA_real_,
    remission_rate = NA_real_,
    excess_mortality_rate = NA_real_,
    case_fatality_rate = NA_real_,
    disability_weight = NA_real_,
    source = NA_character_,
    notes = "Leave unavailable parameters blank for DisMod processing."
  )
}

dismod_input_template <- function(disease_grid) {
  params <- c(
    "incidence",
    "prevalence",
    "remission",
    "excess_mortality",
    "case_fatality"
  )
  out <- merge(
    disease_grid,
    data.frame(parameter = params, stringsAsFactors = FALSE),
    all = TRUE
  )
  transform(
    out,
    mean_value = NA_real_,
    lower_95 = NA_real_,
    upper_95 = NA_real_,
    sample_size = NA_real_,
    data_source = NA_character_,
    quality_flag = NA_character_,
    notes = "DisMod-ready long format."
  )
}

bau_trends_template <- function(disease_grid) {
  unique_diseases <- unique(disease_grid["disease"])
  transform(
    unique_diseases,
    incidence_apc = NA_real_,
    cfr_apc = NA_real_,
    prevalence_apc = NA_real_,
    source = NA_character_,
    notes = "Annual proportional change. Use 0 if assuming no BAU trend."
  )
}

risk_factor_prevalence_template <- function(spec, time_grid) {
  out <- merge(
    time_grid,
    data.frame(risk_factor = spec$risk_factors, stringsAsFactors = FALSE),
    all = TRUE
  )
  transform(
    out,
    risk_category = NA_character_,
    prevalence_BAU = NA_real_,
    prevalence_intervention = NA_real_,
    source = NA_character_,
    notes = "Prevalence proportions should sum to 1 across categories."
  )
}

relative_risk_template <- function(spec, base_grid) {
  out <- merge(
    base_grid,
    expand.grid(
      risk_factor = spec$risk_factors,
      disease = spec$diseases,
      stringsAsFactors = FALSE
    ),
    all = TRUE
  )
  transform(
    out,
    risk_category = NA_character_,
    rr = NA_real_,
    rr_lower = NA_real_,
    rr_upper = NA_real_,
    reference_category = NA_character_,
    source = NA_character_,
    notes = "Reference category should have RR = 1."
  )
}

direct_effect_template <- function(spec, disease_grid) {
  unique_rows <- unique(disease_grid)
  transform(
    unique_rows,
    incidence_rr = NA_real_,
    cfr_rr = NA_real_,
    morbidity_rr = NA_real_,
    coverage = NA_real_,
    source = NA_character_,
    notes = "Use 1 for no direct effect on a rate."
  )
}

stratum_rate_ratio_template <- function(spec) {
  data.frame(
    stratum = spec$strata,
    acmr_rate_ratio = NA_real_,
    morbidity_rate_ratio = NA_real_,
    reference_stratum = NA_character_,
    source = NA_character_,
    notes = "Rate ratios are used for heterogeneity/disaggregation.",
    stringsAsFactors = FALSE
  )
}

cost_template <- function(disease_grid) {
  transform(
    disease_grid,
    disease_cost = NA_real_,
    background_cost = NA_real_,
    currency = NA_character_,
    price_year = NA_integer_,
    source = NA_character_,
    notes = "Costs should be annual per-person costs unless stated otherwise."
  )
}
