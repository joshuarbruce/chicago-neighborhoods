# Chicago's 77 Neighborhoods — Data Portrait

Chicago organizes itself into 77 official community areas — a boundary system stable enough to anchor decades of demographic and planning data, yet granular enough that neighborhoods with fewer than a mile between them can feel like different cities. This project builds a data portrait of each one, combining active business license records, Reddit community discussion, and Airbnb guest reviews to ask: what does each neighborhood *do*, what do *residents* talk about, and what do *visitors* notice?

The output is a [Quarto Reveal.js slide deck](https://joshuarbruce.github.io/chicago-neighborhoods/) — one slide per neighborhood — with an AI-generated summary synthesizing all three sources, a business category breakdown, and side-by-side TF-IDF phrase charts showing the resident voice (Reddit) alongside the visitor voice (Airbnb reviews).

**[View the slide deck →](https://joshuarbruce.github.io/chicago-neighborhoods/)**

---

## What the Data Shows

**The business geography is stark.** The Loop (5,573 active licenses), Near North Side (6,391), and Near West Side (3,130) account for a disproportionate share of Chicago's commercial activity. The Near North Side also scores highest on business diversity — its mix of food, retail, health, and professional services is nearly evenly spread across categories. At the other end, neighborhoods like Burnside and Riverdale have both the fewest businesses and the least diversified mix.

**Diversity doesn't always follow density.** Edison Park, a quiet far-northwest neighborhood, ranks first on the Shannon entropy diversity index despite modest business counts — its small commercial strip covers many categories. North Lawndale ranks third, reflecting a mixed-use commercial corridor. The simplest business profiles cluster in the most economically isolated communities.

**Reddit's coverage map mirrors Chicago's attention economy.** Well-known lakefront neighborhoods — Logan Square, Hyde Park, Lincoln Park — generate hundreds of posts. Many South and West Side neighborhoods are nearly silent: Montclare and West Englewood had no usable Reddit data; Burnside had one post. This isn't just a data quality footnote — it's a finding. Where communities are underrepresented online, the data can only say so.

**TF-IDF surfaces the genuinely local.** The bi- and tri-gram distinctive phrase analysis tends to find things that only make sense if you've lived there. Irving Park's top phrases include "ice cream" — a nod to the neighborhood's unusually dense dessert shop scene. Lincoln Park's include "juvenile geese" — a very real seasonal hazard for anyone who walks along the lakefront path there. The Loop surfaces "central business district" and "trump tower"; Pilsen surfaces "murals" and "18th street."

**Sentiment skews relentlessly positive.** 74 of 77 neighborhoods score Positive; 3 score Neutral; none score Negative. This is partly a function of how people write about their neighborhoods on Reddit (with local pride), and partly a limitation of AFINN's general-purpose lexicon, which doesn't capture the register of civic complaint that shows up in community discourse. The sentiment scores are meaningful as relative signals but shouldn't be taken as ground truth.

**Residents and visitors notice different things.** The most consistent pattern in the Airbnb review TF-IDF is proximity language — "walking distance," "close transit," "easy access" — that rarely surfaces in Reddit discussions, where locals take transit access as given. Visitor phrases also concentrate on amenity specifics (coffee shops, restaurants, parking) while resident phrases capture local events, community issues, and neighborhood character. Near North Side visitors emphasize "Michigan Avenue" and "lake view"; residents discuss "alderman," "construction permits," and "dog parks." The gap between what a neighborhood markets to visitors and what residents actually care about is itself a data signal.

---

## Methodology

### Business data

Active business licenses (~77,877 records) come from the Chicago Data Portal Socrata API, filtered to `license_status = AAC`. Chicago issues licenses under roughly 200 distinct types; these are collapsed into 10 categories (Food & Beverage, Retail, Health, etc.) using keyword matching. Business diversity per neighborhood is measured with Shannon entropy: higher values indicate a more evenly spread license mix.

### Reddit collection

Posts are collected using Reddit's public JSON endpoints — no OAuth, no API key. For each neighborhood the collector tries: (1) a dedicated neighborhood subreddit if one exists, (2) a keyword search of r/chicago, and (3) a fallback to r/AskChicago if r/chicago returns fewer than 15 posts. Each source is paginated up to 1,000 posts, with a 3.5-second delay between requests to stay well within rate limits. The result is 10,534 posts across 77 neighborhoods.

### Sentiment analysis

Posts are tokenized with `tidytext::unnest_tokens()`. AFINN scores (−5 to +5) are summed per post and then divided by word count, so longer posts don't dominate the neighborhood average. Bing (positive/negative ratio) is computed as a secondary signal. Neighborhoods below 10 posts are flagged `low_reddit`; those with no Reddit data are flagged `business_only`.

### Distinctive phrases

Rather than word frequency, which surfaces common words shared across all neighborhoods, TF-IDF on bi- and tri-gram phrases finds terms that are *specifically* elevated for one neighborhood relative to the others. After scoring, shorter phrases that appear as substrings of higher-ranked longer phrases are removed — so "lincoln yards" is dropped when "lincoln yards development" already appears. This consistently produces more specific, more interesting results than unigrams or unsuppressed bigrams.

### Airbnb data

Listing and review data comes from [Inside Airbnb](https://insideairbnb.com/) (two Chicago snapshots: June and September 2025). Each listing is assigned to a community area via spatial join — using its latitude/longitude against the official Chicago community area polygons — rather than Airbnb's own neighborhood labels, which use a different boundary system. The two snapshots are combined: listings are deduplicated keeping the most recent record; reviews are deduplicated by listing, date, and reviewer, yielding 519,747 unique reviews across 76 of 77 neighborhoods. Review text runs through the same NLP pipeline as Reddit posts: cleaning, stopword removal, bi/trigram TF-IDF with sub-phrase deduplication. An additional layer of Airbnb-specific stopwords suppresses generic hospitality language ("great stay," "clean," "host") to surface what's genuinely distinctive about each neighborhood's visitor experience.

### AI summaries

Each neighborhood's slide leads with a 3–4 sentence summary generated by `claude-haiku-4-5-20251001` via the Anthropic API. The prompt synthesizes all three data sources — business composition, resident Reddit discussion, and Airbnb visitor reviews — and explicitly prohibits drawing on general knowledge. When the Reddit and Airbnb phrase sets diverge noticeably, the model is instructed to name the gap. Every claim is traceable to the input data. Summaries are cached to git so re-rendering the deck never requires an API call.

### Visual design

The slide deck uses a Tufte-inspired aesthetic throughout: a cream background, Palatino serif typography, and a muted earth-tone palette that reserves color for data rather than decoration. Charts use a custom `theme_tufte_slide()` ggplot2 theme with no gridlines, faint vertical reference lines at meaningful values, and a single axis rule. Sentiment colors are muted sage green, warm gold, and brick red. The two TF-IDF charts on each slide use distinct accent colors — slate teal for Reddit (resident voice) and ochre for Airbnb (visitor voice) — so the contrast is visible at a glance. Both charts are CSS-anchored to the bottom of their columns so they align consistently across slides where the AI summary varies in length.

---

## Reproducing the Project

### Prerequisites

- R ≥ 4.3 with `renv` (restores all packages from lockfile)
- Python ≥ 3.10
- Quarto CLI
- Anthropic API key (only needed to regenerate AI summaries; not needed to re-render slides)

### Setup

```bash
git clone https://github.com/joshuarbruce/chicago-neighborhoods.git
cd chicago-neighborhoods

# Restore R packages
Rscript -e "renv::restore()"

# Python packages
pip install -r python/requirements.txt
```

### Re-render slides from committed data

No API key or pipeline run required — all summaries and processed data are committed:

```bash
quarto render slides/chicago_neighborhoods.qmd

# Test render (5 neighborhoods)
NEIGHBORHOOD_SUBSET=5 quarto render slides/chicago_neighborhoods.qmd
```

### Run the full pipeline

```bash
# Business data (requires local CSV from Chicago Data Portal bulk download)
Rscript R/01_fetch_business_data.R
Rscript R/02_process_business_data.R

# Airbnb data (downloads automatically from insideairbnb.com)
Rscript R/02b_process_airbnb_data.R

# Reddit collection (~6 hours; 3.5s delay, up to 1,000 posts/neighborhood)
python3 python/fetch_reddit.py

# NLP processing
Rscript R/03_process_reddit_data.R

# AI summaries (requires ANTHROPIC_API_KEY in .Renviron)
# Idempotent by default — skips existing files
# Add --force to delete and regenerate all 77 summaries (e.g. after prompt changes)
Rscript R/04_generate_ai_summaries.R --force

# Assemble master dataset
Rscript R/05_build_neighborhood_metrics.R

# Render
quarto render slides/chicago_neighborhoods.qmd
```

---

## Data Sources & Licensing

**Business licenses:** [City of Chicago Data Portal](https://data.cityofchicago.org/) under the [Chicago Data Portal Terms of Use](https://www.chicago.gov/city/en/narr/foia/data_disclaimer.html).

**Community area boundaries:** [Chicago Data Portal GeoJSON](https://data.cityofchicago.org/Facilities-Geographic-Boundaries/Boundaries-Community-Areas-current-/cauq-8yn6).

**Reddit data:** Collected via Reddit's public JSON API per Reddit's [Terms of Service](https://www.redditinc.com/policies/user-agreement). Post content remains the property of respective authors.

**Airbnb listing and review data:** [Inside Airbnb](https://insideairbnb.com/) under the [Creative Commons Attribution 4.0 International License](https://creativecommons.org/licenses/by/4.0/). Review content remains the property of respective authors.

**Sentiment lexicons:** AFINN © Finn Årup Nielsen; Bing lexicon from Bing Liu et al.; both accessed via the [tidytext](https://github.com/juliasilge/tidytext) R package.

**AI summaries:** Generated with the [Anthropic Claude API](https://www.anthropic.com). Summaries are derived solely from project data and do not represent Anthropic's views.

---

© 2026 Joshua R. Bruce. Code released under the [MIT License](LICENSE).
