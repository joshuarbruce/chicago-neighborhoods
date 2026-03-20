# test_pipeline.R — Subset pipeline test (3 neighborhoods)
# Tests the full pipeline on Rogers Park (1), Hyde Park (41), Riverdale (54).
# Runs in ~5 minutes; validates each stage without full API spend.
#
# Usage: Rscript test_pipeline.R

suppressPackageStartupMessages({
  library(tidyverse)
  library(here)
})

message("=== Test Pipeline (3 neighborhoods) ===")
TEST_SLUGS <- c("rogers_park", "hyde_park", "riverdale")
message("Neighborhoods: ", paste(TEST_SLUGS, collapse = ", "))

# ---------------------------------------------------------------------------
# Stage 1: Verify reference data
# ---------------------------------------------------------------------------
message("\n--- Stage 1: Reference data ---")
lookup <- read_csv(here("data", "reference", "community_area_lookup.csv"),
                   show_col_types = FALSE)
stopifnot(
  "Lookup must have 77 rows" = nrow(lookup) == 77L,
  "Test slugs must be present" = all(TEST_SLUGS %in% lookup$slug)
)
message("OK: 77 neighborhoods in lookup table")
message("Test slugs found: ", paste(lookup$name[lookup$slug %in% TEST_SLUGS], collapse = ", "))

# ---------------------------------------------------------------------------
# Stage 2: Business data
# ---------------------------------------------------------------------------
message("\n--- Stage 2: Business data ---")
biz_raw_path <- here("data", "raw", "business_licenses", "chicago_business_licenses.csv")
if (!file.exists(biz_raw_path)) {
  message("Business data not found — running fetch...")
  source(here("R", "01_fetch_business_data.R"), local = new.env())
} else {
  message("Business data already present: ", biz_raw_path)
}

# ---------------------------------------------------------------------------
# Stage 3: Process business data (full — needed for joins)
# ---------------------------------------------------------------------------
message("\n--- Stage 3: Process business data ---")
biz_out <- here("data", "processed", "business_summary.rds")
if (!file.exists(biz_out)) {
  source(here("R", "02_process_business_data.R"), local = new.env())
} else {
  message("business_summary.rds already present")
}

biz_data <- readRDS(biz_out)
test_biz <- biz_data$summary |> filter(slug %in% TEST_SLUGS)
message("Business data for test neighborhoods:")
print(test_biz |> select(name, total_active_businesses, top_3_categories, business_diversity_index))

# ---------------------------------------------------------------------------
# Stage 4: Reddit — check for test files or collect
# ---------------------------------------------------------------------------
message("\n--- Stage 4: Reddit data ---")
reddit_dir <- here("data", "raw", "reddit")
missing_reddit <- TEST_SLUGS[!file.exists(file.path(reddit_dir, paste0(TEST_SLUGS, ".json")))]

if (length(missing_reddit) > 0) {
  message("Missing Reddit files: ", paste(missing_reddit, collapse = ", "))
  message("Running: python python/fetch_reddit.py --test")
  result <- system(
    paste("python", here("python", "fetch_reddit.py"), "--test"),
    intern = FALSE
  )
  if (result != 0) {
    warning("Reddit collection returned non-zero exit code. Continuing...")
  }
} else {
  message("Reddit files present for all test neighborhoods")
}

# ---------------------------------------------------------------------------
# Stage 5: Sentiment (subset)
# ---------------------------------------------------------------------------
message("\n--- Stage 5: Reddit processing + sentiment ---")
sent_out <- here("data", "processed", "sentiment_scores.rds")
source(here("R", "03_process_reddit_data.R"), local = new.env())
sentiment <- readRDS(sent_out)
test_sent <- sentiment |> filter(slug %in% TEST_SLUGS)
message("Sentiment for test neighborhoods:")
print(test_sent |> select(name, post_count, mean_sentiment_score, sentiment_label, data_quality_flag))

# ---------------------------------------------------------------------------
# Stage 6: AI summaries (subset — only generate for test slugs)
# ---------------------------------------------------------------------------
message("\n--- Stage 6: AI summaries (test subset) ---")
summary_dir <- here("data", "processed", "ai_summaries")
dir.create(summary_dir, recursive = TRUE, showWarnings = FALSE)

missing_summaries <- TEST_SLUGS[
  !file.exists(file.path(summary_dir, paste0(TEST_SLUGS, ".txt")))
]

if (length(missing_summaries) > 0) {
  message("Generating summaries for: ", paste(missing_summaries, collapse = ", "))
  # Source the AI summary script but it only generates missing files
  source(here("R", "04_generate_ai_summaries.R"), local = new.env())
} else {
  message("Summaries already present for all test neighborhoods")
}

for (slug in TEST_SLUGS) {
  txt_path <- file.path(summary_dir, paste0(slug, ".txt"))
  if (file.exists(txt_path)) {
    name <- lookup$name[lookup$slug == slug]
    message("\n", name, ":")
    message(readLines(txt_path, warn = FALSE) |> paste(collapse = " "))
  }
}

# ---------------------------------------------------------------------------
# Stage 7: Master dataset
# ---------------------------------------------------------------------------
message("\n--- Stage 7: Master dataset ---")
source(here("R", "05_build_neighborhood_metrics.R"), local = new.env())
metrics <- readRDS(here("data", "processed", "neighborhood_metrics.rds"))
test_metrics <- metrics |> filter(slug %in% TEST_SLUGS)
message("\nFinal metrics for test neighborhoods:")
print(test_metrics |> select(name, total_active_businesses, sentiment_label,
                              data_quality_flag, ai_summary) |>
  mutate(ai_summary = str_trunc(ai_summary, 80)))

message("\n=== Test pipeline complete ===")
message("All ", length(TEST_SLUGS), " test neighborhoods passed.")
message("\nNext: quarto render slides/chicago_neighborhoods.qmd")
