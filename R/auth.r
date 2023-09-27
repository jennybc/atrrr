#' Authenticate for the  API
#'
#' @param user Your user handle (e.g, benguinaudeau.bsky.social).
#' @param password Your app password (usually created on
#'   <https://bsky.app/settings/app-passwords>).
#' @param domain For now https://bsky.app/, but could change in the future.
#' @param verbose If TRUE, prints success message.
#' @param token (Stale) token object. Usually you don't need to use this. But if
#'   you manage your own tokens and they get stale, you can use this parameter
#'   and request a fresh token.
#'
#' @returns An authentication token (invisible)
#'
#' @details After requesting the token, it is safed in the location returned by
#'   `file.path(tools::R_user_dir("atr", "cache"), Sys.getenv("BSKY_TOKEN",
#'   unset = "token.rds"))`. If you have multiple tokens, you can use
#'   `Sys.setenv(BSKY_TOKEN = "filename.rds")` to save/load the token with a
#'   different name.
#'
#' @export
auth <- function(user,
                 password,
                 domain = "https://bsky.app/",
                 verbose = TRUE,
                 token = NULL) {

  if (is.null(token)) {
    url <- file.path(sub("/+$", "", domain), "settings/app-passwords")
    if (interactive()) {
      utils::browseURL(url)
      cli::cli_alert_info("Navigate to {.url {url}} and create a new app password")
    } else {
      cli::cli_abort("You need to run {.fn auth} in an interactive session")
    }

    if (missing(user))
      user <- askpass::askpass(
        "Please enter your username (e.g., \"jbgruber.bsky.social\") password"
      )

    if (missing(password))
      password <- askpass::askpass("Please enter your app password")

    if (!is.null(user) && !is.null(password)) {
      token <- req_token(user, password)
    } else {
      cli::cli_abort("You need to supply username and password.")
    }

  } else {
    if (!methods::is(token, "bsky_token"))
      cli::cli_abort("token needs to be an object of class {.emph bsky_token}")
    token <- refresh_token(token)
  }

  token$domain <- domain
  token$accessJwt <- httr2::obfuscate(token$accessJwt)
  token$refreshJwt <- httr2::obfuscate(token$refreshJwt)
  # it's not clear how long a token is valid. The docs say 'couple minutes'
  token$valid_until <- Sys.time() + 3 * 60
  # TODO: should not be necessary, but refresh seems broken
  token$password <- httr2::obfuscate(password)

  class(token) <- "bsky_token"

  f <- Sys.getenv("BSKY_TOKEN", unset = "token.rds")
  p <- tools::R_user_dir("atr", "cache")
  dir.create(p, showWarnings = FALSE, recursive = TRUE)

  # store in cache
  rlang::env_poke(env = the, nm = "bsky_token", value = token, create = TRUE)

  httr2::secret_write_rds(x = token, path = file.path(p, f),
                          key = I(rlang::hash("musksucks")))

  cli::cli_alert_success("Succesfully authenticated!")
  invisible(token)
}


req_token <- function(user, password) {
  # https://atproto.com/specs/xrpc#authentication
  httr2::request("https://bsky.social/xrpc/com.atproto.server.createSession") |>
    httr2::req_method("POST") |>
    httr2::req_body_json(list(
      identifier = user,
      password = password
    )) |>
    httr2::req_error(body = error_parse) |>
    httr2::req_perform() |>
    httr2::resp_body_json()
}


get_token <- function() {

  f <- file.path(tools::R_user_dir("atr", "cache"),
                 Sys.getenv("BSKY_TOKEN", unset = "token.rds"))

  if (rlang::env_has(the, nms = "bsky_token")) {
    token <- rlang::env_get(the, nm = "bsky_token", I(rlang::hash("musksucks")))
  } else if (file.exists(f)) {
    token <- httr2::secret_read_rds(f, I(rlang::hash("musksucks")))
  } else {
    token <- auth()
  }

  if (token$valid_until < Sys.time()) {
    token <- auth(password = token$password, token = token, verbose = FALSE)
  }

  invisible(token)
}


refresh_token <- function(token) {
  # TODO: no clue why this doesn't work
  # https://github.com/bluesky-social/atproto/blob/main/lexicons/com/atproto/server/refreshSession.json
  # httr2::request("https://bsky.social/xrpc/com.atproto.server.refreshSession") |>
  #   httr2::req_method("POST") |>
  #   httr2::req_body_json(list(
  #     accessJwt = unclass(token$accessJwt),
  #     refreshJwt = unclass(token$refreshJwt),
  #     handle = token$handle,
  #     did = token$did
  #   )) |>
  #   httr2::req_error(body = error_parse) |>
  #   httr2::req_perform() |>
  #   httr2::resp_body_json()
  req_token(unclass(token$handle), unclass(token$password))
}


#' @title Print token
#' @description Print a AT token
#' @param x An object of class \code{bsky_token}
#' @param ... not used.
#' @export
print.bsky_token <- function(x, ...) {
  cli::cli_h1("Blue Sky token")
  cli::cat_bullet(glue::glue("User: {x$handle}"),
                  background_col = "#0560FF", col = "#F3F9FF")
  cli::cat_bullet(glue::glue("Domain: {x$domain}"),
                  background_col = "#0560FF", col = "#F3F9FF")
  cli::cat_bullet(glue::glue("Valid until: {x$valid_until}"),
                  background_col = "#0560FF", col = "#F3F9FF")

}
