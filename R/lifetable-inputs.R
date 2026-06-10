#' Expand age-banded census templates into exact-age lifetable inputs
#'
#' The all-cause main lifetable engine ([run_pmslt_lifetable_bau()] and
#' [run_pmslt_lifetable_interventions()]) works on exact single-year ages, but
#' the raw `01_population.csv`, `02_all_cause_mortality.csv`, and
#' `03_all_cause_morbidity.csv` templates are written in age bands. This helper
#' bridges the two by expanding each closed age band to single years using an
#' explicit, documented rule:
#'
#' * Population counts (`initial_population`) are split **uniformly** across the
#'   single years in the band, so the band total is preserved.
#' * Rates (`acmr_BAU` mortality, `pYLD_BAU` morbidity) are held **constant**
#'   within the band.
#'
#' Tables that already use an exact single-year `age` column are returned
#' unchanged, so the helper is safe to apply to either format.
#'
#' @param population,mortality,morbidity Data frames or CSV paths in the raw
#'   template format (or already exact-age). Default to the numbered files in
#'   `input_dir`. `morbidity` is optional.
#' @param input_dir Optional directory holding the numbered templates, used to
#'   locate any input not supplied explicitly.
#'
#' @return A list with exact-age `population`, `mortality`, and `morbidity`
#'   (the last `NULL` when no morbidity input is available), ready to pass to the
#'   main lifetable functions or [run_pmslt()].
#' @export
#'
#' @examples
#' \dontrun{
#' inputs <- prepare_lifetable_inputs(input_dir = "inputs_raw")
#' run_pmslt_lifetable_bau(inputs$population, inputs$mortality, inputs$morbidity)
#' }
prepare_lifetable_inputs <- function(population = NULL,
                                     mortality = NULL,
                                     morbidity = NULL,
                                     input_dir = NULL) {
  population <- resolve_run_pmslt_input(population, input_dir, "01_population.csv",
                                        required = TRUE, label = "population")
  mortality <- resolve_run_pmslt_input(mortality, input_dir, "02_all_cause_mortality.csv",
                                       required = TRUE, label = "mortality")
  morbidity <- resolve_run_pmslt_input(morbidity, input_dir, "03_all_cause_morbidity.csv",
                                       required = FALSE, label = "morbidity")

  list(
    population = expand_lifetable_band_table(
      population, "population", count_cols = "initial_population", rate_cols = character()
    ),
    mortality = expand_lifetable_band_table(
      mortality, "mortality", count_cols = character(), rate_cols = "acmr_BAU"
    ),
    morbidity = if (is.null(morbidity)) {
      NULL
    } else {
      expand_lifetable_band_table(
        morbidity, "morbidity", count_cols = character(), rate_cols = "pYLD_BAU"
      )
    }
  )
}

# Expand one banded template to exact single-year ages. Count columns are split
# uniformly across the band; rate columns are held constant. Exact-age inputs
# (those that already carry an `age` column) are returned unchanged.
expand_lifetable_band_table <- function(data, label, count_cols, rate_cols) {
  data <- read_lifetable_input(data, label)
  if ("age" %in% names(data)) {
    return(data)
  }
  required <- c("age_start", "age_end", "sex", "stratum")
  missing_cols <- setdiff(required, names(data))
  if (length(missing_cols) > 0) {
    stop(
      "`", label, "` must have either an exact-age `age` column or banded ",
      "`age_start`/`age_end` columns. Missing: ",
      paste(missing_cols, collapse = ", "), ".",
      call. = FALSE
    )
  }

  age_start <- as.numeric(data$age_start)
  age_end <- as.numeric(data$age_end)
  if (any(is.na(age_start)) || any(is.na(age_end))) {
    stop("`", label, "` has missing `age_start` or `age_end` values.", call. = FALSE)
  }
  if (any(age_start != floor(age_start)) || any(age_end != floor(age_end))) {
    stop("`", label, "` age bands must use whole-number ages.", call. = FALSE)
  }
  if (any(age_end < age_start)) {
    stop("`", label, "` has an age band where `age_end` is before `age_start`.", call. = FALSE)
  }

  drop_cols <- intersect(c("age_start", "age_end", "age_label"), names(data))
  value_cols <- c(count_cols, rate_cols)
  rows <- lapply(seq_len(nrow(data)), function(i) {
    ages <- seq.int(age_start[[i]], age_end[[i]])
    width <- length(ages)
    expanded <- data[rep(i, width), setdiff(names(data), drop_cols), drop = FALSE]
    expanded$age <- ages
    for (col in count_cols) {
      expanded[[col]] <- as.numeric(data[[col]][[i]]) / width
    }
    for (col in rate_cols) {
      expanded[[col]] <- as.numeric(data[[col]][[i]])
    }
    expanded
  })
  out <- do.call(rbind, rows)
  row.names(out) <- NULL

  key <- c("age", "sex", "stratum")
  if (any(duplicated(out[key]))) {
    stop(
      "`", label, "` has overlapping age bands: the same age appears in more ",
      "than one band for a sex/stratum.",
      call. = FALSE
    )
  }
  out[c(key, value_cols, setdiff(names(out), c(key, value_cols)))]
}
