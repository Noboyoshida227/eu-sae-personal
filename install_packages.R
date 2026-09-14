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

# --- 2. Pandoc (needed only to render the final HTML/Word report) -------
# R/pandoc_bootstrap.R finds an existing Pandoc (RStudio/Quarto bundles, PATH,
# Homebrew, pandoc.org installer, an earlier download) or downloads one pinned,
# SHA-256-verified release into the user's R cache folder. Base R only: no
# `pandoc`/`gh`/`rlang` version interplay, no admin rights, bounded timeout,
# at most one download attempt per session.
cat("\n[2/3] Checking Pandoc (report rendering)...\n")
pandoc_error <- tryCatch({
  source(file.path("R", "pandoc_bootstrap.R"), local = TRUE)
  res <- sae_ensure_pandoc(root = getwd(), min_version = "2.8")
  if (isTRUE(res$ok)) NULL else if (is.character(res$reason)) res$reason else "Pandoc is not available."
}, error = function(e) conditionMessage(e))
if (!is.null(pandoc_error)) {
  cat("  Pandoc setup failed:", pandoc_error, "\n")
  cat("  This does not prevent startup if the R-package checks below pass.\n")
  cat("  Analysis can run; the run will finish as 'Analysis completed - report\n")
  cat("  unavailable' and outputs/final_report.html/.docx will not be produced.\n")
  cat("  To fix: connect to the internet and run the launcher again (the app\n")
  cat("  downloads its own copy), or install Pandoc from https://pandoc.org/installing.html\n")
  cat("  (Windows: .msi installer; macOS: .pkg installer) and run the launcher again.\n")
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
  if (!is.null(pandoc_error)) cat("  NOTE: Pandoc is not available; the final report will be skipped until it is.\n")
  cat("  Package versions recorded locally in ", local_version_report, ".\n", sep = "")
  cat("  This local report is for troubleshooting only and is ignored by Git.\n")
  cat("  You can now run the app with:  shiny::runApp('app.R')\n\n")
} else {
  cat("\n  WARNING: The following packages could not be loaded:\n")
  cat("    ", paste(failed, collapse = ", "), "\n")
  stop("Setup incomplete. Dashboard was not started. See startup_setup.log (or this console). Resolve download, installation or loading errors and run the launcher again.", call. = FALSE)
}
