# R/02b_process_airbnb_data.R
# Stage 2b: Download and process Inside Airbnb Chicago data.
# Inputs:   Inside Airbnb listings.csv + reviews.csv.gz (two snapshots)
# Outputs:  data/processed/airbnb_summary.rds
#           data/processed/airbnb_tfidf.rds
#
# Run: Rscript R/02b_process_airbnb_data.R

suppressPackageStartupMessages({
  library(tidyverse)
  library(tidytext)
  library(sf)
  library(here)
  library(glue)
})

source(here("R", "utils", "text_helpers.R"))

GEOJSON_PATH <- here("data", "reference", "chicago_community_areas.geojson")
LOOKUP_PATH  <- here("data", "reference", "community_area_lookup.csv")
RAW_DIR      <- here("data", "raw", "airbnb")
OUT_SUMMARY  <- here("data", "processed", "airbnb_summary.rds")
OUT_TFIDF    <- here("data", "processed", "airbnb_tfidf.rds")

dir.create(RAW_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(here("data", "processed"), recursive = TRUE, showWarnings = FALSE)

# ---------------------------------------------------------------------------
# Snapshot definitions — both available Chicago snapshots
# ---------------------------------------------------------------------------
SNAPSHOTS <- list(
  list(
    date     = "2025-06-17",
    listings = "https://data.insideairbnb.com/united-states/il/chicago/2025-06-17/visualisations/listings.csv",
    reviews  = "https://data.insideairbnb.com/united-states/il/chicago/2025-06-17/data/reviews.csv.gz"
  ),
  list(
    date     = "2025-09-22",
    listings = "https://data.insideairbnb.com/united-states/il/chicago/2025-09-22/visualisations/listings.csv",
    reviews  = "https://data.insideairbnb.com/united-states/il/chicago/2025-09-22/data/reviews.csv.gz"
  )
)

# ---------------------------------------------------------------------------
# Download helper (skip if already present)
# ---------------------------------------------------------------------------
download_if_missing <- function(url, dest) {
  if (file.exists(dest)) {
    message("  Already present: ", basename(dest))
    return(invisible(dest))
  }
  message("  Downloading: ", basename(dest))
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  tryCatch(
    download.file(url, dest, mode = "wb", quiet = TRUE),
    error = function(e) stop("Download failed for ", url, ": ", conditionMessage(e))
  )
  invisible(dest)
}

# ---------------------------------------------------------------------------
# Download all snapshots
# ---------------------------------------------------------------------------
message("=== Downloading Inside Airbnb Chicago snapshots ===")
for (snap in SNAPSHOTS) {
  message("Snapshot: ", snap$date)
  snap_dir <- file.path(RAW_DIR, snap$date)
  download_if_missing(snap$listings, file.path(snap_dir, "listings.csv"))
  download_if_missing(snap$reviews,  file.path(snap_dir, "reviews.csv.gz"))
}

# ---------------------------------------------------------------------------
# Load and combine listings from all snapshots
# ---------------------------------------------------------------------------
message("\n=== Loading listings ===")

read_listings <- function(snap) {
  path <- file.path(RAW_DIR, snap$date, "listings.csv")
  read_csv(path, show_col_types = FALSE) |>
    mutate(snapshot_date = snap$date)
}

listings_raw <- map(SNAPSHOTS, read_listings) |> bind_rows()
message("Total listing rows across snapshots: ", nrow(listings_raw))

# Parse price: "$150.00" → 150.0
listings_raw <- listings_raw |>
  mutate(
    price_num = price |>
      str_replace_all("[$,]", "") |>
      as.numeric()
  )

# Deduplicate: keep most recent snapshot per listing_id
listings_deduped <- listings_raw |>
  arrange(desc(snapshot_date)) |>
  distinct(id, .keep_all = TRUE)

message("Unique listings after deduplication: ", nrow(listings_deduped))

# ---------------------------------------------------------------------------
# Spatial join: assign each listing to a Chicago community area
# ---------------------------------------------------------------------------
message("\n=== Assigning listings to community areas (spatial join) ===")

community_areas <- st_read(GEOJSON_PATH, quiet = TRUE)

# Normalise the area number column name
area_col <- if ("area_numbe" %in% names(community_areas)) "area_numbe" else "community_area_number"
community_areas <- community_areas |>
  mutate(community_area_number = as.integer(.data[[area_col]])) |>
  select(community_area_number, geometry)

# Drop listings with missing coordinates
listings_geo <- listings_deduped |>
  filter(!is.na(longitude), !is.na(latitude)) |>
  st_as_sf(coords = c("longitude", "latitude"), crs = 4326, remove = FALSE)

# Ensure same CRS
community_areas <- st_transform(community_areas, crs = st_crs(listings_geo))

# Spatial join — each listing gets the community_area_number of the polygon it falls in
listings_joined <- st_join(listings_geo, community_areas, join = st_within) |>
  st_drop_geometry() |>
  filter(!is.na(community_area_number))

message("Listings successfully assigned to a community area: ", nrow(listings_joined))
message("Listings outside community area boundaries (dropped): ",
        nrow(listings_geo) - nrow(listings_joined))

# ---------------------------------------------------------------------------
# Load lookup and join slugs
# ---------------------------------------------------------------------------
lookup <- read_csv(LOOKUP_PATH, show_col_types = FALSE)

listings_with_slug <- listings_joined |>
  left_join(
    lookup |> select(community_area_number, slug, neighborhood_name = name),
    by = "community_area_number"
  )

# ---------------------------------------------------------------------------
# Aggregate listing-level stats per neighborhood
# ---------------------------------------------------------------------------
message("\n=== Aggregating listing statistics ===")

listing_stats <- listings_with_slug |>
  group_by(community_area_number, slug, neighborhood_name) |>
  summarise(
    airbnb_listing_count = n(),
    airbnb_median_price  = median(price_num, na.rm = TRUE),
    airbnb_avg_rating    = mean(reviews_per_month, na.rm = TRUE),
    .groups = "drop"
  )

# Room type breakdown (for potential charting)
by_room_type <- listings_with_slug |>
  count(slug, neighborhood_name, room_type) |>
  rename(n_listings = n)

# Ensure all 77 neighborhoods are present (right join fills zeros)
summary_77 <- lookup |>
  select(community_area_number, slug, name) |>
  left_join(listing_stats |> select(-neighborhood_name), by = c("community_area_number", "slug")) |>
  mutate(
    airbnb_listing_count = coalesce(airbnb_listing_count, 0L),
    airbnb_data_flag     = if_else(airbnb_listing_count == 0, "no_airbnb", "full")
  ) |>
  arrange(community_area_number)

stopifnot("airbnb summary must have 77 rows" = nrow(summary_77) == 77L)
message("Listing count summary: ", sum(summary_77$airbnb_listing_count > 0),
        " neighborhoods with listings, ",
        sum(summary_77$airbnb_listing_count == 0), " with none")

# ---------------------------------------------------------------------------
# Load and combine reviews
# ---------------------------------------------------------------------------
message("\n=== Loading reviews ===")

read_reviews <- function(snap) {
  path <- file.path(RAW_DIR, snap$date, "reviews.csv.gz")
  read_csv(path, show_col_types = FALSE) |>
    mutate(snapshot_date = snap$date)
}

reviews_raw <- map(SNAPSHOTS, read_reviews) |> bind_rows()
message("Total review rows across snapshots: ", nrow(reviews_raw))

# Deduplicate: same review can appear in multiple snapshots
reviews_deduped <- reviews_raw |>
  distinct(listing_id, date, reviewer_id, .keep_all = TRUE)

message("Unique reviews after deduplication: ", nrow(reviews_deduped))

# Join reviews to community area via listing_id
listing_area_map <- listings_with_slug |>
  select(id, community_area_number, slug) |>
  distinct()

reviews_with_slug <- reviews_deduped |>
  inner_join(listing_area_map, by = c("listing_id" = "id")) |>
  filter(!is.na(comments), nchar(str_trim(comments)) > 10)

message("Reviews with valid community area: ", nrow(reviews_with_slug))

# ---------------------------------------------------------------------------
# Review NLP: clean text
# ---------------------------------------------------------------------------
message("\n=== Running NLP on Airbnb reviews ===")

reviews_clean <- reviews_with_slug |>
  mutate(
    text_clean = clean_reddit_text(comments)
  ) |>
  filter(nchar(text_clean) > 5)

# ---------------------------------------------------------------------------
# AFINN sentiment on reviews
# ---------------------------------------------------------------------------
message("Computing AFINN sentiment...")

all_stopwords <- bind_rows(
  get_stopwords(source = "snowball"),
  get_stopwords(source = "smart"),
  chicago_stopwords()
) |>
  distinct(word, .keep_all = FALSE)

review_tokens <- reviews_clean |>
  select(slug, listing_id, reviewer_id, date, text_clean) |>
  mutate(review_id = row_number()) |>
  unnest_tokens(word, text_clean) |>
  anti_join(all_stopwords, by = "word") |>
  filter(str_detect(word, "^[a-z]{3,}$"))

afinn <- get_sentiments("afinn")

airbnb_sentiment <- review_tokens |>
  inner_join(afinn, by = "word") |>
  group_by(slug, review_id) |>
  summarise(review_afinn = sum(value), word_count = n(), .groups = "drop") |>
  mutate(review_afinn_norm = review_afinn / word_count) |>
  group_by(slug) |>
  summarise(
    airbnb_mean_sentiment = mean(review_afinn_norm, na.rm = TRUE),
    .groups = "drop"
  ) |>
  mutate(
    airbnb_sentiment_label = case_when(
      airbnb_mean_sentiment >  0.05 ~ "Positive",
      airbnb_mean_sentiment < -0.05 ~ "Negative",
      TRUE                          ~ "Neutral"
    )
  )

# ---------------------------------------------------------------------------
# TF-IDF: bi- and tri-gram phrases from Airbnb reviews
# (mirrors R/03_process_reddit_data.R exactly)
# ---------------------------------------------------------------------------
message("Computing Airbnb review bi/tri-gram TF-IDF...")

# Add airbnb-specific stopwords to suppress generic hospitality language
airbnb_stopwords <- tibble(
  word    = c("stay", "stayed", "host", "hosts", "place", "great", "nice",
              "good", "clean", "comfortable", "apartment", "room", "unit",
              "airbnb", "listing", "location", "highly", "recommend",
              "recommended", "everything", "perfect", "wonderful"),
  lexicon = "airbnb_custom"
)

all_stopwords_airbnb <- bind_rows(all_stopwords, airbnb_stopwords) |>
  distinct(word, .keep_all = FALSE)

extract_ngrams_reviews <- function(data, n) {
  word_cols <- paste0("w", seq_len(n))
  data |>
    select(slug, review_id = listing_id, full_text = text_clean) |>
    unnest_tokens(ngram, full_text, token = "ngrams", n = n) |>
    separate(ngram, into = word_cols, sep = " ") |>
    filter(
      if_all(all_of(word_cols), ~ !.x %in% all_stopwords_airbnb$word),
      if_all(all_of(word_cols), ~ str_detect(.x, "^[a-z]{3,}$"))
    ) |>
    unite(word, all_of(word_cols), sep = " ")
}

all_ngrams_airbnb <- bind_rows(
  extract_ngrams_reviews(reviews_clean, 2),
  extract_ngrams_reviews(reviews_clean, 3)
)

tfidf_all_airbnb <- all_ngrams_airbnb |>
  count(slug, word) |>
  bind_tf_idf(word, slug, n)

# Deduplicate: drop bigrams that appear inside higher-ranked trigrams
airbnb_tfidf <- tfidf_all_airbnb |>
  group_by(slug) |>
  slice_max(order_by = tf_idf, n = 20, with_ties = FALSE) |>
  group_modify(function(df, .key) {
    trigrams_here <- df$word[str_count(df$word, " ") == 2]
    df |> filter(
      str_count(word, " ") == 2 |
        !map_lgl(word, \(p) any(str_detect(trigrams_here, fixed(p))))
    )
  }) |>
  slice_max(order_by = tf_idf, n = 10, with_ties = FALSE) |>
  ungroup()

# Top phrases string for AI prompt
airbnb_top_words <- airbnb_tfidf |>
  group_by(slug) |>
  summarise(airbnb_top_words = paste(word, collapse = ", "), .groups = "drop")

# ---------------------------------------------------------------------------
# Assemble final summary with sentiment + top phrases
# ---------------------------------------------------------------------------
summary_77 <- summary_77 |>
  left_join(airbnb_sentiment, by = "slug") |>
  left_join(airbnb_top_words, by = "slug") |>
  mutate(
    airbnb_sentiment_label = coalesce(airbnb_sentiment_label, "Neutral")
  )

# ---------------------------------------------------------------------------
# Save
# ---------------------------------------------------------------------------
saveRDS(
  list(summary = summary_77, by_room_type = by_room_type),
  OUT_SUMMARY
)
message("\nSaved: ", OUT_SUMMARY)

saveRDS(airbnb_tfidf, OUT_TFIDF)
message("Saved: ", OUT_TFIDF)

# ---------------------------------------------------------------------------
# Summary report
# ---------------------------------------------------------------------------
message("\nAirbnb data quality breakdown:")
print(count(summary_77, airbnb_data_flag))

message("\nTop 10 neighborhoods by Airbnb listing count:")
summary_77 |>
  arrange(desc(airbnb_listing_count)) |>
  select(name, airbnb_listing_count, airbnb_median_price) |>
  head(10) |>
  print()
