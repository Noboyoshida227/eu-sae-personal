# Unit tests for R/pandoc_bootstrap.R. No network, no real Pandoc download.
# Run from the package root:  Rscript tests/test_pandoc_bootstrap.R
#
# Every network/hash/extract primitive is replaced by a stub inside a private
# environment, so the tests exercise the decision logic only:
#   - explicit EU_SAE_PANDOC and package-local tools/pandoc win over PATH
#   - offline mode never downloads
#   - an uncomputable checksum blocks extraction
#   - a mismatching checksum blocks extraction
#   - a failed download reports a structured reason and is not retried in-session
#   - a cached copy is reused without downloading
#   - a successful download is extracted, verified and reported as "downloaded"
#   - rmarkdown (when installed) is pinned to the selected folder

env <- new.env(parent = globalenv())
sys.source("R/pandoc_bootstrap.R", envir = env)

passed <- 0L
check <- function(ok, label) {
  if (!isTRUE(ok)) stop("FAIL: ", label, call. = FALSE)
  passed <<- passed + 1L
  cat("PASS:", label, "\n")
}

exe_name <- env$.sae_pandoc_exe_name()
sandbox <- tempfile("pandoc-bootstrap-test-"); dir.create(sandbox)
root <- file.path(sandbox, "pkg"); dir.create(root)
cache <- file.path(sandbox, "cache"); dir.create(cache)
Sys.setenv(EU_SAE_PANDOC = "", EU_SAE_PANDOC_OFFLINE = "", RSTUDIO_PANDOC = "")
options(eu_sae.pandoc_download_failed = NULL)

# --- stubs -----------------------------------------------------------------
# A "pandoc folder" is any folder containing a file named like the executable
# whose first line holds the version number the stub should report.
make_pandoc <- function(dir, version) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  writeLines(version, file.path(dir, exe_name))
  invisible(normalizePath(dir, winslash = "/"))
}
env$sae_pandoc_version_at <- function(dir) {
  f <- file.path(dir, exe_name)
  # Only the tiny stub files created by make_pandoc() count; a real Pandoc that
  # happens to be on this machine's PATH is ignored so results are deterministic.
  if (!file.exists(f) || is.na(file.size(f)) || file.size(f) > 64) return(NULL)
  v <- tryCatch(readLines(f, n = 1L, warn = FALSE), error = function(e) "")
  if (!length(v) || !nzchar(v)) return(NULL)   # "installed but cannot run"
  tryCatch(numeric_version(v), error = function(e) NULL)
}
env$sae_pandoc_cache_dir <- function() cache
env$sae_pandoc_platform <- function() "windows-x86_64"   # any pinned key
# rmarkdown pinning: simulate find_pandoc(dir=) agreeing with the folder.
env$.sae_use_pandoc_dir <- function(dir, version) list(dir = normalizePath(dir, winslash = "/"), version = version)

state <- new.env()
reset <- function(download = TRUE, hash = "match", extract_ok = TRUE) {
  state$downloads <- 0L; state$extracted <- 0L
  state$download <- download; state$hash <- hash; state$extract_ok <- extract_ok
  options(eu_sae.pandoc_download_failed = NULL)
  unlink(list.files(cache, full.names = TRUE, all.files = TRUE, no.. = TRUE), recursive = TRUE)
}
pin <- env$.sae_pandoc_release$assets[["windows-x86_64"]]$sha256
env$.sae_download <- function(url, dest, quiet = FALSE) {
  state$downloads <- state$downloads + 1L
  if (!isTRUE(state$download)) return("libcurl: simulated proxy refusal (403)")
  writeLines("archive", dest); TRUE
}
env$.sae_sha256 <- function(path) {
  if (!file.exists(path)) return(NA_character_)
  switch(state$hash, match = pin, mismatch = strrep("0", 64), NA_character_)
}
env$.sae_extract_pandoc <- function(archive, dest_dir) {
  state$extracted <- state$extracted + 1L
  if (!isTRUE(state$extract_ok)) stop("simulated extraction failure")
  make_pandoc(dest_dir, "3.11"); invisible(file.path(dest_dir, exe_name))
}

# --- 1. explicit override wins ---------------------------------------------
reset()
override <- make_pandoc(file.path(sandbox, "override"), "3.6")
Sys.setenv(EU_SAE_PANDOC = override)
res <- env$sae_ensure_pandoc(root = root, quiet = TRUE)
check(isTRUE(res$ok) && identical(res$dir, override) && res$source == "existing" && state$downloads == 0L,
      "EU_SAE_PANDOC override is used, nothing downloaded")
Sys.setenv(EU_SAE_PANDOC = "")

# --- 2. package-local tools/pandoc wins over the cache ----------------------
reset()
local_dir <- make_pandoc(file.path(root, "tools", "pandoc"), "3.6")
make_pandoc(file.path(cache, "3.11-windows-x86_64"), "3.11")
res <- env$sae_ensure_pandoc(root = root, quiet = TRUE)
check(isTRUE(res$ok) && identical(res$dir, local_dir), "package-local tools/pandoc is preferred over the cache")
unlink(file.path(root, "tools"), recursive = TRUE)

# --- 3. too-old copies are skipped -----------------------------------------
reset()
make_pandoc(file.path(root, "tools", "pandoc"), "2.7")
res <- env$sae_find_pandoc(root = root, min_version = "2.8")
check(is.null(res), "a Pandoc below the minimum version is ignored")
unlink(file.path(root, "tools"), recursive = TRUE)

# --- 4. cached copy reused without download --------------------------------
reset()
cached <- make_pandoc(file.path(cache, "3.11-windows-x86_64"), "3.11")
res <- env$sae_ensure_pandoc(root = root, quiet = TRUE)
check(isTRUE(res$ok) && identical(res$dir, cached) && state$downloads == 0L, "cached download is reused")

# --- 5. offline: never downloads, structured reason ------------------------
reset()
res <- env$sae_ensure_pandoc(root = root, allow_download = FALSE, quiet = TRUE)
check(!res$ok && state$downloads == 0L && grepl("disabled", res$reason), "offline mode returns a reason without downloading")
Sys.setenv(EU_SAE_PANDOC_OFFLINE = "1")
res <- env$sae_ensure_pandoc(root = root, quiet = TRUE)
check(!res$ok && state$downloads == 0L, "EU_SAE_PANDOC_OFFLINE=1 is honoured")
Sys.setenv(EU_SAE_PANDOC_OFFLINE = "")

# --- 6. successful download -------------------------------------------------
reset()
res <- env$sae_ensure_pandoc(root = root, quiet = TRUE)
check(isTRUE(res$ok) && res$source == "downloaded" && state$downloads == 1L && state$extracted == 1L &&
        as.character(res$version) == "3.11" && !file.exists(file.path(cache, "pandoc-3.11-windows-x86_64.zip")),
      "download + checksum + extraction succeeds and the archive is removed")

# --- 7. uncomputable checksum blocks extraction ----------------------------
reset(hash = "na")
res <- env$sae_ensure_pandoc(root = root, quiet = TRUE)
check(!res$ok && state$extracted == 0L && grepl("SHA-256", res$reason) && !file.exists(file.path(cache, "pandoc-3.11-windows-x86_64.zip")),
      "unavailable checksum: nothing extracted, archive discarded, reason given")

# --- 8. mismatching checksum blocks extraction -----------------------------
reset(hash = "mismatch")
res <- env$sae_ensure_pandoc(root = root, quiet = TRUE)
check(!res$ok && state$extracted == 0L && grepl("mismatch", res$reason), "checksum mismatch: nothing extracted")

# --- 9. download failure: reason kept, not retried in the same session ------
reset(download = FALSE)
res <- env$sae_ensure_pandoc(root = root, quiet = TRUE)
check(!res$ok && grepl("403", res$reason) && state$downloads == 1L, "download failure carries the underlying error")
res2 <- env$sae_ensure_pandoc(root = root, quiet = TRUE)
check(!res2$ok && state$downloads == 1L && grepl("not retried", res2$reason), "a failed download is not repeated in the same session")
make_pandoc(file.path(cache, "3.11-windows-x86_64"), "3.11")
res3 <- env$sae_ensure_pandoc(root = root, quiet = TRUE)
check(isTRUE(res3$ok) && state$downloads == 1L, "but an existing copy is still picked up afterwards")

# --- 10. extraction failure -------------------------------------------------
reset(extract_ok = FALSE)
res <- env$sae_ensure_pandoc(root = root, quiet = TRUE)
check(!res$ok && grepl("extraction", res$reason), "extraction failure is reported")

# --- 11. downloaded but cannot run -----------------------------------------
reset()
env$.sae_extract_pandoc <- function(archive, dest_dir) { dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE); writeLines("", file.path(dest_dir, exe_name)) }
res <- env$sae_ensure_pandoc(root = root, quiet = TRUE)
check(!res$ok && grepl("could not be run", res$reason), "an executable that cannot run is reported, not used")

# --- 12. real helpers: platform key, timeout bound, checksum of a known file --
key <- (function() { e2 <- new.env(); sys.source("R/pandoc_bootstrap.R", envir = e2); e2$sae_pandoc_platform() })()
check(key %in% names(env$.sae_pandoc_release$assets), paste("platform key is pinned:", key))
Sys.setenv(EU_SAE_PANDOC_TIMEOUT = "5")
check(env$.sae_download_timeout() == 600, "timeout below 30 s falls back to 600 s")
Sys.setenv(EU_SAE_PANDOC_TIMEOUT = "900")
check(env$.sae_download_timeout() == 900, "EU_SAE_PANDOC_TIMEOUT is honoured")
Sys.setenv(EU_SAE_PANDOC_TIMEOUT = "")
e3 <- new.env(); sys.source("R/pandoc_bootstrap.R", envir = e3)
tf <- tempfile(); writeLines("abc", tf, sep = "")
h <- e3$.sae_sha256(tf)
check(identical(h, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") || is.na(h),
      if (is.na(h)) "real SHA-256 helper unavailable here (returns NA, which blocks installs)" else "real SHA-256 helper matches the known digest of 'abc'")
check(is.na(e3$.sae_sha256(file.path(sandbox, "missing"))), "SHA-256 of a missing file is NA")

# --- 13. rmarkdown pinning (only when rmarkdown and a real Pandoc exist) -----
if (requireNamespace("rmarkdown", quietly = TRUE) && rmarkdown::pandoc_available()) {
  real_dir <- rmarkdown::find_pandoc()$dir
  real_ver <- e3$sae_pandoc_version_at(real_dir)
  used <- e3$.sae_use_pandoc_dir(real_dir, real_ver)
  check(!is.null(used) && identical(normalizePath(rmarkdown::find_pandoc()$dir, winslash = "/"), used$dir),
        "rmarkdown is pinned to the folder selected by the helper")
  bogus <- e3$.sae_use_pandoc_dir(file.path(sandbox, "nowhere"), numeric_version("9.9"))
  check(is.null(bogus), "a folder rmarkdown cannot use is rejected")
} else {
  cat("SKIP: rmarkdown pinning check (rmarkdown or Pandoc not installed here)\n")
}

# --- 14. render_final_report() reports a skipped report instead of failing --
# Only the two report functions are lifted out of app_support.R (the rest of
# that file needs the full app stack); rendering is stubbed.
support <- paste(readLines("app_support.R", warn = FALSE, encoding = "UTF-8"), collapse = "\n")
support <- gsub("rmarkdown::render(", "test_render(", support, fixed = TRUE)
support <- gsub("sae_render_word_report()", "test_word()", support, fixed = TRUE)
exprs <- parse(text = support, keep.source = FALSE)
wanted <- c("sae_report_result", "render_final_report")
renv <- new.env(parent = globalenv())
for (ex in exprs) {
  if (is.call(ex) && identical(ex[[1]], as.name("<-")) && as.character(ex[[2]]) %in% wanted) eval(ex, renv)
}
check(all(vapply(wanted, exists, logical(1), envir = renv, inherits = FALSE)), "report functions extracted from app_support.R")

work <- file.path(sandbox, "work"); dir.create(file.path(work, "outputs"), recursive = TRUE)
old_wd <- setwd(work); on.exit(setwd(old_wd), add = TRUE)
writeLines("---\ntitle: t\n---\n", "report.Rmd")
events <- character(); logs <- character()
cb <- function(event, label) events <<- c(events, paste(event, label))
lg <- function(msg) logs <<- c(logs, msg)
renv$test_render <- function(input, output_file, ...) { writeLines("<html></html>", output_file); invisible(output_file) }
renv$test_word   <- function(...) { writeLines("docx", file.path("outputs", "final_report.docx")); invisible(TRUE) }

renv$sae_ensure_pandoc <- function(...) list(ok = FALSE, dir = NULL, version = NULL, source = NA, reason = "Pandoc download failed: libcurl: proxy refused (403)")
r <- renv$render_final_report(logger = lg, progress_callback = cb)
check(identical(r$status, "unavailable") && !r$rendered && grepl("403", r$reason), "missing Pandoc -> status 'unavailable' with the underlying reason")
check(identical(events, c("start Report", "skipped Report")), "progress reports the report step as skipped, not complete")
check(any(grepl("Report not rendered", logs)) && !any(grepl("Excel", logs)), "log explains the skip without claiming which outputs exist")
check(!file.exists("outputs/final_report.html"), "no report file is produced when Pandoc is missing")

events <- character(); logs <- character()
renv$sae_ensure_pandoc <- function(...) list(ok = TRUE, dir = "/x", version = numeric_version("3.11"), source = "existing", reason = NA)
r <- renv$render_final_report(logger = lg, progress_callback = cb)
check(identical(r$status, "rendered") && r$rendered && !is.null(r$html) && !is.null(r$docx), "available Pandoc -> status 'rendered' with html and docx paths")
check(identical(events, c("start Report", "complete Report")), "progress reports the report step as complete")
setwd(old_wd)

unlink(sandbox, recursive = TRUE)
cat(sprintf("\nAll %d pandoc_bootstrap checks passed.\n", passed))
