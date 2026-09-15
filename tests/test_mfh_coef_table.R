# ============================================================
# test_mfh_coef_table.R -- MFH coefficient table never stops the
# Comparison step, and the robust MFH2 refit labels its coefficients
#
# Background: with the Greek NUTS3 data the robust optim() refit of
# eblupMFH2 was used (msae returned refvar = 0).  Its estcoef matrix had
# no rownames, and 03_comparison.R built the coefficient table with
# data.frame(Term = rownames(.ec), ...), which failed with
# "arguments imply differing number of rows: 1, 0, 10" and marked the
# whole run as failed although every estimate had been written.
#
# Run from the package root:  Rscript tests/test_mfh_coef_table.R
# No network, no msae/magic needed.
# ============================================================

root <- normalizePath(if (file.exists("R/pipeline_helpers.R")) "." else "..",
                      winslash = "/", mustWork = TRUE)
source(file.path(root, "R", "pipeline_helpers.R"))
source(file.path(root, "scripts", "eblupMFH2_robust.R"))

checks <- 0L
ok <- function(cond, msg) {
  checks <<- checks + 1L
  if (!isTRUE(cond)) stop("FAILED: ", msg, call. = FALSE)
  cat("  ok -", msg, "\n")
}

years <- c(2022L, 2023L)
formulas <- list(poor_2022 = poor_2022 ~ x1 + x2,
                 poor_2023 = poor_2023 ~ x1)
cols <- c("beta", "std.error", "t.statistics", "p.value")
make_estcoef <- function(with_rownames = TRUE) {
  m <- matrix(c(0.10, 0.02, 5.0, 0.0001,
                0.20, 0.10, 2.0, 0.0455,
               -0.30, 0.25, -1.2, 0.2301,
                0.15, 0.03, 5.0, 0.0001,
                0.05, 0.04, 1.25, 0.2113),
              ncol = 4, byrow = TRUE, dimnames = list(NULL, cols))
  if (with_rownames) rownames(m) <- c("(Intercept)", "x1", "x2", "(Intercept)", "x1")
  m
}

cat("-- sae_mfh_coef_table() --\n")
tbl <- sae_mfh_coef_table(make_estcoef(TRUE), formulas, years, "MFH2")
ok(is.data.frame(tbl) && nrow(tbl) == 5L, "labelled matrix: five rows")
ok(identical(tbl$Term, c("(Intercept)", "x1", "x2", "(Intercept)", "x1")),
   "labelled matrix: rownames used as terms")
ok(identical(tbl$Year, c(2022L, 2022L, 2022L, 2023L, 2023L)),
   "year taken from the formula names")
ok(identical(tbl$Signif, c("***", "*", "", "***", "")), "significance stars")
ok(all(tbl$Method == "MFH2"), "method label")

tbl2 <- sae_mfh_coef_table(make_estcoef(FALSE), formulas, years, "MFH2")
ok(is.data.frame(tbl2) && nrow(tbl2) == 5L,
   "matrix WITHOUT rownames (robust refit) still produces a table")
ok(identical(tbl2$Term, c("(Intercept)", "x1", "x2", "(Intercept)", "x1")),
   "terms derived from the formulas when rownames are missing")
ok(identical(tbl2[, c("Estimate", "Std.Error", "z.value", "p.value")],
             tbl[, c("Estimate", "Std.Error", "z.value", "p.value")]),
   "numbers identical with and without rownames")

tbl3 <- sae_mfh_coef_table(make_estcoef(FALSE), unname(formulas), years, "MFH2")
ok(identical(tbl3$Year, c(2022L, 2022L, 2022L, 2023L, 2023L)),
   "unnamed formula list: year falls back to years_keep")

ok(is.null(sae_mfh_coef_table(make_estcoef(TRUE)[1:4, , drop = FALSE], formulas, years)),
   "row count that does not match the formulas returns NULL, no error")
ok(is.null(sae_mfh_coef_table(NULL, formulas, years)), "NULL estcoef returns NULL")
ok(is.null(sae_mfh_coef_table(as.data.frame(make_estcoef(TRUE)), formulas, years)),
   "non-matrix estcoef returns NULL")

# The previous inline code fails on the unlabelled matrix exactly as in the log.
old_way <- tryCatch({
  ec <- make_estcoef(FALSE)[1:3, , drop = FALSE]
  data.frame(Method = "MFH2", Year = 2022L, Term = rownames(ec), Estimate = ec[, "beta"])
  "no error"
}, error = function(e) conditionMessage(e))
ok(grepl("differing number of rows", old_way),
   "reference: the old inline data.frame() call reproduces George's error")

cat("-- .eblupMFH2_finalize() labels the coefficient rows --\n")
set.seed(1)
n <- 12L; r <- 2L
x1 <- rnorm(n); x2 <- rnorm(n)
X1 <- cbind("(Intercept)" = 1, x1 = x1, x2 = x2)
X2 <- cbind("(Intercept)" = 1, x1 = x1)
x.matrix <- rbind(cbind(X1, matrix(0, n, ncol(X2))),
                  cbind(matrix(0, n, ncol(X1)), X2))
colnames(x.matrix) <- c(colnames(X1), colnames(X2))
y.matrix <- c(0.2 + 0.1 * x1 - 0.05 * x2 + rnorm(n, sd = 0.03),
              0.25 + 0.12 * x1 + rnorm(n, sd = 0.03))
vardir <- data.frame(v1 = runif(n, 0.001, 0.003),
                     v2 = runif(n, 0.001, 0.003),
                     v12 = runif(n, 0.0002, 0.0005))
R <- .df2matR_local(vardir, r)
fit <- .eblupMFH2_finalize(sigma2_u = 0.002, rho_u = 0.4,
                           y.matrix = y.matrix, x.matrix = x.matrix, R = R,
                           r = r, n = n, y.var = c("poor_2022", "poor_2023"),
                           convergence = TRUE, iterations = 10L)
ec <- fit$fit$estcoef
ok(is.matrix(ec) && nrow(ec) == 5L, "finalize returns a 5-row estcoef matrix")
ok(identical(rownames(ec), c("(Intercept)", "x1", "x2", "(Intercept)", "x1")),
   "estcoef rows carry the design-matrix column names (like msae)")
ok(identical(colnames(ec), cols), "estcoef columns unchanged")
tbl4 <- sae_mfh_coef_table(ec, formulas, years, "MFH2")
ok(is.data.frame(tbl4) && identical(tbl4$Term, rownames(ec)),
   "comparison table built from the robust fit")

cat(sprintf("All %d MFH coefficient-table checks passed.\n", checks))
