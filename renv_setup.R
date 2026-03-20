# renv_setup.R — Run this once interactively to initialize renv.
# Do NOT run via Rscript (renv::init() requires interactive confirmation).
#
# In an R session:
#   source("renv_setup.R")

# Initialize renv (creates renv/ and renv.lock)
renv::init()

# Install all required packages
packages <- c(
  # Tidyverse core
  "tidyverse", "scales", "ggtext", "patchwork", "forcats",
  # HTTP
  "httr2",
  # Text / NLP
  "tidytext", "textdata", "SnowballC", "wordcloud2",
  # Geospatial
  "sf", "leaflet", "htmlwidgets",
  # Utilities
  "jsonlite", "here", "glue", "assertthat", "knitr", "renv"
)

install.packages(packages)

# Snapshot to renv.lock
renv::snapshot()

message("renv setup complete. Commit renv.lock to git.")
