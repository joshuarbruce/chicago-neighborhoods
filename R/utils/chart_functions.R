# R/utils/chart_functions.R
# Reusable ggplot2 and leaflet chart factories for the neighborhood slides.

library(ggplot2)
library(scales)
library(dplyr)
library(leaflet)
library(sf)

# ---------------------------------------------------------------------------
# Color palette
# ---------------------------------------------------------------------------

SENTIMENT_COLORS <- c(
  "Positive"  = "#2E7D32",
  "Neutral"   = "#F9A825",
  "Negative"  = "#C62828"
)

CATEGORY_PALETTE <- c(
  "#1565C0", "#00695C", "#6A1B9A", "#E65100",
  "#37474F", "#558B2F", "#AD1457", "#4527A0",
  "#00838F", "#757575"
)

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
    geom_col(show.legend = FALSE) +
    geom_text(aes(label = comma(n)), hjust = -0.1, size = 3.5) +
    scale_fill_manual(values = CATEGORY_PALETTE) +
    scale_x_continuous(expand = expansion(mult = c(0, 0.15))) +
    labs(
      title    = "Active Business Licenses by Category",
      subtitle = neighborhood_name,
      x        = "Number of Active Licenses",
      y        = NULL
    ) +
    theme_minimal(base_size = 13) +
    theme(
      panel.grid.major.y = element_blank(),
      plot.title         = element_text(face = "bold"),
      axis.text.y        = element_text(size = 11)
    )
}

# ---------------------------------------------------------------------------
# Sentiment badge (used in slide header)
# ---------------------------------------------------------------------------

#' Return a named list with label and hex color for a sentiment label.
sentiment_badge <- function(sentiment_label) {
  list(
    label = sentiment_label,
    color = SENTIMENT_COLORS[sentiment_label]
  )
}

# ---------------------------------------------------------------------------
# Leaflet minimap
# ---------------------------------------------------------------------------

#' Create a leaflet minimap centered on a neighborhood's geometry centroid.
#'
#' @param geojson_path Path to the chicago_community_areas.geojson file.
#' @param community_area_number Integer (1–77).
#' @param neighborhood_name Character label for popup.
#' @return leaflet htmlwidget.
make_leaflet_minimap <- function(geojson_path, community_area_number, neighborhood_name) {
  areas <- sf::st_read(geojson_path, quiet = TRUE)

  # Chicago Data Portal GeoJSON uses "area_numbe" (truncated field name)
  area_col <- if ("area_numbe" %in% names(areas)) "area_numbe" else "community_area_number"
  target <- areas[as.integer(areas[[area_col]]) == community_area_number, ]

  centroid <- sf::st_centroid(sf::st_geometry(target))
  coords   <- sf::st_coordinates(centroid)
  lng <- coords[1]
  lat <- coords[2]

  leaflet(options = leafletOptions(zoomControl = FALSE)) |>
    addProviderTiles("CartoDB.Positron") |>
    addPolygons(
      data        = target,
      fillColor   = "#1565C0",
      fillOpacity = 0.35,
      color       = "#0D47A1",
      weight      = 2,
      popup       = neighborhood_name
    ) |>
    setView(lng = lng, lat = lat, zoom = 13)
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
    palette = c("#C62828", "#F9A825", "#2E7D32"),
    domain  = merged$mean_sentiment_score,
    na.color = "#BDBDBD"
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
        weight    = 2,
        color     = "#333",
        fillOpacity = 0.9,
        bringToFront = TRUE
      )
    ) |>
    addLegend(
      pal      = pal,
      values   = ~mean_sentiment_score,
      title    = "Mean Sentiment Score",
      position = "bottomright"
    ) |>
    setView(lng = -87.6298, lat = 41.8781, zoom = 10)
}
