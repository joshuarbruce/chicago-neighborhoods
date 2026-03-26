# R/04_generate_ai_summaries.R
# Stage 6: Generate AI summaries for each neighborhood using Claude API.
# Output: data/processed/ai_summaries/{slug}.txt (one file per neighborhood)
#
# Idempotent: skips existing files. Summaries are committed to git so future
# renders don't require an API key.
#
# Run: Rscript R/04_generate_ai_summaries.R

suppressPackageStartupMessages({
  library(tidyverse)
  library(here)
  library(glue)
})

source(here("R", "utils", "api_helpers.R"))

SENT_PATH    <- here("data", "processed", "sentiment_scores.rds")
BIZ_PATH     <- here("data", "processed", "business_summary.rds")
AIRBNB_PATH  <- here("data", "processed", "airbnb_summary.rds")
SUMMARY_DIR  <- here("data", "processed", "ai_summaries")

# --force flag: delete all existing summaries and regenerate from scratch
args  <- commandArgs(trailingOnly = TRUE)
force_regen <- "--force" %in% args

dir.create(SUMMARY_DIR, recursive = TRUE, showWarnings = FALSE)

if (force_regen) {
  existing <- list.files(SUMMARY_DIR, pattern = "\\.txt$", full.names = TRUE)
  if (length(existing) > 0) {
    file.remove(existing)
    message("--force: deleted ", length(existing), " existing summary files")
  }
}

# ---------------------------------------------------------------------------
# Load data
# ---------------------------------------------------------------------------
sentiment   <- readRDS(SENT_PATH)
biz_data    <- readRDS(BIZ_PATH)
biz_summary <- biz_data$summary

airbnb_summary <- if (file.exists(AIRBNB_PATH)) {
  readRDS(AIRBNB_PATH)$summary |>
    select(slug, airbnb_listing_count, airbnb_median_price,
           airbnb_data_flag, airbnb_top_words)
} else {
  message("airbnb_summary.rds not found — Airbnb context will be omitted from prompts.")
  NULL
}

# Join
metrics <- biz_summary |>
  left_join(sentiment, by = c("community_area_number", "slug", "name")) |>
  arrange(community_area_number)

if (!is.null(airbnb_summary)) {
  metrics <- metrics |> left_join(airbnb_summary, by = "slug")
}

stopifnot(nrow(metrics) == 77L)

# ---------------------------------------------------------------------------
# Prompt builder
# ---------------------------------------------------------------------------
build_prompt <- function(row) {
  name            <- row$name
  total_biz       <- row$total_active_businesses
  top_cats        <- row$top_3_categories
  diversity       <- round(row$business_diversity_index, 2)
  sentiment_label <- row$sentiment_label
  top_words       <- coalesce(row$top_words, "")
  flag            <- row$data_quality_flag

  biz_block <- glue(
    "- Active business licenses: {total_biz}",
    "- Top business categories: {top_cats}",
    "- Business diversity index (Shannon entropy): {diversity}",
    .sep = "\n"
  )

  reddit_block <- if (flag == "business_only") {
    "(No Reddit data available for this neighborhood.)"
  } else {
    glue(
      "- Overall community sentiment: {sentiment_label}",
      "- Top phrases from Reddit discussions (resident voice): {top_words}",
      .sep = "\n"
    )
  }

  # Airbnb block — only included if airbnb columns exist in row
  has_airbnb <- "airbnb_data_flag" %in% names(row)
  airbnb_block <- if (!has_airbnb || row$airbnb_data_flag == "no_airbnb") {
    "(No Airbnb listing data available for this neighborhood.)"
  } else {
    listing_count <- row$airbnb_listing_count
    median_price  <- if (is.na(row$airbnb_median_price)) "N/A" else
                       paste0("$", round(row$airbnb_median_price))
    airbnb_words  <- coalesce(row$airbnb_top_words, "")
    glue(
      "- Active Airbnb listings: {listing_count}",
      "- Median nightly price: {median_price}",
      "- Top phrases from Airbnb guest reviews (visitor voice): {airbnb_words}",
      .sep = "\n"
    )
  }

  glue(
    "You are writing a data-driven neighborhood profile for a public data journalism project.",
    "Write a 3–4 sentence summary of the {name} neighborhood in Chicago based ONLY on the",
    "following data. Do not use general knowledge about the neighborhood.",
    "Do not begin with '{name} is...'",
    "If the Airbnb visitor phrases and Reddit resident phrases differ noticeably,",
    "briefly note what visitors seem to value that residents don't often discuss.",
    "",
    "Data for {name}:",
    "{biz_block}",
    "{reddit_block}",
    "Airbnb visitor data:",
    "{airbnb_block}",
    "",
    "Write the summary now:",
    .sep = "\n"
  )
}

# ---------------------------------------------------------------------------
# Generate summaries (idempotent)
# ---------------------------------------------------------------------------
n <- nrow(metrics)
message("Generating AI summaries for ", n, " neighborhoods...")
message("Existing summaries will be skipped.")

for (i in seq_len(n)) {
  row  <- metrics[i, ]
  slug <- row$slug
  out  <- file.path(SUMMARY_DIR, paste0(slug, ".txt"))

  if (file.exists(out)) {
    message(glue("[{i}/{n}] SKIP {row$name} (exists)"))
    next
  }

  message(glue("[{i}/{n}] Generating summary for: {row$name}"))
  prompt <- build_prompt(row)

  summary_text <- tryCatch(
    call_claude(prompt),
    error = function(e) {
      warning(glue("Failed for {row$name}: {conditionMessage(e)}"))
      NA_character_
    }
  )

  if (!is.na(summary_text)) {
    writeLines(summary_text, out)
    message("  Saved: ", basename(out))
  } else {
    message("  FAILED — no file written for ", row$name)
  }

  if (i < n) Sys.sleep(1)
}

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
existing_files <- list.files(SUMMARY_DIR, pattern = "\\.txt$")
message("\nSummary files: ", length(existing_files), " / 77")

missing_slugs <- setdiff(metrics$slug, tools::file_path_sans_ext(existing_files))
if (length(missing_slugs) > 0) {
  message("Missing summaries for: ", paste(missing_slugs, collapse = ", "))
} else {
  message("All 77 summaries present.")
}
