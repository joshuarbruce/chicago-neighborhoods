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

SENT_PATH   <- here("data", "processed", "sentiment_scores.rds")
BIZ_PATH    <- here("data", "processed", "business_summary.rds")
SUMMARY_DIR <- here("data", "processed", "ai_summaries")

dir.create(SUMMARY_DIR, recursive = TRUE, showWarnings = FALSE)

# ---------------------------------------------------------------------------
# Load data
# ---------------------------------------------------------------------------
sentiment  <- readRDS(SENT_PATH)
biz_data   <- readRDS(BIZ_PATH)
biz_summary <- biz_data$summary

# Join
metrics <- biz_summary |>
  left_join(sentiment, by = c("community_area_number", "slug", "name")) |>
  arrange(community_area_number)

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
      "- Top words from Reddit discussions: {top_words}",
      .sep = "\n"
    )
  }

  glue(
    "You are writing a data-driven neighborhood profile for a public data journalism project.",
    "Write a 3–4 sentence summary of the {name} neighborhood in Chicago based ONLY on the",
    "following data. Do not use general knowledge about the neighborhood.",
    "Do not begin with '{name} is...'",
    "",
    "Data for {name}:",
    "{biz_block}",
    "{reddit_block}",
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
