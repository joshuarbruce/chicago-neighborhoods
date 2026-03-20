"""
fetch_reddit.py — Stage 4: Reddit data collection for Chicago neighborhoods.

Uses Reddit's public JSON endpoints (no OAuth required).
Writes one JSON file per neighborhood to data/raw/reddit/{slug}.json
and a collection_log.csv summarizing results.

Usage:
    python python/fetch_reddit.py                     # All 77 neighborhoods
    python python/fetch_reddit.py --slugs rogers_park hyde_park  # Specific neighborhoods
    python python/fetch_reddit.py --test              # Test subset (Rogers Park, Hyde Park, Riverdale)
"""

import json
import logging
import time
import argparse
from pathlib import Path
import pandas as pd
import requests

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
BASE_DIR = Path(__file__).resolve().parent.parent
CONFIG_PATH = Path(__file__).resolve().parent / "neighborhood_config.json"
OUTPUT_DIR = BASE_DIR / "data" / "raw" / "reddit"
LOG_PATH = OUTPUT_DIR / "collection_log.csv"

with open(CONFIG_PATH) as f:
    config = json.load(f)

REDDIT_BASE = config["reddit_base_url"]
USER_AGENT = config["user_agent"]
DELAY = config["request_delay_seconds"]
MIN_POSTS = config["min_posts_threshold"]
PRIMARY_SUB = config["primary_subreddit"]
FALLBACK_SUB = config["fallback_subreddit"]
POST_LIMIT = config["post_limit"]
TIME_FILTER = config["time_filter"]

HEADERS = {"User-Agent": USER_AGENT}

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger(__name__)

OUTPUT_DIR.mkdir(parents=True, exist_ok=True)


# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------

def get_json(url: str, params: dict = None) -> dict | None:
    """GET a Reddit JSON endpoint; return parsed dict or None on error."""
    try:
        resp = requests.get(url, headers=HEADERS, params=params, timeout=15)
        if resp.status_code == 404:
            log.warning("404 Not Found: %s", url)
            return None
        if resp.status_code == 429:
            log.warning("429 Rate Limited — sleeping 30s then retrying: %s", url)
            time.sleep(30)
            resp = requests.get(url, headers=HEADERS, params=params, timeout=15)
        resp.raise_for_status()
        return resp.json()
    except requests.RequestException as e:
        log.error("Request failed for %s: %s", url, e)
        return None


def extract_posts(data: dict) -> list[dict]:
    """Pull post records from a Reddit listing JSON."""
    if not data:
        return []
    try:
        children = data["data"]["children"]
    except (KeyError, TypeError):
        return []
    posts = []
    for child in children:
        p = child.get("data", {})
        posts.append({
            "id":           p.get("id"),
            "title":        p.get("title", ""),
            "selftext":     p.get("selftext", ""),
            "score":        p.get("score", 0),
            "num_comments": p.get("num_comments", 0),
            "created_utc":  p.get("created_utc"),
            "subreddit":    p.get("subreddit"),
            "url":          p.get("url"),
            "permalink":    p.get("permalink"),
            "author":       p.get("author"),
        })
    return posts


# ---------------------------------------------------------------------------
# Collection logic
# ---------------------------------------------------------------------------

def fetch_subreddit_posts(subreddit: str, slug: str) -> list[dict]:
    """Fetch new + top posts from a dedicated neighborhood subreddit."""
    posts = []
    for sort in ("new", "top"):
        url = f"{REDDIT_BASE}/r/{subreddit}/{sort}.json"
        params = {"limit": POST_LIMIT}
        if sort == "top":
            params["t"] = TIME_FILTER
        data = get_json(url, params)
        time.sleep(DELAY)
        posts.extend(extract_posts(data))
    # Deduplicate by post id
    seen = set()
    unique = []
    for p in posts:
        if p["id"] not in seen:
            seen.add(p["id"])
            unique.append(p)
    log.info("  Subreddit r/%s: %d unique posts", subreddit, len(unique))
    return unique


def search_subreddit(subreddit: str, search_term: str) -> list[dict]:
    """Search within a subreddit for a neighborhood term."""
    url = f"{REDDIT_BASE}/r/{subreddit}/search.json"
    params = {
        "q":           search_term,
        "restrict_sr": 1,
        "sort":        "relevance",
        "t":           TIME_FILTER,
        "limit":       POST_LIMIT,
    }
    data = get_json(url, params)
    time.sleep(DELAY)
    posts = extract_posts(data)
    log.info("  Search r/%s q=%r: %d posts", subreddit, search_term, len(posts))
    return posts


def collect_neighborhood(neighborhood: dict) -> dict:
    """
    Collect posts for a single neighborhood.
    Returns a summary dict for the collection log.
    """
    slug = neighborhood["slug"]
    name = neighborhood["name"]
    subreddit = neighborhood.get("subreddit")  # may be null
    search_term = neighborhood["search_term"]
    out_path = OUTPUT_DIR / f"{slug}.json"

    if out_path.exists():
        log.info("[SKIP] %s — already collected", name)
        existing = json.loads(out_path.read_text())
        return {
            "slug":          slug,
            "name":          name,
            "post_count":    len(existing.get("posts", [])),
            "sources":       ",".join(existing.get("sources", [])),
            "status":        "skipped",
        }

    log.info("[COLLECT] %s", name)
    all_posts = []
    sources = []

    # (a) Dedicated neighborhood subreddit if it exists
    if subreddit:
        sub_posts = fetch_subreddit_posts(subreddit, slug)
        all_posts.extend(sub_posts)
        sources.append(f"r/{subreddit}")

    # (b) Always search r/chicago
    chicago_posts = search_subreddit(PRIMARY_SUB, search_term)
    all_posts.extend(chicago_posts)
    if chicago_posts:
        sources.append(f"r/{PRIMARY_SUB}")

    # (c) If fewer than MIN_POSTS from r/chicago, try fallback subreddit
    if len(chicago_posts) < MIN_POSTS:
        log.info("  r/chicago returned %d posts (< %d) — trying fallback r/%s",
                 len(chicago_posts), MIN_POSTS, FALLBACK_SUB)
        fallback_posts = search_subreddit(FALLBACK_SUB, search_term)
        all_posts.extend(fallback_posts)
        if fallback_posts:
            sources.append(f"r/{FALLBACK_SUB}")

    # Deduplicate across all sources
    seen = set()
    unique_posts = []
    for p in all_posts:
        if p["id"] and p["id"] not in seen:
            seen.add(p["id"])
            unique_posts.append(p)

    payload = {
        "slug":    slug,
        "name":    name,
        "sources": sources,
        "posts":   unique_posts,
    }
    out_path.write_text(json.dumps(payload, indent=2, ensure_ascii=False))
    log.info("  Wrote %d unique posts → %s", len(unique_posts), out_path.name)

    return {
        "slug":       slug,
        "name":       name,
        "post_count": len(unique_posts),
        "sources":    ",".join(sources),
        "status":     "collected",
    }


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Collect Reddit posts for Chicago neighborhoods")
    parser.add_argument("--slugs", nargs="+", help="Only collect these slugs")
    parser.add_argument("--test", action="store_true",
                        help="Test mode: Rogers Park, Hyde Park, Riverdale")
    args = parser.parse_args()

    neighborhoods = config["neighborhoods"]

    if args.test:
        test_slugs = {"rogers_park", "hyde_park", "riverdale"}
        neighborhoods = [n for n in neighborhoods if n["slug"] in test_slugs]
        log.info("Test mode: %d neighborhoods", len(neighborhoods))
    elif args.slugs:
        slug_set = set(args.slugs)
        neighborhoods = [n for n in neighborhoods if n["slug"] in slug_set]
        log.info("Subset mode: %d neighborhoods", len(neighborhoods))

    log.info("Collecting %d neighborhoods", len(neighborhoods))
    log_rows = []

    for i, nbhd in enumerate(neighborhoods, 1):
        log.info("(%d/%d)", i, len(neighborhoods))
        row = collect_neighborhood(nbhd)
        log_rows.append(row)

    # Write / append collection log
    log_df = pd.DataFrame(log_rows)
    if LOG_PATH.exists():
        existing_log = pd.read_csv(LOG_PATH)
        # Replace rows for re-collected slugs
        existing_log = existing_log[~existing_log["slug"].isin(log_df["slug"])]
        log_df = pd.concat([existing_log, log_df], ignore_index=True)
    log_df.to_csv(LOG_PATH, index=False)
    log.info("Collection log written to %s", LOG_PATH)
    log.info("Done. Total neighborhoods: %d", len(log_rows))


if __name__ == "__main__":
    main()
