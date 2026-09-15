**Subject:** EU SAE app – version w5e (fixes George's "exit status 255" and adds per-year covariate summary)

Dear Alexandros, Eirini and George,

Thank you for the tests on w5d. A new version, **w5e**, is ready and I would like everyone to move to it and run the analysis once more before I leave on Friday.

**What changed.**
- George's run stopped with "Step 'UFH' failed with exit status 255" even though the UFH estimates were complete. The cause was R exiting abnormally on that laptop *after* the step had finished. The app now recognises that case, records a warning in the run log, and continues to MFH and the report. George confirmed the full analysis completes with this fix.
- The Data Readiness tab's "Auxiliary Covariate Summary" now shows the mean, standard error, number of domains and the correlation with the poverty rate **for each year separately**, plus an "All years" row (the figure shown until now). The saved file `outputs/tables/aux_covariate_summary.csv` has a new `year` column.
- Nothing else changed: the statistical calculations and the Pandoc handling introduced in w5d are as before.

**Where to get it.**
https://github.com/Noboyoshida227/eu-sae-personal/releases/tag/v5.2.0-rc.6-wizard.5.6 – download **EU_SAE_520_w5e.zip** under "Assets".
SHA-256: `<paste the line from dist\EU_SAE_520_w5e\SHA256SUMS.txt>`

**Please do this.**
1. Extract the zip to a fresh folder. George: please delete the patched w5d folder so that only w5e remains.
2. Start the wizard as before (Mac: Start_Wizard.command, with the one-time "Open Anyway" step if macOS asks again; Windows: Start_Wizard.bat, click Run on the prompt).
3. Run one complete analysis with the example Spain data and the report enabled. Eirini: please plug in the laptop, set Windows not to sleep while plugged in, set "MCPE bootstrap replicates" to 50 for this test, press "Run Analysis" **once**, and then wait – even if the browser page greys out, the run continues in the black window and the results are archived under `app_runs\`.
4. Tell me the final status line, and send `run.log` from the new `app_runs\<timestamp>` folder. Eirini, a screenshot of your `app_runs` folder would also help me understand the earlier restarts.

Alexandros – I still do not have a Mac result for the Pandoc download on first run; if w5e ends with "Completed successfully" and `outputs/final_report.docx` exists, that question is answered.

Many thanks,
Nobuo
