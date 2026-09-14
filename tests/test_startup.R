# Exercise setup failure paths without installing packages or changing security.
args <- commandArgs(trailingOnly = TRUE)
installer <- if (length(args)) args[1] else "install_packages.R"
code <- paste(readLines(installer), collapse="\n")
code <- gsub("utils::packageVersion", "test_version", code, fixed=TRUE)
code <- gsub("utils::write.csv", "test_write", code, fixed=TRUE)
# Pandoc is handled by R/pandoc_bootstrap.R; replace its loader and entry point.
code <- gsub('source(file.path("R", "pandoc_bootstrap.R"), local = TRUE)', "invisible(NULL)", code, fixed=TRUE)
code <- gsub("sae_ensure_pandoc(", "test_ensure_pandoc(", code, fixed=TRUE)
stopifnot(grepl("test_ensure_pandoc(", code, fixed=TRUE))
run_case <- function(mode) {
  e <- new.env(parent=globalenv())
  e$downloads <- character()
  e$pandoc_downloads <- 0L
  e$test_version <- function(pkg) {
    if (pkg == "arrow" && !"arrow" %in% e$downloads) stop("not installed")
    numeric_version("99.0.0")
  }
  e$install.packages <- function(pkgs, ...) {
    expected_type <- if (.Platform$OS.type == "windows") "binary" else getOption("pkgType")
    stopifnot(list(...)$type == expected_type)
    e$downloads <- c(e$downloads, pkgs)
    if (mode == "download_failure" && pkgs == "arrow") stop("Network download failed")
  }
  e$loadNamespace <- function(pkg, ...) {
    if (pkg == "arrow" && mode %in% c("download_failure", "dll_block"))
      stop(if (mode == "dll_block") "Application Control blocked arrow.dll" else "arrow missing")
    TRUE
  }
  e$requireNamespace <- function(...) TRUE
  e$test_write <- function(...) invisible(NULL)
  e$file.exists <- function(...) TRUE
  e$pandoc_calls <- 0L
  e$test_ensure_pandoc <- function(root = getwd(), min_version = "2.8", ...) {
    e$pandoc_calls <- e$pandoc_calls + 1L
    stopifnot(identical(min_version, "2.8"))
    found <- function(dir, source) list(ok=TRUE, dir=dir, version=numeric_version("3.6"), source=source, reason=NA_character_)
    if (mode == "existing")      return(found(tempdir(), "existing"))
    if (mode == "mac_pkg")       return(found("/usr/local/bin", "existing"))
    if (mode == "mac_homebrew")  return(found("/opt/homebrew/bin", "existing"))
    if (mode == "missing") { e$pandoc_downloads <- e$pandoc_downloads+1L; return(found(file.path(tempdir(), "3.11"), "downloaded")) }
    if (mode == "pandoc_failure") return(list(ok=FALSE, dir=NULL, version=NULL, source=NA_character_, reason="Pandoc download failed: libcurl: proxy refused (403)"))
    if (mode == "pandoc_offline") return(list(ok=FALSE, dir=NULL, version=NULL, source=NA_character_, reason="Pandoc not found and downloads are disabled (EU_SAE_PANDOC_OFFLINE=1)."))
    if (mode == "missing_helper") stop("could not find function \"sae_ensure_pandoc\"")
    found(tempdir(), "existing")
  }
  err <- tryCatch({eval(parse(text=code),e);NULL}, error=conditionMessage)
  expected_fail <- mode %in% c("download_failure","dll_block")
  stopifnot(!is.null(err) == expected_fail, "arrow" %in% e$downloads)
  if (expected_fail) stopifnot(grepl("Setup incomplete",err))
  stopifnot(e$pandoc_calls == 1L)                      # exactly one Pandoc check per setup
  if (mode == "existing") stopifnot(e$pandoc_downloads == 0L, is.null(e$pandoc_error))
  if (mode %in% c("mac_pkg", "mac_homebrew")) stopifnot(e$pandoc_downloads == 0L, is.null(e$pandoc_error))
  if (mode %in% c("pandoc_failure", "pandoc_offline", "missing_helper")) {
    stopifnot(!is.null(e$pandoc_error))                # reported ...
    stopifnot(is.null(err))                            # ... but never fatal
  }
  if (mode == "pandoc_failure") stopifnot(grepl("403", e$pandoc_error))   # underlying reason kept
  if (mode == "missing") stopifnot(e$pandoc_downloads == 1L, is.null(e$pandoc_error))
  cat("PASS:",mode,"\n")
}
for (mode in c("existing","missing","download_failure","dll_block","pandoc_failure",
               "pandoc_offline","missing_helper","mac_pkg","mac_homebrew")) run_case(mode)

