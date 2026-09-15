# Regression test for .pipeline_run_step() in app_support.R.
# Run from the package root:  Rscript tests/test_step_runner.R
#
# A step's R child can finish all its work and still exit non-zero while R
# shuts down (DLL unload / finalizer / device close on some Windows machines;
# observed as "Step 'UFH' failed with exit status 255" with no R error in the
# child log). The runner must distinguish that from a real script failure.

src <- paste(readLines("app_support.R", warn = FALSE, encoding = "UTF-8"), collapse = "\n")
ex <- parse(text = src, keep.source = FALSE)
want <- c("%||%", ".pipeline_step_timeout", ".pipeline_write_child_output",
          ".pipeline_success_summary", ".pipeline_warning_summary",
          ".pipeline_failure_excerpt", ".pipeline_log_child_summary",
          ".pipeline_run_step", ".pipeline_step_sentinel")
for (e in ex) {
  if (is.call(e) && identical(e[[1]], as.name("<-")) && as.character(e[[2]]) %in% want) eval(e)
}
stopifnot(all(vapply(want, exists, logical(1))))

passed <- 0L
check <- function(ok, label) {
  if (!isTRUE(ok)) stop("FAIL: ", label, call. = FALSE)
  passed <<- passed + 1L
  cat("PASS:", label, "\n")
}

work <- tempfile("step-runner-"); dir.create(work)
old_wd <- setwd(work); on.exit(setwd(old_wd), add = TRUE)
logs <- character()
lg <- function(m) logs <<- c(logs, m)
run <- function(step, body) {
  f <- tempfile(fileext = ".R"); writeLines(body, f)
  logs <<- character()
  .pipeline_run_step(step, f, "cfg.yml", logger = lg)
}

r <- run("UFH", 'cat("Results saved to:\\n")')
check(r$status == 0L && r$exit_status == 0L && isTRUE(r$completed), "normal completion -> status 0")

r <- run("UFH", c('cat("Results saved to:\\n")',
                  'reg.finalizer(globalenv(), function(e) quit(save = "no", status = 255), onexit = TRUE)'))
check(r$status == 0L && r$exit_status == 255L && isTRUE(r$completed),
      "finished, then exit status 255 at shutdown -> treated as success, exit status kept")
check(any(grepl("exited with status 255 while shutting down", logs)),
      "shutdown failure is reported as a warning in the run log")
check(file.exists(file.path("outputs", "logs", "ufh_child_output.log")), "child log is still written")

r <- run("MFH", c('cat("partial\\n")', 'stop("boom")'))
check(r$status == 1L && !isTRUE(r$completed), "a real error -> non-zero status, not completed")
check(any(grepl("Error", logs)), "the error text is surfaced in the run log")

r <- run("Comparison", 'quit(save = "no", status = 3)')
check(r$status == 3L && !isTRUE(r$completed), "early quit(status = 3) -> non-zero, not completed")

r <- run("UFH", c('cat("Results saved to:\\n")', 'cat("Execution halted\\n")',
                  'reg.finalizer(globalenv(), function(e) quit(save = "no", status = 255), onexit = TRUE)'))
check(r$status == 255L, "'Execution halted' in the output disables the tolerance")

setwd(old_wd); unlink(work, recursive = TRUE)
cat(sprintf("\nAll %d step-runner checks passed.\n", passed))
