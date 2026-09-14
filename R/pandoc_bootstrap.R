# ============================================================
# R/pandoc_bootstrap.R
#
# Pandoc without a manual install, on Windows, macOS and Linux.
#
# Pandoc is only needed to render the final HTML report and its Word
# copy. Rather than asking every user to install it (admin rights,
# Gatekeeper, PATH problems), this file:
#
#   1. looks for a usable Pandoc (>= 2.8) in the places it is commonly
#      found, including a copy this package downloaded earlier; and
#   2. if none is found, downloads one pinned, checksum-verified release
#      straight from GitHub into a per-user cache folder and uses that.
#
# It uses only base R (utils::download.file / unzip / untar). It does NOT
# use the CRAN `pandoc`, `gh`, `httr2` or `rlang` packages, whose version
# interplay broke the wizard.5.3 Pandoc step on macOS.
#
# No administrator rights are needed. Nothing is written outside the
# per-user R cache directory (tools::R_user_dir("EU_SAE", "cache")) or,
# when present, the package's own tools/pandoc/ folder.
#
# Offline use (local only: the release builder copies inventory files only,
# so tools/pandoc/ is never part of a built ZIP): put the extracted
# `pandoc.exe` (Windows) or `pandoc` (macOS/Linux) in <extracted package>/
# tools/pandoc/, or set EU_SAE_PANDOC=/folder/containing/pandoc.
# Set EU_SAE_PANDOC_OFFLINE=1 to forbid downloads.
#
# Public entry points:
#   sae_find_pandoc(root, min_version)   -> list(dir, version) or NULL
#   sae_ensure_pandoc(root, min_version, allow_download, quiet)
#        -> list(ok, dir, version, source, reason); ok = FALSE carries `reason`.
# On success both point rmarkdown at the selected folder explicitly
# (rmarkdown::find_pandoc(dir = )) and verify it took, so the version rmarkdown
# renders with is the one reported here.
#
# Download policy: one pinned release, SHA-256 must be computed AND match or
# nothing is extracted; download timeout is bounded (EU_SAE_PANDOC_TIMEOUT,
# default 600 s); at most one download attempt per R session, so a failure at
# setup is not repeated after a long estimation run.
# ============================================================

.sae_pandoc_release <- list(
  version  = "3.11",
  base_url = "https://github.com/jgm/pandoc/releases/download/3.11/",
  assets   = list(
    "windows-x86_64" = list(file = "pandoc-3.11-windows-x86_64.zip",
                            sha256 = "2ab72baf2399450e148ddf7a2a8689806c42e1bba71862b57e220fd9b8456d3d"),
    "macos-arm64"    = list(file = "pandoc-3.11-arm64-macOS.zip",
                            sha256 = "15806bedf9517bfead72e88fe6a6696635c3691efbb6e152173440e9c5bb50b4"),
    "macos-x86_64"   = list(file = "pandoc-3.11-x86_64-macOS.zip",
                            sha256 = "3b1c1b57f160112c821d02f23d946ede8b7f57a6ccf4632a25a512d334a9291f"),
    "linux-amd64"    = list(file = "pandoc-3.11-linux-amd64.tar.gz",
                            sha256 = "37edb3bbcf722f921a009941bf5874e2e0c09263226c9b4a2d980788cb062ab6"),
    "linux-arm64"    = list(file = "pandoc-3.11-linux-arm64.tar.gz",
                            sha256 = "56ed5566ec41d22ec9ee0704e6ac0b98ba102e92384efd5306173a22d314c79a")
  )
)

# ---- Platform -------------------------------------------------------------

sae_pandoc_platform <- function() {
  machine <- tolower(Sys.info()[["machine"]])
  sysname <- tolower(Sys.info()[["sysname"]])
  if (.Platform$OS.type == "windows") return("windows-x86_64")   # also runs on ARM Windows via emulation
  if (sysname == "darwin") {
    return(if (grepl("arm|aarch", machine)) "macos-arm64" else "macos-x86_64")
  }
  if (sysname == "linux") {
    return(if (grepl("aarch64|arm64", machine)) "linux-arm64" else "linux-amd64")
  }
  NA_character_
}

.sae_pandoc_exe_name <- function() {
  if (.Platform$OS.type == "windows") "pandoc.exe" else "pandoc"
}

# ---- Locating an existing Pandoc ------------------------------------------

# Run `pandoc --version` in `dir`; return numeric_version or NULL.
sae_pandoc_version_at <- function(dir) {
  if (is.null(dir) || length(dir) != 1L || is.na(dir) || !nzchar(dir)) return(NULL)
  exe <- file.path(dir, .sae_pandoc_exe_name())
  if (!file.exists(exe)) return(NULL)
  out <- tryCatch(suppressWarnings(system2(exe, "--version", stdout = TRUE, stderr = TRUE)),
                  error = function(e) character())
  if (!length(out)) return(NULL)
  m <- regmatches(out[1], regexpr("[0-9]+(\\.[0-9]+)+", out[1]))
  if (!length(m)) return(NULL)
  tryCatch(numeric_version(m), error = function(e) NULL)
}

sae_pandoc_cache_dir <- function() {
  # Per-user, outside the package folder (so it is not synced by OneDrive
  # and survives upgrading to the next package version).
  d <- tryCatch(tools::R_user_dir("EU_SAE", which = "cache"), error = function(e) NULL)
  if (is.null(d) || !nzchar(d)) {
    d <- file.path(if (.Platform$OS.type == "windows") Sys.getenv("LOCALAPPDATA") else path.expand("~"),
                   ".eu_sae_cache")
  }
  file.path(d, "pandoc")
}

.sae_path_dirs <- function() {
  p <- strsplit(Sys.getenv("PATH"), .Platform$path.sep, fixed = TRUE)[[1]]
  p[nzchar(p)]
}

.sae_dirs_containing <- function(parent, exe) {
  if (!dir.exists(parent)) return(character())
  hits <- list.files(parent, pattern = paste0("^", gsub(".", "\\.", exe, fixed = TRUE), "$"),
                     recursive = TRUE, full.names = TRUE)
  unique(dirname(hits))
}

# Ordered candidate folders. Earlier entries win.
sae_pandoc_candidate_dirs <- function(root = getwd()) {
  exe <- .sae_pandoc_exe_name()
  win <- .Platform$OS.type == "windows"
  pf  <- Sys.getenv("ProgramFiles"); lad <- Sys.getenv("LOCALAPPDATA"); pfx <- Sys.getenv("ProgramFiles(x86)")
  c(
    # 1. Explicit override.
    Sys.getenv("EU_SAE_PANDOC"),
    # 2. A copy shipped inside this package (offline distribution).
    .sae_dirs_containing(file.path(root, "tools", "pandoc"), exe),
    # 3. A copy this package downloaded earlier.
    .sae_dirs_containing(sae_pandoc_cache_dir(), exe),
    # 4. Whatever rmarkdown / RStudio already know about, and PATH.
    Sys.getenv("RSTUDIO_PANDOC"),
    .sae_path_dirs(),
    # 5. Bundled with RStudio, Positron, Quarto.
    if (win) c(
      file.path(pf,  "RStudio/resources/app/bin/quarto/bin/tools"),
      file.path(pf,  "RStudio/resources/app/bin/quarto/bin/tools/x86_64"),
      file.path(pf,  "RStudio/bin/pandoc"),
      file.path(lad, "Programs/RStudio/resources/app/bin/quarto/bin/tools"),
      file.path(lad, "Programs/RStudio/resources/app/bin/quarto/bin/tools/x86_64"),
      file.path(lad, "Programs/Positron/resources/app/quarto/bin/tools/x86_64"),
      file.path(pf,  "Positron/resources/app/quarto/bin/tools/x86_64"),
      file.path(pf,  "Quarto/bin/tools"), file.path(pf, "Quarto/bin/tools/x86_64"),
      file.path(lad, "Programs/Quarto/bin/tools"), file.path(lad, "Programs/Quarto/bin/tools/x86_64"),
      file.path(pf,  "Pandoc"), file.path(lad, "Pandoc"), file.path(pfx, "Pandoc")
    ) else c(
      "/Applications/RStudio.app/Contents/Resources/app/bin/quarto/bin/tools",
      "/Applications/RStudio.app/Contents/Resources/app/bin/quarto/bin/tools/aarch64",
      "/Applications/RStudio.app/Contents/Resources/app/bin/quarto/bin/tools/x86_64",
      "/Applications/RStudio.app/Contents/Resources/app/quarto/bin/tools",
      "/Applications/Positron.app/Contents/Resources/app/quarto/bin/tools/aarch64",
      "/Applications/Positron.app/Contents/Resources/app/quarto/bin/tools/x86_64",
      "/Applications/quarto/bin/tools", "/Applications/quarto/bin/tools/aarch64",
      "/Applications/quarto/bin/tools/x86_64",
      "/usr/lib/rstudio/resources/app/bin/quarto/bin/tools",
      "/usr/lib/rstudio/resources/app/bin/quarto/bin/tools/x86_64",
      "/opt/quarto/bin/tools", "/opt/quarto/bin/tools/x86_64",
      # 6. Package managers and the pandoc.org .pkg installer.
      "/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin", "/usr/bin",
      "/opt/pandoc", path.expand("~/opt/pandoc"),
      # 7. The CRAN `pandoc` R package's own install folder (if a user has it).
      .sae_dirs_containing(path.expand("~/Library/Application Support/r-pandoc"), exe),
      .sae_dirs_containing(path.expand("~/.local/share/r-pandoc"), exe)
    ),
    if (win) .sae_dirs_containing(file.path(lad, "r-pandoc"), exe)
  )
}

.sae_use_pandoc_dir <- function(dir, version) {
  dir <- normalizePath(dir, winslash = "/", mustWork = FALSE)
  Sys.setenv(RSTUDIO_PANDOC = dir)
  if (requireNamespace("rmarkdown", quietly = TRUE)) {
    # Pin rmarkdown to THIS folder. Without `dir`, find_pandoc() re-scans its own
    # sources and keeps the highest version it sees (e.g. a newer copy on PATH),
    # silently overriding the selection made here and any EU_SAE_PANDOC override.
    seen <- tryCatch(rmarkdown::find_pandoc(cache = FALSE, dir = dir), error = function(e) NULL)
    seen_dir <- tryCatch(normalizePath(seen$dir, winslash = "/", mustWork = FALSE), error = function(e) "")
    if (is.null(seen) || !identical(seen_dir, dir) || is.null(seen$version) ||
        seen$version != version) {
      return(NULL)
    }
  }
  list(dir = dir, version = version)
}

# Find a usable Pandoc >= min_version. Returns list(dir, version) or NULL.
sae_find_pandoc <- function(root = getwd(), min_version = "2.8") {
  min_version <- numeric_version(min_version)
  seen <- character()
  for (d in sae_pandoc_candidate_dirs(root)) {
    if (is.null(d) || is.na(d) || !nzchar(d)) next
    d <- tryCatch(normalizePath(d, winslash = "/", mustWork = FALSE), error = function(e) d)
    if (d %in% seen) next
    seen <- c(seen, d)
    v <- sae_pandoc_version_at(d)
    if (is.null(v) || v < min_version) next
    used <- .sae_use_pandoc_dir(d, v)
    if (!is.null(used)) return(used)
  }
  NULL
}

# ---- Downloading a pinned release -----------------------------------------

# SHA-256 of a file, or NA_character_ if it cannot be computed here.
.sae_sha256 <- function(path) {
  if (!file.exists(path)) return(NA_character_)
  out <- tryCatch({
    if (requireNamespace("digest", quietly = TRUE)) {
      tolower(digest::digest(file = path, algo = "sha256"))
    } else if (exists("sha256sum", envir = asNamespace("tools"), inherits = FALSE)) {   # R >= 4.5
      tolower(unname(get("sha256sum", envir = asNamespace("tools"))(path)))
    } else if (.Platform$OS.type == "windows") {
      o <- system2("certutil", c("-hashfile", shQuote(path), "SHA256"), stdout = TRUE, stderr = TRUE)
      h <- gsub("[^0-9a-f]", "", tolower(o))
      h[nchar(h) == 64][1]
    } else {
      o <- system2("shasum", c("-a", "256", shQuote(path)), stdout = TRUE, stderr = TRUE)
      tolower(strsplit(o[1], "[[:space:]]+")[[1]][1])
    }
  }, error = function(e) NA_character_, warning = function(w) NA_character_)
  if (!is.character(out) || length(out) != 1L || is.na(out) || !grepl("^[0-9a-f]{64}$", out)) {
    return(NA_character_)
  }
  out
}

.sae_download_timeout <- function() {
  t <- suppressWarnings(as.numeric(Sys.getenv("EU_SAE_PANDOC_TIMEOUT", "600")))
  if (is.na(t) || t < 30) 600 else t
}

# One bounded attempt (a second method only on Windows, where libcurl may not see
# the system proxy that wininet does). Returns TRUE or a character reason.
.sae_download <- function(url, dest, quiet = FALSE) {
  old <- options(timeout = .sae_download_timeout()); on.exit(options(old), add = TRUE)
  methods <- if (.Platform$OS.type == "windows") c("libcurl", "wininet") else "libcurl"
  reasons <- character()
  for (m in methods) {
    res <- tryCatch({
      status <- utils::download.file(url, dest, mode = "wb", method = m, quiet = quiet)
      if (status != 0) paste0(m, ": download.file returned status ", status)
      else if (!file.exists(dest) || file.size(dest) < 1e6) paste0(m, ": file missing or truncated")
      else TRUE
    }, error = function(e) paste0(m, ": ", conditionMessage(e)),
       warning = function(w) paste0(m, ": ", conditionMessage(w)))
    if (isTRUE(res)) return(TRUE)
    reasons <- c(reasons, res)
    unlink(dest)
  }
  paste(reasons, collapse = " | ")
}

# Extract only the pandoc executable from the release archive into `dest_dir`.
.sae_extract_pandoc <- function(archive, dest_dir) {
  exe <- .sae_pandoc_exe_name()
  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  is_zip <- grepl("\\.zip$", archive, ignore.case = TRUE)
  entries <- if (is_zip) utils::unzip(archive, list = TRUE)$Name else utils::untar(archive, list = TRUE)
  wanted <- entries[basename(entries) == exe & !grepl("/$", entries)]
  if (!length(wanted)) stop("The Pandoc archive does not contain ", exe)
  wanted <- wanted[1]
  staging <- tempfile("pandoc-extract-"); dir.create(staging)
  on.exit(unlink(staging, recursive = TRUE), add = TRUE)
  if (is_zip) utils::unzip(archive, files = wanted, exdir = staging, junkpaths = TRUE)
  else utils::untar(archive, files = wanted, exdir = staging)
  extracted <- list.files(staging, pattern = paste0("^", gsub(".", "\\.", exe, fixed = TRUE), "$"),
                          recursive = TRUE, full.names = TRUE)[1]
  if (is.na(extracted)) stop("Could not extract ", exe, " from the Pandoc archive.")
  target <- file.path(dest_dir, exe)
  if (!file.copy(extracted, target, overwrite = TRUE)) stop("Could not place ", exe, " in ", dest_dir)
  if (.Platform$OS.type != "windows") Sys.chmod(target, "755")
  invisible(target)
}

# Download the pinned release for this platform into the per-user cache.
# Returns the folder containing the executable, or stops with a reason.
# Nothing is extracted unless the SHA-256 was computed and matches the pin.
sae_download_pandoc <- function(quiet = FALSE) {
  rel <- .sae_pandoc_release
  key <- sae_pandoc_platform()
  if (is.na(key) || is.null(rel$assets[[key]])) stop("No pinned Pandoc build for this platform (", key, ").")
  asset <- rel$assets[[key]]
  cache <- sae_pandoc_cache_dir()
  dest_dir <- file.path(cache, paste0(rel$version, "-", key))
  archive  <- file.path(cache, asset$file)
  dir.create(cache, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(archive), add = TRUE)   # never leave an archive behind, verified or not

  if (!identical(.sae_sha256(archive), asset$sha256)) {
    unlink(archive)
    if (!quiet) message("  Downloading Pandoc ", rel$version, " (", asset$file,
                        ", 26-42 MB, up to ", .sae_download_timeout(), " s) ...")
    res <- .sae_download(paste0(rel$base_url, asset$file), archive, quiet = quiet)
    if (!isTRUE(res)) stop("Download failed (", res, "). Check the internet connection or proxy, ",
                           "or install Pandoc from https://pandoc.org/installing.html")
  }
  got <- .sae_sha256(archive)
  if (is.na(got)) {
    stop("Could not compute the SHA-256 of ", asset$file, " on this system (digest package, ",
         "tools::sha256sum, certutil or shasum needed); the download was discarded, nothing was installed.")
  }
  if (!identical(got, asset$sha256)) {
    stop("Checksum mismatch for ", asset$file, " (expected ", asset$sha256, ", got ", got,
         "); the download was discarded, nothing was installed.")
  }
  .sae_extract_pandoc(archive, dest_dir)
  dest_dir
}

# ---- Main entry point ---------------------------------------------------

.sae_pandoc_result <- function(ok, dir = NULL, version = NULL, source = NA_character_, reason = NA_character_) {
  list(ok = isTRUE(ok), dir = dir, version = version, source = source, reason = reason)
}

# Find Pandoc, downloading it if allowed, necessary, and not already attempted
# in this R session. Always returns list(ok, dir, version, source, reason).
sae_ensure_pandoc <- function(root = getwd(), min_version = "2.8",
                              allow_download = !identical(Sys.getenv("EU_SAE_PANDOC_OFFLINE"), "1"),
                              quiet = FALSE) {
  say <- function(...) if (!quiet) message(...)
  found <- sae_find_pandoc(root, min_version)
  if (!is.null(found)) {
    say("  OK: Pandoc ", found$version, " at ", found$dir)
    return(.sae_pandoc_result(TRUE, found$dir, found$version, "existing"))
  }
  if (!allow_download) {
    reason <- "Pandoc not found and downloads are disabled (EU_SAE_PANDOC_OFFLINE=1)."
    say("  ", reason)
    return(.sae_pandoc_result(FALSE, reason = reason))
  }
  prior <- getOption("eu_sae.pandoc_download_failed", NULL)
  if (!is.null(prior)) {
    reason <- paste0("Pandoc download already failed earlier in this session and was not retried: ", prior)
    say("  ", reason)
    return(.sae_pandoc_result(FALSE, reason = reason))
  }
  say("  Pandoc not found on this computer; fetching a private copy for this user (one-time, no admin rights needed).")
  dl <- tryCatch(list(dir = sae_download_pandoc(quiet = quiet)),
                 error = function(e) list(error = conditionMessage(e)))
  if (!is.null(dl$error)) {
    reason <- paste0("Pandoc download failed: ", dl$error)
    options(eu_sae.pandoc_download_failed = dl$error)
    say("  ", reason)
    return(.sae_pandoc_result(FALSE, reason = reason))
  }
  dir <- dl$dir
  v <- sae_pandoc_version_at(dir)
  if (is.null(v) || v < numeric_version(min_version)) {
    reason <- paste0("Pandoc was downloaded to ", dir, " but could not be run",
                     if (identical(Sys.info()[["sysname"]], "Darwin"))
                       " (macOS or a device policy may have blocked it; see System Settings > Privacy & Security)"
                     else if (.Platform$OS.type == "windows")
                       " (an application-control policy may have blocked it)"
                     else "", ".")
    options(eu_sae.pandoc_download_failed = reason)
    say("  ", reason)
    return(.sae_pandoc_result(FALSE, reason = reason))
  }
  used <- .sae_use_pandoc_dir(dir, v)
  if (is.null(used)) {
    reason <- paste0("Pandoc ", v, " is at ", dir, " but rmarkdown did not accept that folder.")
    say("  ", reason)
    return(.sae_pandoc_result(FALSE, reason = reason))
  }
  say("  OK: Pandoc ", v, " installed for this user at ", dir)
  .sae_pandoc_result(TRUE, used$dir, used$version, "downloaded")
}

