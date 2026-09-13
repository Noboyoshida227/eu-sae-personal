# Exercise setup failure paths without installing packages or changing security.
args <- commandArgs(trailingOnly = TRUE)
installer <- if (length(args)) args[1] else "install_packages.R"
code <- paste(readLines(installer), collapse="\n")
code <- gsub("utils::packageVersion", "test_version", code, fixed=TRUE)
code <- gsub("utils::write.csv", "test_write", code, fixed=TRUE)
code <- gsub("rmarkdown::find_pandoc", "test_find", code, fixed=TRUE)
code <- gsub("pandoc::pandoc_installed_latest", "test_latest", code, fixed=TRUE)
code <- gsub("pandoc::pandoc_install", "test_install_pandoc", code, fixed=TRUE)
code <- gsub("pandoc::pandoc_bin", "test_bin", code, fixed=TRUE)
run_case <- function(mode) {
  e <- new.env(parent=globalenv())
  e$downloads <- character()
  e$pandoc_downloads <- 0L
  e$test_version <- function(pkg) {
    if (pkg == "arrow" && !"arrow" %in% e$downloads) stop("not installed")
    numeric_version("99.0.0")
  }
  e$install.packages <- function(pkgs, ...) {
    stopifnot(list(...)$type == "binary")
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
  e$test_find <- function(cache=FALSE, dir=NULL) {
    if (e$pandoc_downloads || mode == "existing") list(version=numeric_version("3.6"), dir=tempdir())
    else list(version=numeric_version("0"), dir=NULL)
  }
  e$test_latest <- function() if (e$pandoc_downloads) "3.6" else NULL
  e$test_bin <- function(...) file.path(tempdir(), "pandoc.exe")
  e$test_install_pandoc <- function(...) {
    if (mode == "pandoc_failure") stop("Pandoc download blocked")
    e$pandoc_downloads <- e$pandoc_downloads+1L
  }
  err <- tryCatch({eval(parse(text=code),e);NULL}, error=conditionMessage)
  expected_fail <- mode %in% c("download_failure","dll_block","pandoc_failure")
  stopifnot(!is.null(err) == expected_fail, "arrow" %in% e$downloads)
  if (expected_fail) stopifnot(grepl("Setup incomplete",err))
  if (mode == "existing") stopifnot(e$pandoc_downloads == 0L)
  if (mode == "missing") stopifnot(e$pandoc_downloads == 1L)
  cat("PASS:",mode,"\n")
}
for (mode in c("existing","missing","download_failure","dll_block","pandoc_failure")) run_case(mode)

