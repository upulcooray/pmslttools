# Central schema definitions.
#
# Raw input template schemas and PMSLT-ready post-DisMod schemas are deliberately
# kept separate. Raw schemas describe user-filled collection templates. PMSLT-
# ready schemas describe files consumed by downstream model modules.

pmslt_input_schemas <- function() {
  files <- template_file_dictionary()
  requirements <- column_requirement_dictionary()
  validations <- column_validation_dictionary()

  lapply(names(files), function(template_name) {
    columns <- names(files[[template_name]]$columns)
    schema <- data.frame(
      column = columns,
      requirement = vapply(columns, function(column) {
        column_requirement(template_name, column)
      }, character(1)),
      description = unname(unlist(files[[template_name]]$columns, use.names = FALSE)),
      validation_type = vapply(columns, function(column) {
        value <- validations[[template_name]][[column]]
        if (is.null(value) || is.null(value$type)) {
          "none"
        } else {
          value$type
        }
      }, character(1)),
      allowed_values = vapply(columns, function(column) {
        value <- validations[[template_name]][[column]]
        if (is.null(value) || is.null(value$allowed_values)) {
          ""
        } else {
          paste(value$allowed_values, collapse = "; ")
        }
      }, character(1)),
      stringsAsFactors = FALSE
    )

    list(
      file = paste0(template_name, ".csv"),
      template_name = template_name,
      purpose = files[[template_name]]$purpose,
      rows = files[[template_name]]$rows,
      columns = schema,
      key_columns = raw_template_key_columns(template_name),
      checks = files[[template_name]]$checks,
      requirement_groups = requirements[[template_name]]
    )
  }) |>
    stats::setNames(names(files))
}

raw_template_key_columns <- function(template_name) {
  switch(
    template_name,
    "00_column_dictionary" = c("file", "column"),
    "00_model_specification" = "field",
    "01_population" = c("age_start", "sex", "stratum"),
    "02_all_cause_mortality" = c("age_start", "sex", "stratum"),
    "03_all_cause_morbidity" = c("age_start", "sex", "stratum"),
    "04_life_expectancy" = c("age", "sex", "stratum"),
    "05_disease_epidemiology_raw" = c("age_start", "sex", "stratum", "disease"),
    "06_dismod_input_skeleton" = c("age_start", "sex", "stratum", "disease", "parameter"),
    "07_bau_trends" = "disease",
    "08_risk_factor_prevalence" = c("age_start", "sex", "stratum", "time_step", "intervention", "risk_factor", "risk_category"),
    "09_relative_risks" = c("age_start", "sex", "stratum", "risk_factor", "disease", "risk_category"),
    "10_direct_intervention_effects" = c("age_start", "sex", "stratum", "disease", "intervention"),
    "11_stratum_rate_ratios" = c("age_start", "sex", "stratum", "parameter"),
    "12_costs" = c("age_start", "sex", "stratum", "disease"),
    character()
  )
}

template_file_dictionary <- function() {
  id_age <- "Generated age-band start. Do not edit in the CSV. If the age bands are wrong, regenerate the templates using `age_bands()`."
  id_age_end <- "Generated age-band end. `Inf` means the final open-ended age band, such as 100+. Do not edit manually."
  id_age_label <- "Human-readable age-band label. Keep as generated so files can be checked and joined safely."
  id_sex <- "Generated sex group from `pmslt_spec(sexes = ...)`. Use the same labels in all files."
  id_stratum <- "Generated population stratum from `pmslt_spec(strata = ...)`. For an unstratified model this is usually `total`."
  id_disease <- "Generated disease name from `pmslt_spec(diseases = ...)`. Keep spelling identical across files."
  id_source <- "Enter the data source, such as census year, GBD release, registry name, study citation, table number, or URL."
  id_notes <- "Optional free-text notes. Use this for assumptions, conversions, caveats, or reasons a value is blank."

  list(
    "00_column_dictionary" = schema_file(
      "Lists every generated template column and whether the user must fill it.",
      "One row per file and column.",
      list(
        file = "Generated template filename.",
        column = "Column name in that template.",
        requirement = "Whether the column is generated, required, conditional, or optional.",
        description = "Plain-language guidance on how to fill or interpret the column.",
        validation_type = "Machine-readable validation category for future raw input checks.",
        allowed_values = "Allowed values where the schema can enumerate them."
      ),
      c(
        "Use this file as the quick reference for which fields must be filled.",
        "Required and conditional fields are also marked with `*` in `README_inputs_raw.md`."
      )
    ),
    "00_model_specification" = schema_file(
      "Records the model design used to generate the templates. This is mainly for checking and documentation.",
      "One row per model specification field.",
      list(
        field = "Generated specification field name. Do not edit unless correcting the model design.",
        value = "Generated value used by the package. Review this file first; if these values are wrong, regenerate the templates rather than editing all CSVs manually.",
        notes = "Explanation of what each model specification field means."
      ),
      c(
        "Confirm the diseases, risk factors, age range, sex groups, strata, and horizon are correct.",
        "If anything is wrong, edit the R call to `pmslt_spec()` and regenerate the templates."
      )
    ),
    "01_population" = schema_file(
      "Collects base-year population counts. These initialize the main lifetable cohorts.",
      "One row per age, sex, and stratum combination.",
      list(
        age_start = id_age,
        age_end = id_age_end,
        age_label = id_age_label,
        sex = id_sex,
        stratum = id_stratum,
        initial_population = "Required. Enter the number of people alive in the base year for this age, sex, and stratum. Use counts, not rates or proportions. Decimals are acceptable only if the source gives modelled population estimates.",
        source = id_source,
        notes = id_notes
      ),
      c(
        "`initial_population` should be non-negative in every row.",
        "Population totals should match your census or official population source after summing rows.",
        "Do not enter population percentages here."
      )
    ),
    "02_all_cause_mortality" = schema_file(
      "Collects business-as-usual all-cause mortality rates for the main lifetable.",
      "One row per age, sex, and stratum combination.",
      list(
        age_start = id_age,
        age_end = id_age_end,
        age_label = id_age_label,
        sex = id_sex,
        stratum = id_stratum,
        acmr_BAU = "Required. Enter the all-cause mortality rate under business-as-usual. Unit: deaths per person-year. Example: 800 deaths per 100,000 person-years becomes 0.008. This is not disease-specific mortality.",
        source = id_source,
        notes = "Use this to record whether the rate came from observed deaths, life tables, GBD, or a forecast. Also record any conversion from deaths per 100,000."
      ),
      c(
        "`acmr_BAU` should be non-negative.",
        "Older age groups should usually have higher mortality than younger age groups.",
        "Do not paste cause-specific mortality into this file."
      )
    ),
    "03_all_cause_morbidity" = schema_file(
      "Collects all-cause background morbidity for HALY calculations.",
      "One row per age, sex, and stratum combination.",
      list(
        age_start = id_age,
        age_end = id_age_end,
        age_label = id_age_label,
        sex = id_sex,
        stratum = id_stratum,
        pYLD_BAU = "Required for HALYs. Enter prevalent years lived with disability per person under business-as-usual. This is often calculated as total prevalent YLD divided by population for the demographic group. It should usually be between 0 and 1.",
        source = id_source,
        notes = "Record whether this came from GBD, national burden of disease estimates, or another source."
      ),
      c(
        "`pYLD_BAU` should usually be between 0 and 1.",
        "This is all-cause morbidity, not disease-specific disability weight.",
        "If only DALYs are being modelled later, still keep the source traceable."
      )
    ),
    "04_life_expectancy" = schema_file(
      "Collects reference life expectancy used to calculate years of life lost.",
      "One row per age start, sex, and stratum combination.",
      list(
        age = "Generated age value. It should match the start of each model age band.",
        sex = id_sex,
        stratum = id_stratum,
        expected_years_remaining = "Required for DALY/YLL calculations. Enter remaining life expectancy at this age, sex, and stratum from the chosen reference life table. If a single common standard is used, repeat the same value across sexes and strata.",
        source = id_source,
        notes = "Record the life table used, country or standard population, year, and whether values are sex-specific, stratum-specific, or common across groups."
      ),
      c(
        "`expected_years_remaining` should be non-negative.",
        "Values should generally decline as age increases within each sex and stratum.",
        "Use the same reference life table consistently across the project.",
        "For a single common standard, enter identical values across sexes and strata rather than leaving rows blank."
      )
    ),
    "05_disease_epidemiology_raw" = schema_file(
      "Collects raw disease-specific epidemiological parameters before DisMod. This file tells the package what is known and what DisMod may need to estimate.",
      "One row per age, sex, stratum, and disease combination.",
      list(
        age_start = id_age,
        age_end = id_age_end,
        age_label = id_age_label,
        sex = id_sex,
        stratum = id_stratum,
        disease = id_disease,
        incidence_rate = "Enter disease incidence rate per person-year if available. Example: 150 per 100,000 person-years becomes 0.0015. Leave blank if unavailable and intended for DisMod.",
        prevalence = "Enter disease prevalence as a proportion between 0 and 1 if available. Example: 8 percent becomes 0.08. This is the proportion with disease at baseline.",
        remission_rate = "Enter remission rate per person-year if relevant. For many chronic non-remitting diseases, enter 0 if that is the explicit modelling assumption. Leave blank only if remission is unknown and should be estimated or reviewed.",
        excess_mortality_rate = "Enter excess mortality among people with the disease, per person-year, if available. This is not the all-cause mortality rate and not disease-specific mortality evidence.",
        disease_mortality_rate = "Enter disease-specific mortality evidence per person-year if available, such as mortality attributable to this disease. This is the `mortality` evidence used by disease consistency solvers and is distinct from `excess_mortality_rate`.",
        case_fatality_rate = "Enter the case fatality rate per person-year if this is the parameter used by your disease model. Do not duplicate excess mortality unless that equivalence is a deliberate assumption.",
        disability_weight = "Enter disease-specific disability weight between 0 and 1. Example: 0 means no disability and 1 means equivalent to death. This is not all-cause pYLD.",
        source = id_source,
        notes = "Record assumptions, especially when remission is set to 0 or when incidence/prevalence values were converted from published units."
      ),
      c(
        "For DisMod-lite, aim to provide at least three of incidence, prevalence, remission, excess mortality, and case fatality.",
        "`disease_mortality_rate` is disease-specific mortality evidence for consistency solvers; do not fill it by copying excess mortality unless that is a documented source assumption.",
        "Use blank for unknown values, not zero.",
        "Prevalence and disability weight should be between 0 and 1."
      )
    ),
    "06_dismod_input_skeleton" = schema_file(
      "Provides a long-format disease-consistency solver evidence skeleton. This can be filled directly or populated from `05_disease_epidemiology_raw.csv`.",
      "One row per age, sex, stratum, disease, and solver evidence parameter.",
      list(
        age_start = id_age,
        age_end = id_age_end,
        age_label = id_age_label,
        sex = id_sex,
        stratum = id_stratum,
        disease = id_disease,
        parameter = "Generated solver evidence parameter name. Allowed values include incidence, prevalence, remission, excess_mortality, case_fatality, and mortality. `mortality` means disease-specific mortality evidence, not excess mortality among people with disease.",
        mean_value = "Enter the best estimate for this parameter. Use per person-year for rates and 0 to 1 for proportions.",
        lower_95 = "Optional. Enter lower 95 percent uncertainty bound on the same scale as `mean_value`.",
        upper_95 = "Optional. Enter upper 95 percent uncertainty bound on the same scale as `mean_value`.",
        sample_size = "Optional. Enter sample size or effective sample size if the source provides it. Leave blank if unknown.",
        data_source = id_source,
        quality_flag = "Optional. Use simple values such as High, Medium, or Low to record confidence in the estimate.",
        notes = id_notes
      ),
      c(
        "`lower_95` should be less than or equal to `mean_value`; `upper_95` should be greater than or equal to `mean_value`.",
        "Prevalence rows are proportions, while incidence, remission, mortality, excess mortality, and case fatality rows are rates.",
        "`mortality` is explicit disease-specific mortality evidence for consistency solvers and must not be inferred from `excess_mortality`.",
        "DisMod-lite usually needs at least three epidemiological parameter types per disease."
      )
    ),
    "07_bau_trends" = schema_file(
      "Collects annual business-as-usual trend assumptions for disease rates.",
      "One row per disease.",
      list(
        disease = id_disease,
        incidence_apc = "Enter annual proportional change in incidence. Example: -0.02 means incidence declines by 2 percent per year. Enter 0 if assuming no BAU trend.",
        cfr_apc = "Enter annual proportional change in case fatality or excess mortality, depending on the disease model. Example: -0.015 means a 1.5 percent annual decline.",
        prevalence_apc = "Optional. Enter annual proportional change in prevalence if you are explicitly modelling prevalence trends outside the disease lifetable. Often this can be left blank.",
        source = id_source,
        notes = "Record how the annual percentage change was estimated, such as Poisson regression, log-linear trend, GBD forecast, or expert assumption."
      ),
      c(
        "Use proportions, not percentages: -2 percent is -0.02.",
        "Enter 0 for deliberately flat trends.",
        "Do not leave trend cells blank if the intended assumption is no change."
      )
    ),
    "08_risk_factor_prevalence" = schema_file(
      "Collects business-as-usual and intervention risk-factor distributions used to calculate PIFs.",
      "One row per age, sex, stratum, time step, and risk factor. Add or duplicate rows for each risk category as needed.",
      list(
        age_start = id_age,
        age_end = id_age_end,
        age_label = id_age_label,
        sex = id_sex,
        stratum = id_stratum,
        time_step = "Generated simulation cycle, where 0 is the base year. Keep this as an integer annual time step.",
        intervention = "Generated intervention arm from `pmslt_spec(intervention_arms = ...)`. Fill `prevalence_intervention` for this specific scenario.",
        risk_factor = "Generated risk factor name. For example: Smoking, BMI, sodium intake.",
        risk_category = "Generated exposure category from `pmslt_spec(risk_categories = ...)`. Examples for smoking: Never, Current, Former_1_5_years, Former_5_plus_years. Regenerate the templates if categories are wrong.",
        prevalence_BAU = "Required for each category. Enter the BAU prevalence proportion for this age, sex, stratum, time step, and category.",
        prevalence_intervention = "Required for PIF-based intervention modelling. Enter the counterfactual intervention prevalence proportion for the same category. If the intervention has no effect in a row, copy `prevalence_BAU`. The PIF cannot be calculated without this intervention distribution.",
        source = id_source,
        notes = "Record intervention assumptions, time-lag assumptions, or how prevalence was projected over time."
      ),
      c(
        "Within each age, sex, stratum, time step, and risk factor, category prevalences should sum to 1 for BAU and intervention.",
        "Risk category labels must exactly match the labels used in `09_relative_risks.csv`.",
        "Use proportions, not percentages."
      )
    ),
    "09_relative_risks" = schema_file(
      "Collects relative risks connecting risk-factor categories to disease incidence.",
      "One row per age, sex, stratum, risk factor, disease, and risk category.",
      list(
        age_start = id_age,
        age_end = id_age_end,
        age_label = id_age_label,
        sex = id_sex,
        stratum = id_stratum,
        risk_factor = "Generated risk factor name. Must match `08_risk_factor_prevalence.csv`.",
        disease = id_disease,
        risk_category = "Generated exposure category from `pmslt_spec(risk_categories = ...)`. Must exactly match `08_risk_factor_prevalence.csv` because both files are generated from the same specification.",
        rr = "Required. Enter the relative risk for this category and disease. The reference category should be 1. Values above 1 increase disease incidence; values below 1 are protective.",
        rr_lower = "Optional. Lower uncertainty bound for the relative risk.",
        rr_upper = "Optional. Upper uncertainty bound for the relative risk.",
        reference_category = "Enter the reference category label, such as Never or Normal weight. This helps reviewers see which group has RR = 1.",
        source = id_source,
        notes = "Record citation, adjustment set, whether RR came from HR/OR conversion, and any age or sex assumptions."
      ),
      c(
        "Every risk category in `08_risk_factor_prevalence.csv` should have a matching RR row for each affected disease.",
        "Reference category RR should be 1.",
        "Do not enter odds ratios as RRs unless the conversion or rare-disease assumption is justified in `notes`."
      )
    ),
    "10_direct_intervention_effects" = schema_file(
      "Collects direct intervention effects for models where the intervention acts on disease incidence, case fatality, morbidity, or coverage directly.",
      "One row per age, sex, stratum, and disease combination.",
      list(
        age_start = id_age,
        age_end = id_age_end,
        age_label = id_age_label,
        sex = id_sex,
        stratum = id_stratum,
        disease = id_disease,
        intervention = "Generated intervention arm from `pmslt_spec(intervention_arms = ...)`. Direct disease effects are scenario-specific.",
        incidence_rr = "Enter direct relative risk multiplier for incidence. Use 1 for no effect. Example: 0.9 means a 10 percent incidence reduction.",
        cfr_rr = "Enter direct relative risk multiplier for case fatality. Use 1 for no effect.",
        morbidity_rr = "Enter direct multiplier for disease morbidity or disability weight. Use 1 for no effect.",
        coverage = "Enter intervention coverage as a proportion between 0 and 1.",
        source = id_source,
        notes = id_notes
      ),
      c(
        "Use 1, not blank, when there is deliberately no effect on a rate.",
        "Coverage should be between 0 and 1.",
        "Do not mix direct effects with PIF effects unless the model specification says `mechanism = \"both\"`."
      )
    ),
    "11_stratum_rate_ratios" = schema_file(
      "Collects rate ratios needed to disaggregate aggregate rates across equity or population strata.",
      "One row per age, sex, stratum, and disaggregated parameter.",
      list(
        age_start = id_age,
        age_end = id_age_end,
        age_label = id_age_label,
        sex = id_sex,
        stratum = id_stratum,
        parameter = "Generated parameter to disaggregate. Allowed values are acmr, morbidity, incidence, remission, excess_mortality, case_fatality, and mortality.",
        rate_ratio = "Enter the rate ratio for this stratum and parameter compared with the reference stratum.",
        reference_stratum = "Enter the stratum used as the reference, such as Least_deprived or Q5. The reference stratum usually has rate ratio 1.",
        source = id_source,
        notes = "Record whether ratios are observed for this age-sex group, age-standardised, disease-specific, or borrowed from another population."
      ),
      c(
        "Reference stratum should usually have rate ratio 1.",
        "Rate ratios should be positive.",
        "Each generated age, sex, stratum, and parameter combination should have one row.",
        "Be explicit about whether the direction is deprived versus least deprived or the reverse."
      )
    ),
    "12_costs" = schema_file(
      "Collects cost inputs for cost-effectiveness analysis.",
      "One row per age, sex, stratum, and disease combination.",
      list(
        age_start = id_age,
        age_end = id_age_end,
        age_label = id_age_label,
        sex = id_sex,
        stratum = id_stratum,
        disease = id_disease,
        disease_cost = "Enter annual cost per prevalent disease case, in the selected currency and price year.",
        background_cost = "Enter annual non-disease-specific health-system cost per person, if used. Leave blank if background costs are handled elsewhere.",
        currency = "Enter currency code, such as AUD, NZD, USD, or GBP.",
        price_year = "Enter the price year for costs, such as 2024.",
        source = id_source,
        notes = "Record whether costs are health-system, societal, patient, intervention, or disease-management costs."
      ),
      c(
        "Costs should be non-negative.",
        "Keep currency and price year consistent.",
        "Do not mix one-off intervention costs with annual disease-management costs without noting the difference."
      )
    )
  )
}

schema_file <- function(purpose, rows, columns, checks) {
  list(
    purpose = purpose,
    rows = rows,
    columns = columns,
    checks = checks
  )
}

column_dictionary_template <- function(templates) {
  schemas <- pmslt_input_schemas()
  rows <- lapply(names(templates), function(template_name) {
    schema <- schemas[[template_name]]
    columns <- names(templates[[template_name]])
    schema_columns <- schema$columns[match(columns, schema$columns$column), ]
    missing_schema <- is.na(schema_columns$column)
    if (any(missing_schema)) {
      schema_columns[missing_schema, ] <- data.frame(
        column = columns[missing_schema],
        requirement = "generated",
        description = "Generated package column. Keep unchanged unless you know this field is wrong.",
        validation_type = "none",
        allowed_values = "",
        stringsAsFactors = FALSE
      )
    }

    data.frame(
      file = paste0(template_name, ".csv"),
      schema_columns,
      row.names = NULL,
      stringsAsFactors = FALSE
    )
  })

  do.call(rbind, rows)
}

column_requirement <- function(template_name, column) {
  req <- column_requirement_dictionary()[[template_name]]
  if (is.null(req)) {
    return("generated")
  }

  for (requirement in names(req)) {
    if (column %in% req[[requirement]]) {
      return(requirement)
    }
  }

  "generated"
}

column_requirement_dictionary <- function() {
  common_generated <- c(
    "age_start", "age_end", "age_label", "sex", "stratum", "disease",
    "time_step", "intervention", "risk_factor", "risk_category", "parameter",
    "age", "field", "value"
  )

  list(
    "00_column_dictionary" = list(
      generated = c("file", "column", "requirement", "description", "validation_type", "allowed_values")
    ),
    "00_model_specification" = list(
      generated = c("field", "value", "notes")
    ),
    "01_population" = list(
      generated = common_generated,
      required = c("initial_population", "source"),
      optional = "notes"
    ),
    "02_all_cause_mortality" = list(
      generated = common_generated,
      required = c("acmr_BAU", "source"),
      optional = "notes"
    ),
    "03_all_cause_morbidity" = list(
      generated = common_generated,
      required = c("pYLD_BAU", "source"),
      optional = "notes"
    ),
    "04_life_expectancy" = list(
      generated = common_generated,
      required = c("expected_years_remaining", "source"),
      optional = "notes"
    ),
    "05_disease_epidemiology_raw" = list(
      generated = common_generated,
      conditional = c(
        "incidence_rate", "prevalence", "remission_rate",
        "excess_mortality_rate", "disease_mortality_rate",
        "case_fatality_rate"
      ),
      required = c("disability_weight", "source"),
      optional = "notes"
    ),
    "06_dismod_input_skeleton" = list(
      generated = common_generated,
      conditional = c(
        "mean_value", "lower_95", "upper_95", "sample_size",
        "data_source", "quality_flag"
      ),
      optional = "notes"
    ),
    "07_bau_trends" = list(
      generated = common_generated,
      required = c("incidence_apc", "cfr_apc", "source"),
      optional = c("prevalence_apc", "notes")
    ),
    "08_risk_factor_prevalence" = list(
      generated = common_generated,
      required = c("prevalence_BAU", "prevalence_intervention", "source"),
      optional = "notes"
    ),
    "09_relative_risks" = list(
      generated = common_generated,
      required = c("rr", "reference_category", "source"),
      optional = c("rr_lower", "rr_upper", "notes")
    ),
    "10_direct_intervention_effects" = list(
      generated = common_generated,
      required = c("incidence_rr", "cfr_rr", "morbidity_rr", "coverage", "source"),
      optional = "notes"
    ),
    "11_stratum_rate_ratios" = list(
      generated = common_generated,
      required = c("rate_ratio", "reference_stratum", "source"),
      optional = "notes"
    ),
    "12_costs" = list(
      generated = common_generated,
      required = c("disease_cost", "currency", "price_year", "source"),
      optional = c("background_cost", "notes")
    )
  )
}

column_validation_dictionary <- function() {
  rate <- list(type = "non_negative_rate")
  non_negative <- list(type = "non_negative_number")
  proportion <- list(type = "proportion_0_1")
  relative_risk <- list(type = "positive_number")
  annual_change <- list(type = "annual_proportional_change")
  text <- list(type = "text")
  generated <- list(type = "generated_id")
  integer <- list(type = "integer")
  year <- list(type = "calendar_year")
  currency <- list(type = "currency_code")

  common_generated <- list(
    age_start = generated,
    age_end = generated,
    age_label = generated,
    sex = generated,
    stratum = generated,
    disease = generated,
    time_step = integer,
    intervention = generated,
    risk_factor = generated,
    risk_category = generated,
    age = generated,
    field = generated,
    value = generated
  )

  with_common <- function(x) utils::modifyList(common_generated, x)

  list(
    "00_column_dictionary" = list(
      file = text,
      column = text,
      requirement = list(type = "allowed_values", allowed_values = c("generated", "required", "conditional", "optional")),
      description = text,
      validation_type = text,
      allowed_values = text
    ),
    "00_model_specification" = list(field = generated, value = text, notes = text),
    "01_population" = with_common(list(initial_population = non_negative, source = text, notes = text)),
    "02_all_cause_mortality" = with_common(list(acmr_BAU = rate, source = text, notes = text)),
    "03_all_cause_morbidity" = with_common(list(pYLD_BAU = proportion, source = text, notes = text)),
    "04_life_expectancy" = with_common(list(expected_years_remaining = non_negative, source = text, notes = text)),
    "05_disease_epidemiology_raw" = with_common(list(
      incidence_rate = rate,
      prevalence = proportion,
      remission_rate = rate,
      excess_mortality_rate = rate,
      disease_mortality_rate = rate,
      case_fatality_rate = rate,
      disability_weight = proportion,
      source = text,
      notes = text
    )),
    "06_dismod_input_skeleton" = with_common(list(
      parameter = list(type = "allowed_values", allowed_values = c("incidence", "prevalence", "remission", "excess_mortality", "case_fatality", "mortality")),
      mean_value = list(type = "dismod_parameter_value"),
      lower_95 = list(type = "dismod_parameter_value"),
      upper_95 = list(type = "dismod_parameter_value"),
      sample_size = non_negative,
      data_source = text,
      quality_flag = text,
      notes = text
    )),
    "07_bau_trends" = with_common(list(incidence_apc = annual_change, cfr_apc = annual_change, prevalence_apc = annual_change, source = text, notes = text)),
    "08_risk_factor_prevalence" = with_common(list(prevalence_BAU = proportion, prevalence_intervention = proportion, source = text, notes = text)),
    "09_relative_risks" = with_common(list(rr = relative_risk, rr_lower = relative_risk, rr_upper = relative_risk, reference_category = text, source = text, notes = text)),
    "10_direct_intervention_effects" = with_common(list(incidence_rr = relative_risk, cfr_rr = relative_risk, morbidity_rr = relative_risk, coverage = proportion, source = text, notes = text)),
    "11_stratum_rate_ratios" = with_common(list(
      parameter = list(type = "allowed_values", allowed_values = c("acmr", "morbidity", "incidence", "remission", "excess_mortality", "case_fatality", "mortality")),
      rate_ratio = relative_risk,
      reference_stratum = text,
      source = text,
      notes = text
    )),
    "12_costs" = with_common(list(disease_cost = non_negative, background_cost = non_negative, currency = currency, price_year = year, source = text, notes = text))
  )
}

pmslt_ready_input_schemas <- function() {
  list(
    pmslt_disease_epi = pmslt_disease_epi_schema()
  )
}

pmslt_disease_epi_schema <- function() {
  columns <- list(
    age = "Exact single-year age used by downstream PMSLT simulation modules. This is the canonical post-DisMod age column.",
    sex = "Sex group used by downstream PMSLT modules.",
    stratum = "Population stratum used by downstream PMSLT modules.",
    disease = "Disease name. This should match the disease labels used in the model specification.",
    time_step = "Simulation cycle, where 0 is the base year. This is the package's canonical time column for PMSLT disease modules.",
    incidence_BAU = "Business-as-usual disease incidence rate per person-year for this cycle.",
    prevalence_initial = "Disease prevalence at baseline as a proportion between 0 and 1. Required at time_step 0 for every age, sex, stratum, and disease group; later cycles may be blank.",
    remission_rate = "Disease remission rate per person-year.",
    excess_mortality_BAU = "Business-as-usual excess mortality rate among people with the disease, per person-year.",
    case_fatality_BAU = "Business-as-usual case fatality rate per person-year.",
    disability_weight = "Disease-specific disability weight between 0 and 1.",
    prevalence_BAU_reference = "Optional reference prevalence trajectory from DisMod output and BAU trend assumptions. This is not the dynamic prevalence calculated by the disease lifetable.",
    incidence_apc = "Optional annual proportional change applied to incidence_BAU.",
    cfr_apc = "Optional annual proportional change applied to case_fatality_BAU and excess_mortality_BAU.",
    prevalence_apc = "Optional annual proportional change applied to prevalence_BAU_reference.",
    input_source = "Optional provenance note describing how the PMSLT-ready disease file was produced."
  )

  validations <- pmslt_disease_epi_validation_dictionary()
  column_names <- names(columns)
  schema <- data.frame(
    column = column_names,
    requirement = ifelse(
      column_names %in% pmslt_disease_epi_required_columns(),
      "required",
      "optional"
    ),
    description = unname(unlist(columns, use.names = FALSE)),
    validation_type = vapply(column_names, function(column) {
      validations[[column]]$type
    }, character(1)),
    allowed_values = "",
    stringsAsFactors = FALSE
  )

  list(
    file = "pmslt_disease_epi.csv",
    template_name = "pmslt_disease_epi",
    input_stage = "pmslt_ready",
    purpose = paste(
      "Canonical post-DisMod disease epidemiology input consumed by downstream",
      "PMSLT disease modules."
    ),
    rows = paste(
      "One row per exact single-year age, sex, stratum, disease, and time_step combination.",
      "time_step 0 stores baseline prevalence in prevalence_initial."
    ),
    columns = schema,
    checks = c(
      "Raw disease epidemiology may remain age-banded in 05_disease_epidemiology_raw.csv and is validated by validate_raw_inputs().",
      "solve_disease_consistency() writes this canonical PMSLT-ready file from checked disease consistency solver outputs.",
      "Downstream disease modules should consume pmslt_disease_epi.csv rather than raw disease epidemiology or intermediate solver diagnostic files.",
      "The PMSLT-ready disease file uses exact integer age; age_start, age_end, and age_label belong to raw inputs or diagnostic/reporting files.",
      "Rates should be non-negative and per person-year.",
      "prevalence_initial and disability_weight should be between 0 and 1."
    )
  )
}

pmslt_disease_epi_required_columns <- function() {
  c(
    "age", "sex", "stratum", "disease",
    "time_step", "incidence_BAU", "prevalence_initial", "remission_rate",
    "excess_mortality_BAU", "case_fatality_BAU", "disability_weight"
  )
}

pmslt_disease_epi_validation_dictionary <- function() {
  generated <- list(type = "generated_id")
  rate <- list(type = "non_negative_rate")
  proportion <- list(type = "proportion_0_1")
  annual_change <- list(type = "annual_proportional_change")
  integer <- list(type = "integer")
  text <- list(type = "text")

  list(
    age = integer,
    sex = generated,
    stratum = generated,
    disease = generated,
    time_step = integer,
    incidence_BAU = rate,
    prevalence_initial = proportion,
    remission_rate = rate,
    excess_mortality_BAU = rate,
    case_fatality_BAU = rate,
    disability_weight = proportion,
    prevalence_BAU_reference = proportion,
    incidence_apc = annual_change,
    cfr_apc = annual_change,
    prevalence_apc = annual_change,
    input_source = text
  )
}
