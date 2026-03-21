# R/utils/chart_functions.R
# Reusable ggplot2 and leaflet chart factories for the neighborhood slides.

library(ggplot2)
library(scales)
library(dplyr)
library(leaflet)
library(sf)

# ---------------------------------------------------------------------------
# Tufte-inspired palette
# ---------------------------------------------------------------------------

# Muted, warm earth tones — color reserved for data, not decoration
SENTIMENT_COLORS <- c(
  "Positive"  = "#4a7c59",   # sage green
  "Neutral"   = "#b8963e",   # warm gold
  "Negative"  = "#9e3a3a"    # brick red
)

# Ten distinct but muted category colors — warm and cool tones alternating
CATEGORY_PALETTE <- c(
  "#6b4c3b",  # warm brown
  "#3d6b50",  # sage green
  "#5c5087",  # muted violet
  "#7a5c35",  # ochre
  "#3d6070",  # slate teal
  "#7a6b3d",  # olive
  "#7a3d5c",  # dusty rose
  "#3d507a",  # slate blue
  "#3d6b6b",  # muted seafoam
  "#6b6b4a"   # warm khaki
)

SLIDE_BG <- "#fffff8"   # matches $body-bg in custom.scss

# ---------------------------------------------------------------------------
# Shared Tufte-inspired ggplot2 theme
# ---------------------------------------------------------------------------

theme_tufte_slide <- function(base_size = 12) {
  theme_minimal(base_size = base_size, base_family = "serif") %+replace%
    theme(
      # Cream background — charts blend into the slide
      plot.background  = element_rect(fill = SLIDE_BG, color = NA),
      panel.background = element_rect(fill = SLIDE_BG, color = NA),

      # Minimal grid: faint vertical reference lines only (Tufte: remove chartjunk)
      panel.grid.major.y = element_blank(),
      panel.grid.major.x = element_line(color = "#e4e0d8", linewidth = 0.3),
      panel.grid.minor   = element_blank(),

      # Subtle axis line on the value axis
      axis.line.x  = element_line(color = "#6b5f54", linewidth = 0.4),
      axis.ticks.x = element_line(color = "#6b5f54", linewidth = 0.3),
      axis.ticks.y = element_blank(),

      axis.text    = element_text(color = "#4a3f35", size = rel(0.88)),
      axis.title.x = element_text(color = "#6b5f54", size = rel(0.82),
                                  margin = margin(t = 4)),
      axis.title.y = element_blank(),

      # Titles: plain weight, warm color — let the data be bold, not the label
      plot.title    = element_text(face = "plain", size = rel(0.95),
                                   color = "#2c2420", hjust = 0,
                                   margin = margin(b = 2)),
      plot.subtitle = element_text(size = rel(0.80), color = "#7a6b5e",
                                   hjust = 0, margin = margin(b = 4)),
      plot.margin   = margin(4, 8, 4, 4),

      legend.background = element_rect(fill = SLIDE_BG, color = NA),
      legend.key        = element_rect(fill = SLIDE_BG, color = NA),
      legend.text       = element_text(color = "#4a3f35", size = rel(0.85)),
      legend.title      = element_text(color = "#4a3f35", size = rel(0.85))
    )
}

# ---------------------------------------------------------------------------
# Business bar chart
# ---------------------------------------------------------------------------

#' Create a horizontal bar chart of business categories for one neighborhood.
#'
#' @param business_data Data frame with columns `category` and `n`.
#' @param neighborhood_name Character — used in subtitle.
#' @return ggplot object.
make_business_bar_chart <- function(business_data, neighborhood_name) {
  df <- business_data |>
    arrange(desc(n)) |>
    mutate(category = forcats::fct_reorder(category, n))

  ggplot(df, aes(x = n, y = category, fill = category)) +
    geom_col(show.legend = FALSE, width = 0.65) +
    geom_text(aes(label = comma(n)), hjust = -0.15, size = 3.2,
              family = "serif", color = "#4a3f35") +
    scale_fill_manual(values = CATEGORY_PALETTE) +
    scale_x_continuous(expand = expansion(mult = c(0, 0.18)),
                       labels = comma) +
    labs(
      title    = "Active Business Licenses by Category",
      subtitle = neighborhood_name,
      x        = "Active licenses"
    ) +
    theme_tufte_slide(base_size = 12)
}

# ---------------------------------------------------------------------------
# Sentiment badge helper
# ---------------------------------------------------------------------------

#' Return a named list with label and hex color for a sentiment label.
sentiment_badge <- function(sentiment_label) {
  list(
    label = sentiment_label,
    color = SENTIMENT_COLORS[sentiment_label]
  )
}

# ---------------------------------------------------------------------------
# Leaflet minimap (kept for potential future use)
# ---------------------------------------------------------------------------

#' Create a non-interactive leaflet minimap for a single neighborhood.
make_leaflet_minimap <- function(geojson_path, community_area_number, neighborhood_name) {
  areas <- sf::st_read(geojson_path, quiet = TRUE)
  area_col <- if ("area_numbe" %in% names(areas)) "area_numbe" else "community_area_number"
  target <- areas[as.integer(areas[[area_col]]) == community_area_number, ]
  centroid <- sf::st_centroid(sf::st_geometry(target))
  coords   <- sf::st_coordinates(centroid)

  leaflet(options = leafletOptions(
    zoomControl = FALSE, dragging = FALSE, scrollWheelZoom = FALSE,
    doubleClickZoom = FALSE, touchZoom = FALSE, keyboard = FALSE, boxZoom = FALSE
  )) |>
    addProviderTiles("CartoDB.Positron") |>
    addPolygons(data = target, fillColor = "#6b4c3b", fillOpacity = 0.35,
                color = "#4a3f35", weight = 2) |>
    setView(lng = coords[1], lat = coords[2], zoom = 13)
}

# ---------------------------------------------------------------------------
# TF-IDF bar chart
# ---------------------------------------------------------------------------

#' Create a horizontal bar chart of top TF-IDF phrases for one neighborhood.
#'
#' @param tfidf_data Data frame with columns `word` and `tf_idf`.
#' @param neighborhood_name Character — used in subtitle.
#' @return ggplot object.
make_tfidf_chart <- function(tfidf_data, neighborhood_name) {
  df <- tfidf_data |>
    arrange(desc(tf_idf)) |>
    slice_head(n = 10) |>
    mutate(word = forcats::fct_reorder(word, tf_idf))

  ggplot(df, aes(x = tf_idf, y = word)) +
    geom_col(fill = "#4a6b7a", width = 0.65, alpha = 0.85) +
    scale_x_continuous(expand = expansion(mult = c(0, 0.12))) +
    labs(
      title    = "Distinctive Reddit Phrases (TF-IDF)",
      subtitle = neighborhood_name,
      x        = "TF-IDF score"
    ) +
    theme_tufte_slide(base_size = 12) +
    theme(axis.title.x = element_text(color = "#6b5f54", size = rel(0.78)))
}

# ---------------------------------------------------------------------------
# Overview choropleth (opening slide)
# ---------------------------------------------------------------------------

#' Create a leaflet choropleth of all 77 neighborhoods colored by sentiment score.
#'
#' @param geojson_path    Path to chicago_community_areas.geojson.
#' @param metrics         Data frame with columns: community_area_number, mean_sentiment_score, name.
#' @return leaflet htmlwidget.
make_overview_choropleth <- function(geojson_path, metrics) {
  areas <- sf::st_read(geojson_path, quiet = TRUE)
  area_col <- if ("area_numbe" %in% names(areas)) "area_numbe" else "community_area_number"
  areas[[area_col]] <- as.integer(areas[[area_col]])

  merged <- dplyr::left_join(
    areas,
    metrics[, c("community_area_number", "mean_sentiment_score", "name")],
    by = setNames("community_area_number", area_col)
  )

  pal <- colorNumeric(
    palette  = c("#9e3a3a", "#d4b896", "#4a7c59"),  # muted brick → warm sand → sage
    domain   = merged$mean_sentiment_score,
    na.color = "#d4cfc6"
  )

  leaflet(merged) |>
    addProviderTiles("CartoDB.Positron") |>
    addPolygons(
      fillColor   = ~pal(mean_sentiment_score),
      fillOpacity = 0.7,
      color       = "white",
      weight      = 1,
      label       = ~paste0(name, " (", round(mean_sentiment_score, 2), ")"),
      highlightOptions = highlightOptions(
        weight = 2, color = "#4a3f35", fillOpacity = 0.9, bringToFront = TRUE
      )
    ) |>
    addLegend(
      pal      = pal,
      values   = ~mean_sentiment_score,
      title    = "Mean Sentiment",
      position = "bottomright"
    ) |>
    setView(lng = -87.6298, lat = 41.8781, zoom = 10)
}
