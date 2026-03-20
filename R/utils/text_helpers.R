# R/utils/text_helpers.R
# Text cleaning, slug generation, and business category classification.

library(stringr)
library(dplyr)

# ---------------------------------------------------------------------------
# Slug utilities
# ---------------------------------------------------------------------------

#' Convert a neighborhood name to a URL-safe slug.
#' Matches the slugs in community_area_lookup.csv.
make_slug <- function(name) {
  name |>
    str_to_lower() |>
    str_replace_all("[^a-z0-9]+", "_") |>
    str_replace_all("(^_|_$)", "")
}

# ---------------------------------------------------------------------------
# Business category classification
# ---------------------------------------------------------------------------

#' Classify a business license description into one of ~10 broad categories.
#' Uses case_when with str_detect for pattern matching.
#'
#' @param license_description Character vector of license type descriptions.
#' @return Character vector of category labels.
classify_business <- function(license_description) {
  desc <- str_to_lower(license_description)

  case_when(
    str_detect(desc, "restaurant|food|caterer|bakery|deli|cafe|catering|grocery|liquor|tavern|bar|pub|nightclub|retail food") ~
      "Food & Beverage",

    str_detect(desc, "retail|store|shop|boutique|clothing|apparel|merchandise|gift|flower|florist|tobacco|jewelry|antique|furniture|hardware|electronics|auto parts") ~
      "Retail",

    str_detect(desc, "health|medical|dental|clinic|pharmacy|hospital|therapy|therapist|massage|spa|salon|barber|beauty|nail|optician|optometrist|physician|chiropractic|acupuncture") ~
      "Health & Personal Care",

    str_detect(desc, "contractor|construction|remodel|plumb|electric|hvac|roofing|mason|landscap|paint|carpenter|general contractor") ~
      "Construction & Trades",

    str_detect(desc, "auto|vehicle|car|tire|mechanic|garage|towing|gas station|fuel|parking|taxi|livery|limo|transportation") ~
      "Automotive & Transportation",

    str_detect(desc, "office|professional|consulting|financial|insurance|real estate|accounting|attorney|law|legal|architect|engineer|tech|software|staffing|advertising|marketing") ~
      "Professional Services",

    str_detect(desc, "child|daycare|day care|school|educat|tutor|fitness|gym|recreation|sport|theater|entertainment|music|art|gallery|museum") ~
      "Education, Arts & Recreation",

    str_detect(desc, "hotel|motel|bed and breakfast|hostel|lodging|short-term|airbnb") ~
      "Lodging",

    str_detect(desc, "wholesale|warehouse|distribution|manufacturing|industrial|storage|moving") ~
      "Wholesale & Industrial",

    TRUE ~ "Other"
  )
}

# ---------------------------------------------------------------------------
# Diversity index
# ---------------------------------------------------------------------------

#' Compute Shannon entropy (business diversity index) from a frequency table.
#' Higher value = more evenly distributed across categories.
#'
#' @param category_counts Named numeric vector or table of counts.
#' @return Numeric Shannon entropy value (nats), or NA if input is empty.
shannon_entropy <- function(category_counts) {
  counts <- as.numeric(category_counts)
  counts <- counts[counts > 0]
  if (length(counts) == 0) return(NA_real_)
  props <- counts / sum(counts)
  -sum(props * log(props))
}

# ---------------------------------------------------------------------------
# Text cleaning for Reddit
# ---------------------------------------------------------------------------

#' Remove URLs, Reddit formatting, and extra whitespace from post text.
clean_reddit_text <- function(text) {
  text |>
    str_replace_all("https?://\\S+", " ") |>           # URLs
    str_replace_all("\\[([^\\]]+)\\]\\([^)]+\\)", "\\1") |>  # Markdown links → text
    str_replace_all("[*_~`>|#]", " ") |>               # Markdown formatting
    str_replace_all("\\s+", " ") |>                    # Collapse whitespace
    str_trim()
}

#' Custom stopwords to augment tidytext::stop_words for Chicago neighborhood analysis.
chicago_stopwords <- function() {
  custom <- c(
    "chicago", "neighborhood", "area", "community", "city",
    "street", "ave", "blvd", "block", "north", "south", "east", "west",
    "il", "illinois", "post", "thread", "comment", "reddit",
    "https", "www", "com", "amp", "gt", "lt",
    "1", "2", "3", "4", "5", "10", "100"
  )
  tibble::tibble(word = custom, lexicon = "chicago_custom")
}
