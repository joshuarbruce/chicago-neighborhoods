# R/02_process_business_data.R
# Stage 3: Classify business licenses and summarize by neighborhood.
# Output: data/processed/business_summary.rds
#
# Run: Rscript R/02_process_business_data.R

suppressPackageStartupMessages({
  library(tidyverse)
  library(here)
})

source(here("R", "utils", "text_helpers.R"))

RAW_PATH  <- here("data", "raw", "business_licenses", "chicago_business_licenses.csv")
LOOKUP    <- here("data", "reference", "community_area_lookup.csv")
OUT_PATH  <- here("data", "processed", "business_summary.rds")

dir.create(dirname(OUT_PATH), recursive = TRUE, showWarnings = FALSE)

# ---------------------------------------------------------------------------
# Load data
# ---------------------------------------------------------------------------
message("Loading raw business data...")
raw <- read_csv(RAW_PATH, show_col_types = FALSE)
lookup <- read_csv(LOOKUP, show_col_types = FALSE)

message("Raw records: ", nrow(raw))

# ---------------------------------------------------------------------------
# Normalize community area field
# ---------------------------------------------------------------------------
# community_area comes as string numbers ("1" through "77") or sometimes with
# leading zeros or spaces — normalize to integer then back to character.
businesses <- raw |>
  filter(!is.na(community_area), community_area != "") |>
  mutate(
    community_area_number = as.integer(str_trim(community_area))
  ) |>
  filter(between(community_area_number, 1L, 77L))

message("Records with valid community area: ", nrow(businesses))

# ---------------------------------------------------------------------------
# Classify business types
# ---------------------------------------------------------------------------
message("Classifying business types...")
businesses <- businesses |>
  mutate(
    license_description = coalesce(license_description, business_activity, "Unknown"),
    category = classify_business(license_description)
  )

# ---------------------------------------------------------------------------
# Summarize per neighborhood
# ---------------------------------------------------------------------------
message("Summarizing by neighborhood...")

# Category counts per neighborhood (wide → long for diversity index)
category_counts <- businesses |>
  count(community_area_number, category)

# Top 3 categories per neighborhood
top_categories <- category_counts |>
  group_by(community_area_number) |>
  slice_max(order_by = n, n = 3, with_ties = FALSE) |>
  summarise(
    top_3_categories = paste(category, collapse = " | "),
    .groups = "drop"
  )

# Diversity index (Shannon entropy over categories)
diversity <- category_counts |>
  group_by(community_area_number) |>
  summarise(
    total_active_businesses  = sum(n),
    business_diversity_index = shannon_entropy(n),
    .groups = "drop"
  )

business_summary <- diversity |>
  left_join(top_categories, by = "community_area_number") |>
  # Ensure all 77 neighborhoods are represented (even those with zero businesses)
  right_join(
    lookup |> select(community_area_number, name, slug),
    by = "community_area_number"
  ) |>
  mutate(
    total_active_businesses  = coalesce(total_active_businesses, 0L),
    business_diversity_index = coalesce(business_diversity_index, 0),
    top_3_categories         = coalesce(top_3_categories, "No data")
  ) |>
  arrange(community_area_number)

# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------
stopifnot(
  "business_summary must have exactly 77 rows" = nrow(business_summary) == 77L,
  "No NA in community_area_number"             = !any(is.na(business_summary$community_area_number)),
  "No NA in slug"                              = !any(is.na(business_summary$slug))
)

message("business_summary: ", nrow(business_summary), " rows, ",
        sum(business_summary$total_active_businesses), " total active businesses")

# ---------------------------------------------------------------------------
# Save category breakdown (for chart)
# ---------------------------------------------------------------------------
category_breakdown <- category_counts |>
  left_join(lookup |> select(community_area_number, slug), by = "community_area_number")

saveRDS(
  list(
    summary  = business_summary,
    by_category = category_breakdown
  ),
  OUT_PATH
)
message("Saved: ", OUT_PATH)
