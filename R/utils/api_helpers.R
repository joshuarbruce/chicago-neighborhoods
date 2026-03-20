# R/utils/api_helpers.R
# httr2-based helpers for calling the Anthropic Claude API with retry + rate limiting.

library(httr2)
library(glue)

# ---------------------------------------------------------------------------
# Anthropic API configuration
# ---------------------------------------------------------------------------

ANTHROPIC_API_URL <- "https://api.anthropic.com/v1/messages"
ANTHROPIC_API_VERSION <- "2023-06-01"
DEFAULT_MODEL <- "claude-3-5-haiku-20241022"
DEFAULT_MAX_TOKENS <- 200L

get_api_key <- function() {
  key <- Sys.getenv("ANTHROPIC_API_KEY", unset = "")
  if (nchar(key) == 0) {
    stop(
      "ANTHROPIC_API_KEY is not set. ",
      "Add it to your .Renviron file (see .Renviron.example).",
      call. = FALSE
    )
  }
  key
}

# ---------------------------------------------------------------------------
# Core request function
# ---------------------------------------------------------------------------

#' Call the Anthropic Messages API with automatic retry on transient errors.
#'
#' @param prompt Character string — the user message content.
#' @param model  Model ID string.
#' @param max_tokens Maximum tokens in response.
#' @param max_retries Number of retry attempts on 429/5xx.
#' @param retry_delay_sec Seconds to wait between retries (doubles each attempt).
#' @return Character string — the assistant's text response.
call_claude <- function(
    prompt,
    model = DEFAULT_MODEL,
    max_tokens = DEFAULT_MAX_TOKENS,
    max_retries = 3L,
    retry_delay_sec = 5
) {
  key <- get_api_key()

  req <- request(ANTHROPIC_API_URL) |>
    req_headers(
      "x-api-key"         = key,
      "anthropic-version" = ANTHROPIC_API_VERSION,
      "content-type"      = "application/json"
    ) |>
    req_body_json(list(
      model      = model,
      max_tokens = max_tokens,
      messages   = list(
        list(role = "user", content = prompt)
      )
    )) |>
    req_retry(
      max_tries    = max_retries + 1L,
      retry_on_failure = TRUE,
      is_transient = \(resp) resp_status(resp) %in% c(429L, 500L, 502L, 503L, 529L),
      backoff      = \(i) retry_delay_sec * 2^(i - 1)
    ) |>
    req_timeout(60)

  resp <- req_perform(req)
  body <- resp_body_json(resp)

  # Extract text from the first content block
  text <- body$content[[1]]$text
  if (is.null(text) || !nzchar(trimws(text))) {
    stop("Claude API returned empty text. Full response: ", jsonlite::toJSON(body, auto_unbox = TRUE))
  }
  trimws(text)
}

# ---------------------------------------------------------------------------
# Batch helper
# ---------------------------------------------------------------------------

#' Call Claude for each row in a data frame, sleeping between calls.
#'
#' @param df          Data frame with one row per neighborhood.
#' @param prompt_fn   Function(row) -> character prompt string.
#' @param sleep_sec   Seconds to sleep between API calls.
#' @param verbose     Print progress if TRUE.
#' @return Character vector of AI responses, same length as nrow(df).
batch_call_claude <- function(df, prompt_fn, sleep_sec = 1, verbose = TRUE) {
  n <- nrow(df)
  results <- character(n)

  for (i in seq_len(n)) {
    if (verbose) {
      message(glue("[{i}/{n}] Calling Claude for: {df$name[i]}"))
    }
    prompt <- prompt_fn(df[i, ])
    results[i] <- tryCatch(
      call_claude(prompt),
      error = function(e) {
        warning(glue("Claude call failed for {df$name[i]}: {conditionMessage(e)}"))
        NA_character_
      }
    )
    if (i < n) Sys.sleep(sleep_sec)
  }
  results
}
