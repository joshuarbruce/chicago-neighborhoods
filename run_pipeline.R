# run_pipeline.R — Full pipeline orchestrator
# Runs all 8 stages in order.
# Usage: Rscript run_pipeline.R

message("=== Chicago Neighborhoods Pipeline ===")
message("Started: ", Sys.time())

steps <- list(
  list(label = "Stage 2: Fetch business data",         script = "R/01_fetch_business_data.R"),
  list(label = "Stage 3: Process business data",       script = "R/02_process_business_data.R"),
  list(label = "Stage 5: Process Reddit + sentiment",  script = "R/03_process_reddit_data.R"),
  list(label = "Stage 6: Generate AI summaries",       script = "R/04_generate_ai_summaries.R"),
  list(label = "Stage 7: Build neighborhood metrics",  script = "R/05_build_neighborhood_metrics.R")
)

# Reddit collection (Python) must be run manually between stages 2 and 3:
# python python/fetch_reddit.py
message("\nNOTE: Reddit collection (Stage 4) is Python-based.")
message("      Run 'python python/fetch_reddit.py' before Stage 5 if Reddit data is stale.\n")

for (step in steps) {
  message("\n--- ", step$label, " ---")
  source(step$script, local = new.env())
}

message("\n=== Pipeline complete ===")
message("Finished: ", Sys.time())
message("\nNext: quarto render slides/chicago_neighborhoods.qmd")
