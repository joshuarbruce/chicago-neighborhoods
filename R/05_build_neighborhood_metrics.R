# R/05_build_neighborhood_metrics.R
# Stage 7: Join all sources into a single 77-row master dataset.
# Output: data/processed/neighborhood_metrics.rds
#
# Run: Rscript R/05_build_neighborhood_metrics.R

suppressPackageStartupMessages({
  library(tidyverse)
  library(assertthat)
  library(here)
})

BIZ_PATH     <- here("data", "processed", "business_summary.rds")
SENT_PATH    <- here("data", "processed", "sentiment_scores.rds")
AIRBNB_PATH  <- here("data", "processed", "airbnb_summary.rds")
SUMMARY_DIR  <- here("data", "processed", "ai_summaries")
LOOKUP_PATH  <- here("data", "reference", "community_area_lookup.csv")
OUT_PATH     <- here("data", "processed", "neighborhood_metrics.rds")

# ---------------------------------------------------------------------------
# Load
# ---------------------------------------------------------------------------
message("Loading processed data...")
biz_data    <- readRDS(BIZ_PATH)
biz_summary <- biz_data$summary
biz_cats    <- biz_data$by_category
sentiment   <- readRDS(SENT_PATH)
lookup      <- read_csv(LOOKUP_PATH, show_col_types = FALSE)

airbnb_summary <- if (file.exists(AIRBNB_PATH)) {
  message("Loading Airbnb summary...")
  readRDS(AIRBNB_PATH)$summary |>
    select(slug, airbnb_listing_count, airbnb_median_price,
           airbnb_avg_rating, airbnb_data_flag, airbnb_sentiment_label)
} else {
  message("airbnb_summary.rds not found — Airbnb columns will be omitted.")
  NULL
}

# ---------------------------------------------------------------------------
# Read AI summaries into a tibble
# ---------------------------------------------------------------------------
message("Reading AI summary files...")
summary_files <- list.files(SUMMARY_DIR, pattern = "\\.txt$", full.names = TRUE)

ai_summaries <- tibble(
  slug       = tools::file_path_sans_ext(basename(summary_files)),
  ai_summary = map(summary_files, \(f) readLines(f, warn = FALSE)) |>
    map_chr(\(x) paste(x, collapse = " ")) |>
    str_squish()
)

message("  Found ", nrow(ai_summaries), " summary files")

# ---------------------------------------------------------------------------
# Join everything on slug
# ---------------------------------------------------------------------------
message("Joining datasets...")

neighborhood_metrics <- lookup |>
  left_join(
    biz_summary |> select(-name),
    by = c("community_area_number", "slug")
  ) |>
  left_join(
    sentiment |> select(
      slug,
      mean_sentiment_score, sd_sentiment_score,
      sentiment_label, data_quality_flag,
      post_count, total_engagement,
      bing_pos_ratio, bing_positive, bing_negative,
      top_words
    ),
    by = "slug"
  ) |>
  left_join(ai_summaries, by = "slug") |>
  arrange(community_area_number)

if (!is.null(airbnb_summary)) {
  neighborhood_metrics <- left_join(neighborhood_metrics, airbnb_summary, by = "slug")
}

# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------
message("Running assertions...")

assert_that(
  nrow(neighborhood_metrics) == 77L,
  msg = paste("Expected 77 rows, got", nrow(neighborhood_metrics))
)

assert_that(
  !any(is.na(neighborhood_metrics$community_area_number)),
  msg = "NA values in community_area_number"
)

assert_that(
  !any(is.na(neighborhood_metrics$slug)),
  msg = "NA values in slug"
)

assert_that(
  !any(is.na(neighborhood_metrics$name)),
  msg = "NA values in name"
)

assert_that(
  !any(is.na(neighborhood_metrics$total_active_businesses)),
  msg = "NA values in total_active_businesses — check business_summary join"
)

assert_that(
  !any(is.na(neighborhood_metrics$data_quality_flag)),
  msg = "NA values in data_quality_flag — check sentiment_scores join"
)

# Warn (don't stop) if Airbnb data is missing
if ("airbnb_listing_count" %in% names(neighborhood_metrics)) {
  assert_that(
    !any(is.na(neighborhood_metrics$airbnb_listing_count)),
    msg = "NA values in airbnb_listing_count — check airbnb_summary join"
  )
  message("Airbnb coverage: ",
          sum(neighborhood_metrics$airbnb_listing_count > 0), " neighborhoods with listings")
}

# Warn (don't stop) if AI summaries are missing
n_missing_summary <- sum(is.na(neighborhood_metrics$ai_summary))
if (n_missing_summary > 0) {
  warning(n_missing_summary, " neighborhoods are missing AI summaries. ",
          "Run R/04_generate_ai_summaries.R to generate them.")
}

# ---------------------------------------------------------------------------
# Save
# ---------------------------------------------------------------------------
saveRDS(neighborhood_metrics, OUT_PATH)
message("Saved: ", OUT_PATH)
message("Columns: ", paste(names(neighborhood_metrics), collapse = ", "))

# Quick summary table
message("\nData quality breakdown:")
print(count(neighborhood_metrics, data_quality_flag))
message("\nSentiment breakdown:")
print(count(neighborhood_metrics, sentiment_label))
message("\nTop 5 neighborhoods by business count:")
neighborhood_metrics |>
  arrange(desc(total_active_businesses)) |>
  select(name, total_active_businesses, sentiment_label) |>
  head(5) |>
  print()
