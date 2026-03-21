# R/01_fetch_business_data.R
# Stage 2: Read manually downloaded business licenses CSV, filter to active, rename columns.
# Input:  data/raw/business_licenses/chicago_business_licenses_raw.csv
#         (Download from: Chicago Data Portal → dataset r5kz-chrr → Export → CSV)
# Output: data/raw/business_licenses/chicago_business_licenses.csv
#
# Skips processing if output already exists (idempotent).
# Run: Rscript R/01_fetch_business_data.R

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(here)
})

RAW_PATH <- here("data", "raw", "business_licenses", "chicago_business_licenses_raw.csv")
OUT_PATH <- here("data", "raw", "business_licenses", "chicago_business_licenses.csv")

# ---------------------------------------------------------------------------
# Guard: input must exist
# ---------------------------------------------------------------------------
if (!file.exists(RAW_PATH)) {
  stop(
    "Raw CSV not found: ", RAW_PATH, "\n",
    "Download it from the Chicago Data Portal:\n",
    "  https://data.cityofchicago.org/d/r5kz-chrr → Export → CSV\n",
    "Save as: ", RAW_PATH,
    call. = FALSE
  )
}

# ---------------------------------------------------------------------------
# Guard: skip if output already exists
# ---------------------------------------------------------------------------
if (file.exists(OUT_PATH)) {
  n_rows <- nrow(read_csv(OUT_PATH, show_col_types = FALSE))
  message("Already processed: ", OUT_PATH, " (", n_rows, " rows). Delete to reprocess.")
  quit(save = "no", status = 0)
}

# ---------------------------------------------------------------------------
# Read, filter to active licenses, rename columns to snake_case
# ---------------------------------------------------------------------------
message("Reading: ", RAW_PATH)
raw <- read_csv(RAW_PATH, show_col_types = FALSE)
message("Total rows: ", nrow(raw))

df <- raw |>
  filter(`LICENSE STATUS` == "AAC") |>
  transmute(
    id                   = ID,
    license_id           = `LICENSE ID`,
    legal_name           = `LEGAL NAME`,
    doing_business_as    = `DOING BUSINESS AS NAME`,
    address              = ADDRESS,
    community_area       = as.character(`COMMUNITY AREA`),
    community_area_name  = `COMMUNITY AREA NAME`,
    license_code         = `LICENSE CODE`,
    license_description  = `LICENSE DESCRIPTION`,
    business_activity_id = `BUSINESS ACTIVITY ID`,
    business_activity    = `BUSINESS ACTIVITY`,
    license_status       = `LICENSE STATUS`,
    license_term_start   = `LICENSE TERM START DATE`,
    license_term_expiry  = `LICENSE TERM EXPIRATION DATE`,
    latitude             = suppressWarnings(as.numeric(LATITUDE)),
    longitude            = suppressWarnings(as.numeric(LONGITUDE))
  )

message("Active licenses (AAC): ", nrow(df))

write_csv(df, OUT_PATH)
message("Saved to: ", OUT_PATH)
