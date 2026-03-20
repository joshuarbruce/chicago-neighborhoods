# Chicago Neighborhoods Data Analysis

A public portfolio project profiling all 77 of Chicago's official community areas using business license data and Reddit community discussion.

**Live Slides:** https://joshuarbruce.github.io/chicago-neighborhoods/

## What's in Here

Each neighborhood gets a slide with:
- AI-generated summary (Claude claude-3-5-haiku-20241022) drawn from data, not general knowledge
- Business category breakdown (active licenses from Chicago Data Portal)
- Sentiment analysis from Reddit posts (r/chicago + neighborhood subreddits)
- Interactive leaflet minimap
- Top Reddit word cloud

Opening slide: choropleth of all 77 neighborhoods colored by sentiment score.

## Tech Stack

| Layer | Tool |
|-------|------|
| Data wrangling | R + tidyverse |
| Business data | Chicago Data Portal Socrata API |
| Reddit data | Python (public JSON endpoints, no OAuth) |
| NLP / Sentiment | tidytext + AFINN + bing lexicons |
| AI summaries | Anthropic Claude API via httr2 |
| Slides | Quarto Reveal.js |
| Hosting | GitHub Pages (`docs/`) |
| Package mgmt | renv |

## Running the Pipeline

### Prerequisites

- R >= 4.3
- Python >= 3.10
- Quarto CLI >= 1.4
- An Anthropic API key (for Stage 6 only)

### Setup

```bash
# Clone the repo
git clone https://github.com/joshuarbruce/chicago-neighborhoods.git
cd chicago-neighborhoods

# R packages (renv restores from lockfile)
Rscript -e "renv::restore()"

# Python packages
pip install -r python/requirements.txt

# Copy and fill in your API key
cp .Renviron.example .Renviron
# Edit .Renviron and add your ANTHROPIC_API_KEY
```

### Quick Test (3 neighborhoods, ~5 min)

```r
Rscript test_pipeline.R
```

### Full Pipeline

```r
Rscript run_pipeline.R
```

Or run stages individually:

```r
Rscript R/01_fetch_business_data.R     # Download business licenses
Rscript R/02_process_business_data.R   # Classify + summarize by neighborhood
python python/fetch_reddit.py          # Collect Reddit posts
Rscript R/03_process_reddit_data.R     # Sentiment analysis
Rscript R/04_generate_ai_summaries.R  # AI summaries (needs API key)
Rscript R/05_build_neighborhood_metrics.R  # Assemble master dataset
```

### Render Slides

```bash
# Full render
quarto render slides/chicago_neighborhoods.qmd

# Subset (5 neighborhoods, for testing)
NEIGHBORHOOD_SUBSET=5 quarto render slides/chicago_neighborhoods.qmd

# Local preview
quarto preview slides/chicago_neighborhoods.qmd
```

## Data Sources

- **Business Licenses:** [Chicago Data Portal](https://data.cityofchicago.org/Community-Economic-Development/Business-Licenses/r5kz-chrr) — filtered to active licenses (`license_status = AAC`)
- **Reddit:** Public JSON API (r/chicago + neighborhood subreddits where available)
- **Community Area Boundaries:** [Chicago Data Portal GeoJSON](https://data.cityofchicago.org/Facilities-Geographic-Boundaries/Boundaries-Community-Areas-current-/cauq-8yn6)

## Project Structure

```
chicago_neighborhoods/
├── data/
│   ├── raw/              # Not committed (regenerable)
│   ├── processed/
│   │   └── ai_summaries/ # Committed (costly to regenerate)
│   └── reference/        # Committed (stable reference files)
├── R/                    # Analysis scripts (stages 1–5, 7)
│   └── utils/            # Shared helpers
├── python/               # Reddit collection (stage 4)
├── slides/               # Quarto source
├── docs/                 # Rendered output → GitHub Pages
└── run_pipeline.R        # Full pipeline orchestrator
```

## Notes on Data Quality

Some neighborhoods have very little Reddit activity. The `data_quality_flag` field marks each neighborhood as:
- `full` — business + Reddit data available (≥10 posts)
- `low_reddit` — Reddit data thin (<10 posts), used with caution
- `business_only` — no usable Reddit data; AI summary omits Reddit signals

AI summaries are cached to `data/processed/ai_summaries/` and committed so the Quarto render step doesn't require an API key.

## Data Licensing & Attribution

**Business license data** and **community area boundaries** are published by the City of Chicago under the [Chicago Data Portal Terms of Use](https://www.chicago.gov/city/en/narr/foia/data_disclaimer.html). The City of Chicago makes no warranty regarding the accuracy or completeness of this data.

**Reddit data** is collected via Reddit's public JSON API in accordance with Reddit's [Terms of Service](https://www.redditinc.com/policies/user-agreement). Post content remains the property of the respective authors.

**AI-generated summaries** are produced using the [Anthropic Claude API](https://www.anthropic.com). Summaries are derived solely from the quantitative data collected for this project and do not represent Anthropic's views.

**Sentiment lexicons** (AFINN, Bing) are used via the [tidytext](https://github.com/juliasilge/tidytext) R package. AFINN is © Finn Årup Nielsen; Bing lexicon is from Bing Liu and collaborators.

## Copyright

© 2026 Joshua R. Bruce. Code and original analysis in this repository are released under the [MIT License](LICENSE). Data files from third-party sources retain their original licenses as noted above.
