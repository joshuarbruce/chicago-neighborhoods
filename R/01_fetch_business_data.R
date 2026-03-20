# R/01_fetch_business_data.R
# Stage 2: Download active business licenses from Chicago Data Portal Socrata API.
# Output: data/raw/business_licenses/chicago_business_licenses.csv
#
# Skips download if file already exists (idempotent).
# Run: Rscript R/01_fetch_business_data.R

suppressPackageStartupMessages({
  library(httr2)
  library(readr)
  library(dplyr)
  library(here)
})

OUT_PATH <- here("data", "raw", "business_licenses", "chicago_business_licenses.csv")
ENDPOINT <- "https://data.cityofchicago.org/resource/r5kz-chrr.json"
PAGE_SIZE <- 50000L

# ---------------------------------------------------------------------------
# Guard: skip if already downloaded
# ---------------------------------------------------------------------------
if (file.exists(OUT_PATH)) {
  n_rows <- nrow(read_csv(OUT_PATH, show_col_types = FALSE))
  message("Already downloaded: ", OUT_PATH, " (", n_rows, " rows). Delete to re-download.")
  quit(save = "no", status = 0)
}

dir.create(dirname(OUT_PATH), recursive = TRUE, showWarnings = FALSE)
message("Fetching active business licenses from Chicago Data Portal...")

# ---------------------------------------------------------------------------
# Paginated download
# ---------------------------------------------------------------------------
fetch_page <- function(offset) {
  resp <- request(ENDPOINT) |>
    req_url_query(
      `$where`  = "license_status='AAC'",
      `$limit`  = PAGE_SIZE,
      `$offset` = offset,
      `$order`  = "id"
    ) |>
    req_retry(max_tries = 3, backoff = \(i) 5 * 2^(i - 1)) |>
    req_timeout(120) |>
    req_perform()

  resp_body_json(resp, simplifyVector = TRUE)
}

all_records <- list()
offset <- 0L
page <- 1L

repeat {
  message("  Page ", page, " (offset=", offset, ")...")
  records <- fetch_page(offset)
  if (length(records) == 0) break

  all_records[[page]] <- as.data.frame(records)
  message("    Got ", nrow(all_records[[page]]), " records")

  if (nrow(all_records[[page]]) < PAGE_SIZE) break
  offset <- offset + PAGE_SIZE
  page   <- page + 1L
  Sys.sleep(0.5)  # be a good API citizen
}

df <- bind_rows(all_records)
message("Total records fetched: ", nrow(df))

# ---------------------------------------------------------------------------
# Minimal type coercion before saving
# ---------------------------------------------------------------------------
df <- df |>
  mutate(
    community_area = as.character(community_area),
    latitude       = suppressWarnings(as.numeric(latitude)),
    longitude      = suppressWarnings(as.numeric(longitude))
  )

write_csv(df, OUT_PATH)
message("Saved to: ", OUT_PATH)
message("Columns: ", paste(names(df), collapse = ", "))
