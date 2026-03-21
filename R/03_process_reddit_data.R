# R/03_process_reddit_data.R
# Stage 5: Read Reddit JSON files, run sentiment analysis, output per-neighborhood metrics.
# Output: data/processed/reddit_clean.rds, data/processed/sentiment_scores.rds
#
# Run: Rscript R/03_process_reddit_data.R

suppressPackageStartupMessages({
  library(tidyverse)
  library(tidytext)
  library(jsonlite)
  library(here)
  library(glue)
})

source(here("R", "utils", "text_helpers.R"))

REDDIT_DIR <- here("data", "raw", "reddit")
LOOKUP     <- here("data", "reference", "community_area_lookup.csv")
OUT_CLEAN  <- here("data", "processed", "reddit_clean.rds")
OUT_SENT   <- here("data", "processed", "sentiment_scores.rds")

dir.create(dirname(OUT_CLEAN), recursive = TRUE, showWarnings = FALSE)

lookup <- read_csv(LOOKUP, show_col_types = FALSE)

# ---------------------------------------------------------------------------
# Load all Reddit JSON files
# ---------------------------------------------------------------------------
message("Reading Reddit JSON files from: ", REDDIT_DIR)

json_files <- list.files(REDDIT_DIR, pattern = "\\.json$", full.names = TRUE)
message("Found ", length(json_files), " JSON files")

read_reddit_json <- function(path) {
  tryCatch({
    dat  <- fromJSON(path, simplifyVector = FALSE)
    slug <- dat$slug
    posts <- dat$posts

    if (length(posts) == 0) return(NULL)

    tibble(
      slug        = slug,
      post_id     = map_chr(posts, \(p) p$id %||% NA_character_),
      title       = map_chr(posts, \(p) p$title %||% ""),
      selftext    = map_chr(posts, \(p) p$selftext %||% ""),
      score       = map_int(posts, \(p) as.integer(p$score %||% 0L)),
      num_comments= map_int(posts, \(p) as.integer(p$num_comments %||% 0L)),
      subreddit   = map_chr(posts, \(p) p$subreddit %||% NA_character_),
    )
  }, error = function(e) {
    warning("Failed to read: ", path, " — ", conditionMessage(e))
    NULL
  })
}

reddit_raw <- map(json_files, read_reddit_json) |>
  compact() |>
  bind_rows()

message("Total posts loaded: ", nrow(reddit_raw))

# ---------------------------------------------------------------------------
# Clean text
# ---------------------------------------------------------------------------
reddit_clean <- reddit_raw |>
  mutate(
    title_clean = clean_reddit_text(title),
    text_clean  = clean_reddit_text(selftext),
    full_text   = paste(title_clean, text_clean, sep = " ") |> str_squish()
  ) |>
  filter(!is.na(slug), nchar(full_text) > 5)

saveRDS(reddit_clean, OUT_CLEAN)
message("Saved reddit_clean.rds — ", nrow(reddit_clean), " posts")

# ---------------------------------------------------------------------------
# Tokenize
# ---------------------------------------------------------------------------
message("Tokenizing...")

# Combine built-in stopwords + custom Chicago stopwords
all_stopwords <- bind_rows(
  get_stopwords(source = "snowball"),
  get_stopwords(source = "smart"),
  chicago_stopwords()
) |>
  distinct(word, .keep_all = FALSE)

tokens <- reddit_clean |>
  select(slug, post_id, full_text) |>
  unnest_tokens(word, full_text) |>
  anti_join(all_stopwords, by = "word") |>
  filter(str_detect(word, "^[a-z]{3,}$"))   # letters only, min 3 chars

# ---------------------------------------------------------------------------
# AFINN sentiment (scored -5 to +5)
# ---------------------------------------------------------------------------
message("Computing AFINN sentiment...")
afinn <- get_sentiments("afinn")   # downloads on first run

afinn_scores <- tokens |>
  inner_join(afinn, by = "word") |>
  group_by(slug, post_id) |>
  summarise(post_afinn = sum(value), word_count = n(), .groups = "drop") |>
  # Normalize by word count to avoid length bias
  mutate(post_afinn_norm = post_afinn / word_count)

# Per-neighborhood AFINN
neighborhood_afinn <- afinn_scores |>
  group_by(slug) |>
  summarise(
    mean_sentiment_score = mean(post_afinn_norm, na.rm = TRUE),
    sd_sentiment_score   = sd(post_afinn_norm,   na.rm = TRUE),
    .groups = "drop"
  )

# ---------------------------------------------------------------------------
# Bing sentiment (positive/negative ratio)
# ---------------------------------------------------------------------------
message("Computing Bing sentiment...")
bing <- get_sentiments("bing")

bing_counts <- tokens |>
  inner_join(bing, by = "word") |>
  count(slug, sentiment) |>
  pivot_wider(names_from = sentiment, values_from = n, values_fill = 0) |>
  mutate(
    bing_pos_ratio = positive / (positive + negative + 1)  # +1 prevents /0
  ) |>
  select(slug, bing_pos_ratio, bing_positive = positive, bing_negative = negative)

# ---------------------------------------------------------------------------
# Post-level engagement + counts
# ---------------------------------------------------------------------------
post_metrics <- reddit_clean |>
  group_by(slug) |>
  summarise(
    post_count       = n(),
    total_engagement = sum(score + num_comments, na.rm = TRUE),
    .groups          = "drop"
  )

# ---------------------------------------------------------------------------
# TF-IDF: combined bi- and tri-gram phrases per neighborhood
# Multi-word phrases are far more interpretable than single tokens.
# After scoring, we deduplicate: if a bigram is entirely contained within
# a higher-ranked trigram for the same neighborhood, the bigram is dropped
# (e.g. keep "wicker park coffee", drop "wicker park").
# Sentiment still uses unigram `tokens` above.
# ---------------------------------------------------------------------------
message("Computing bi/tri-gram TF-IDF...")

extract_ngrams <- function(data, n) {
  word_cols <- paste0("w", seq_len(n))
  data |>
    select(slug, post_id, full_text) |>
    unnest_tokens(ngram, full_text, token = "ngrams", n = n) |>
    separate(ngram, into = word_cols, sep = " ") |>
    filter(
      if_all(all_of(word_cols), ~ !.x %in% all_stopwords$word),
      if_all(all_of(word_cols), ~ str_detect(.x, "^[a-z]{3,}$"))
    ) |>
    unite(word, all_of(word_cols), sep = " ")
}

all_ngrams <- bind_rows(
  extract_ngrams(reddit_clean, 2),
  extract_ngrams(reddit_clean, 3)
)

tfidf_all <- all_ngrams |>
  count(slug, word) |>
  bind_tf_idf(word, slug, n)

# Deduplicate per neighborhood: take the top 20 candidates, then remove any
# bigram whose text appears as a substring inside a trigram also in that set.
# This collapses "snow tow" / "tow zones" into just "snow tow zones".
tfidf <- tfidf_all |>
  group_by(slug) |>
  slice_max(order_by = tf_idf, n = 20, with_ties = FALSE) |>
  group_modify(function(df, .key) {
    trigrams_here <- df$word[str_count(df$word, " ") == 2]
    df |> filter(
      str_count(word, " ") == 2 |                              # keep all trigrams
        !map_lgl(word, \(p) any(str_detect(trigrams_here, fixed(p))))  # bigram not inside any trigram
    )
  }) |>
  slice_max(order_by = tf_idf, n = 10, with_ties = FALSE) |>
  ungroup()

# Save full TF-IDF table for chart rendering (joined in by slug at slide time)
saveRDS(tfidf, here("data", "processed", "tfidf_terms.rds"))

top_tfidf_words <- tfidf |>
  group_by(slug) |>
  summarise(top_words = paste(word, collapse = ", "), .groups = "drop")

# ---------------------------------------------------------------------------
# Assemble sentiment scores
# ---------------------------------------------------------------------------
sentiment_scores <- lookup |>
  select(community_area_number, name, slug) |>
  left_join(neighborhood_afinn, by = "slug") |>
  left_join(bing_counts,        by = "slug") |>
  left_join(post_metrics,       by = "slug") |>
  left_join(top_tfidf_words,    by = "slug") |>
  mutate(
    post_count           = coalesce(post_count, 0L),
    mean_sentiment_score = coalesce(mean_sentiment_score, 0),

    # Sentiment label: thresholds tuned to normalized AFINN distribution
    sentiment_label = case_when(
      is.na(mean_sentiment_score) | post_count == 0 ~ "Neutral",
      mean_sentiment_score >  0.05 ~ "Positive",
      mean_sentiment_score < -0.05 ~ "Negative",
      TRUE                          ~ "Neutral"
    ),

    # Data quality flag
    data_quality_flag = case_when(
      post_count == 0   ~ "business_only",
      post_count < 10   ~ "low_reddit",
      TRUE              ~ "full"
    )
  ) |>
  arrange(community_area_number)

# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------
stopifnot(
  "sentiment_scores must have 77 rows"       = nrow(sentiment_scores) == 77L,
  "No NA in sentiment_label"                 = !any(is.na(sentiment_scores$sentiment_label)),
  "No NA in data_quality_flag"               = !any(is.na(sentiment_scores$data_quality_flag))
)

message("Sentiment summary:")
print(count(sentiment_scores, sentiment_label))
print(count(sentiment_scores, data_quality_flag))

saveRDS(sentiment_scores, OUT_SENT)
message("Saved: ", OUT_SENT)
