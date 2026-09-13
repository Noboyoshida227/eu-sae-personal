# ============================================================
# install_packages.R
# Run this script ONCE before launching app.R to ensure all
# required R packages are installed.
#
# Usage:  source("install_packages.R")
#    or:  Rscript install_packages.R
# ============================================================

cat("=== EU SAE Shiny App - Package Installer ===\n\n")
options(timeout = max(600, getOption("timeout", 60)))
cat("R:", R.version.string, "\n")

.user_lib <- Sys.getenv("R_LIBS_USER", unset = "")
if (nzchar(.user_lib)) {
  dir.create(.user_lib, recursive = TRUE, showWarnings = FALSE)
  .libPaths(unique(c(.user_lib, .libPaths())))
}

cat("R libraries:", paste(.libPaths(), collapse = "; "), "\n")

# --- R version check ----------------------------------------
# Current CRAN dependencies used by the pipeline (notably emdi)
# require R 4.2.0 or later.
.min_r_version <- "4.2.0"
if (getRversion() < .min_r_version) {
  stop(sprintf(
    "R >= %s is required (you have %s). Please update R from https://cran.r-project.org/",
    .min_r_version,
    getRversion()
  ), call. = FALSE)
}

# --- Helper: install if missing or below a minimum version ---
local_version_report <- "package_versions.local.csv"

installed_package_version <- function(pkg) {
  tryCatch(
    as.character(utils::packageVersion(pkg)),
    error = function(e) NA_character_
  )
}

install_if_missing_or_old <- function(pkg, min_version = NA_character_,
                                      repos = "https://cloud.r-project.org") {
  current_version <- installed_package_version(pkg)
  installed <- !is.na(current_version)
  has_min <- is.character(min_version) && length(min_version) == 1 &&
    !is.na(min_version) && nzchar(min_version)

  too_old <- FALSE
  if (installed) {
    too_old <- has_min && utils::compareVersion(current_version, min_version) < 0
  }

  if (!installed) {
    cat("  Installing:", pkg, "\n")
    install.packages(pkg, repos = repos, lib = .libPaths()[1], quiet = FALSE,
                     type = if (.Platform$OS.type == "windows") "binary" else getOption("pkgType"))
  } else if (too_old) {
    cat("  Updating:", pkg, "(installed", current_version,
        "< required", min_version, ")\n")
    install.packages(pkg, repos = repos, lib = .libPaths()[1], quiet = FALSE,
                     type = if (.Platform$OS.type == "windows") "binary" else getOption("pkgType"))
  } else if (has_min) {
    cat("  OK:", pkg, current_version, "(minimum", min_version, ")\n")
  } else {
    cat("  OK:", pkg, current_version, "\n")
  }
}

# --- 1. CRAN packages --------------------------------------
cat("[1/3] Checking CRAN packages...\n")

cran_packages <- c(
  # Shiny app
  "shiny",

  # Data manipulation
  "data.table", "dplyr", "tidyr", "purrr", "stringr",
  "tibble", "rlang", "tidyverse", "reshape2", "haven", "arrow",

  # Small area estimation
  "sae", "msae", "emdi",

  # Survey design
  "survey",


  # Spatial
  "sf", "spdep",

  # Visualisation
  "ggplot2", "patchwork", "viridis", "scales",

  # Tables and reporting
  "gt", "knitr", "rmarkdown", "openxlsx", "writexl", "readxl", "xml2", "zip",

  # Statistical / matrix
  "MASS", "Matrix", "matrixcalc", "moments", "magic", "car", "caret", "glmnet",

  # API / web
  "httr", "jsonlite", "base64enc",

  # Utilities
  "yaml", "here", "tictoc", "conflicted", "pacman", "pins", "digest", "tools"
)

minimum_versions <- c(
  shiny = "1.7.0",
  data.table = "1.14.0",
  dplyr = "1.0.0",
  tidyr = "1.2.0",
  purrr = "1.0.0",
  stringr = "1.5.0",
  tibble = "3.1.0",
  rlang = "1.1.0",
  haven = "2.5.0",
  arrow = "12.0.0",
  sae = "1.3",
  msae = "0.1.5",
  emdi = "2.0.0",
  survey = "4.2",
  sf = "1.0.0",
  spdep = "1.2.0",
  ggplot2 = "3.4.0",
  patchwork = "1.1.0",
  viridis = "0.6.0",
  scales = "1.2.0",
  gt = "0.9.0",
  knitr = "1.40",
  rmarkdown = "2.20",
  openxlsx = "4.2.5",
  writexl = "1.4.0",
  readxl = "1.4.0",
  Matrix = "1.5.0",
  glmnet = "4.1.0",
  httr = "1.4.0",
  jsonlite = "1.8.0",
  yaml = "2.3.0",
  here = "1.0.1"
)

for (pkg in cran_packages) {
  min_version <- if (pkg %in% names(minimum_versions)) {
    minimum_versions[[pkg]]
  } else {
    NA_character_
  }
  tryCatch(install_if_missing_or_old(pkg, min_version), error = function(e) {
    cat("  Installation error for", pkg, ":", conditionMessage(e), "\n")
  })
}

# Pandoc is a separate executable, not just an R package.
ensure_report_pandoc <- function() {
  use_dir <- function(path) {
    if (!length(path) || is.na(path) || !nzchar(path)) return(FALSE)
    exe <- file.path(path, if (.Platform$OS.type == "windows") "pandoc.exe" else "pandoc")
    if (!file.exists(exe)) return(FALSE)
    info <- tryCatch(rmarkdown::find_pandoc(cache = FALSE, dir = path),
                     error = function(e) NULL)
    if (is.null(info) || info$version < numeric_version("2.8")) return(FALSE)
    Sys.setenv(RSTUDIO_PANDOC = path)
    rmarkdown::find_pandoc(cache = FALSE)
    cat("  OK: Pandoc", as.character(info$version), "at", path, "\n")
    TRUE
  }
  current <- rmarkdown::find_pandoc(cache = FALSE)
  if (current$version >= numeric_version("2.8") && use_dir(current$dir)) return(invisible(TRUE))
  candidates <- c(
    file.path(Sys.getenv("ProgramFiles"), "RStudio/resources/app/bin/quarto/bin/tools"),
    file.path(Sys.getenv("ProgramFiles"), "RStudio/bin/pandoc"),
    file.path(Sys.getenv("LOCALAPPDATA"), "Programs/RStudio/resources/app/bin/quarto/bin/tools"),
    file.path(Sys.getenv("LOCALAPPDATA"), "Pandoc"),
    file.path(Sys.getenv("ProgramFiles"), "Pandoc"),
    file.path(Sys.getenv("ProgramFiles"), "Quarto/bin/tools"),
    "/Applications/RStudio.app/Contents/Resources/app/bin/quarto/bin/tools",
    "/usr/lib/rstudio/resources/app/bin/quarto/bin/tools",
    # macOS / Linux: pandoc.org .pkg installer, Homebrew, MacPorts, ~/opt/pandoc.
    # A double-clicked .command has a minimal PATH, so look here explicitly.
    "/usr/local/bin", "/opt/homebrew/bin", "/opt/local/bin", "/opt/pandoc",
    path.expand("~/opt/pandoc"), "/usr/bin")
  for (path in candidates) if (use_dir(path)) return(invisible(TRUE))
  # The CRAN pandoc package manages official Pandoc binaries in user storage.
  if (!requireNamespace("pandoc", quietly = TRUE)) {
    install.packages("pandoc", repos = "https://cloud.r-project.org",
                     lib = .libPaths()[1], quiet = FALSE,
                     type = if (.Platform$OS.type == "windows") "binary" else getOption("pkgType"))
  }
  if (!requireNamespace("pandoc", quietly = TRUE)) stop("Could not install the Pandoc installer R package.")
  installed <- pandoc::pandoc_installed_latest()
  if (length(installed) && !is.na(installed)) {
    path <- dirname(pandoc::pandoc_bin(installed))
    if (use_dir(path)) return(invisible(TRUE))
  }
  cat("  Installing official Pandoc binary for the current user...\n")
  pandoc::pandoc_install()
  path <- dirname(pandoc::pandoc_bin(pandoc::pandoc_installed_latest()))
  if (!use_dir(path)) stop("Pandoc was downloaded but could not be run, or is older than 2.8.")
  invisible(TRUE)
}

cat("\n[2/3] Checking Pandoc (needed only for report export)...\n")
pandoc_error <- tryCatch({ensure_report_pandoc(); NULL}, error = function(e) conditionMessage(e))
if (!is.null(pandoc_error)) {
  cat("  Pandoc setup failed:", pandoc_error, "\n")
  cat("  This does not prevent startup if the R-package checks below pass.\n")
  cat("  Analysis can run, but final Word/HTML reports cannot be generated without Pandoc.\n")
  cat("  A run that attempts report generation may still be marked failed at that stage.\n")
  cat("  Install Pandoc from https://pandoc.org/installing.html and restart the launcher.\n")
  cat("  Windows: use the .msi installer. macOS: use the .pkg installer.\n")
}

# --- 3. Verify all packages load ---------------------------
cat("\n[3/3] Verifying all packages can be loaded...\n")

failed <- character()
for (pkg in cran_packages) {
  issue <- tryCatch({
    loadNamespace(pkg)
    if (pkg %in% names(minimum_versions) &&
        utils::packageVersion(pkg) < numeric_version(minimum_versions[[pkg]])) {
      stop("Installed version is below the required minimum.")
    }
    NULL
  }, error = function(e) conditionMessage(e))
  if (!is.null(issue)) {
    failed <- c(failed, pkg)
    cat("  Cannot use", pkg, ":", issue, "\n")
  }
}

if (length(failed) == 0) {
  package_versions <- data.frame(
    package = cran_packages,
    version = vapply(cran_packages, function(pkg) {
      as.character(utils::packageVersion(pkg))
    }, character(1)),
    required_minimum = vapply(cran_packages, function(pkg) {
      if (pkg %in% names(minimum_versions)) minimum_versions[[pkg]] else NA_character_
    }, character(1)),
    stringsAsFactors = FALSE
  )
  utils::write.csv(package_versions, local_version_report, row.names = FALSE)
  cat("\n  All packages installed successfully.\n")
  if (!is.null(pandoc_error)) cat("  NOTE: Pandoc setup is incomplete; final report generation requires Pandoc.\n")
  cat("  Package versions recorded locally in ", local_version_report, ".\n", sep = "")
  cat("  This local report is for troubleshooting only and is ignored by Git.\n")
  cat("  You can now run the app with:  shiny::runApp('app.R')\n\n")
} else {
  cat("\n  WARNING: The following packages could not be loaded:\n")
  cat("    ", paste(failed, collapse = ", "), "\n")
  stop("Setup incomplete. Dashboard was not started. See startup_setup.log (or this console). Resolve download, installation or loading errors and run the launcher again.", call. = FALSE)
}
