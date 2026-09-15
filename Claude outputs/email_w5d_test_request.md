**Subject:** EU SAE app – new version w5d for testing (fixes the start-up and Pandoc problems)

Dear Alexandros, Eirini and George,

Thank you all for the testing so far, and for the logs and screenshots – they pointed straight at the causes. A new version of the package is ready and I would be grateful if you could each try it once, following the steps for your computer below (Alexandros on the Mac; Eirini and George on Windows).

**What was wrong.** The previous version tried to fetch Pandoc (the tool that turns the results into the HTML and Word report) through a chain of R packages. On Alexandros's Mac one link in that chain was incompatible with the installed `rlang` package, so the set-up stopped before the app opened. On Eirini's laptop the Pandoc download itself did not go through, and because the report step failed the whole run was marked as failed, even though the MFH estimates had been computed.

**What changed in w5d.** The app now looks for a Pandoc that is already on the computer (for example the one bundled with RStudio) and, if there is none, downloads one verified copy into your own user profile the first time a report is needed (about 40 MB, no administrator rights). If that download is blocked by the network, the analysis still runs to the end: the run finishes with the status "Analysis completed – report unavailable", the Excel results (including the MFH tables under `outputs/data/`) are kept, and the log says why the report was skipped. The launchers on both systems now write a `startup_setup.log` file that tells us what happened.

**Where to get it.**
https://github.com/Noboyoshida227/eu-sae-personal/releases/tag/v5.2.0-rc.6-wizard.5.5 – download **EU_SAE_520_w5d.zip** under "Assets" at the bottom of that page.

If you want to check the download, its SHA-256 fingerprint is
`8a7a96773dd2dbbd35a4a9319580f6e4934cba3bcf614d7b5bb7edd6d65da614`
(`Get-FileHash .\EU_SAE_520_w5d.zip -Algorithm SHA256` in PowerShell, or `shasum -a 256 EU_SAE_520_w5d.zip` in Terminal).

**Before you start.** Please do not install Pandoc or update any R packages beforehand – the point of this test is to see whether the app handles that by itself. Extract the zip to a fresh folder (not on top of the old one), and keep the black launcher window open the whole time; closing it stops the app.

**Alexandros (Mac).**
1. Open the `Start_Here` folder and double-click **Start_Wizard.command**.
2. On macOS 15 or later the first double-click shows "Apple could not verify…". Close that dialog, open **System Settings → Privacy & Security**, scroll down, click **Open Anyway** next to Start_Wizard.command, confirm, and double-click the file again. This is needed once only.
3. Terminal opens, checks the R packages (a few minutes the first time) and then opens the wizard in your browser.

**Eirini and George (Windows).**
1. Open the `Start_Here` folder and double-click **Start_Wizard.bat**.
2. On the "The publisher could not be verified" prompt, click **Run**. (If Windows shows a blue SmartScreen box instead, click "More info" and then "Run anyway".)
3. The black window checks the R packages – on the first start this can take several minutes and may download packages. Then the wizard opens in your browser.
4. If the window stops with **"Setup incomplete"** and does not open the browser, the package installation itself failed. This is the same category as the .dll problem Eirini had earlier and is usually the laptop's security policy blocking a downloaded file; the app cannot get around that. In that case please send me `startup_setup.log` from the package folder and I will see exactly which file was blocked, so we can ask IT for the right exception.

**Everyone, once the wizard is open.**
1. Run one complete analysis with the example Spain data, with the report enabled, and let it finish.
2. When it stops, note the final status line. "Completed successfully" means everything worked, including the report. "Analysis completed – report unavailable" means the estimates are done but Pandoc could not be obtained.
3. Check the `outputs` folder: `outputs/data/pov_mfh.xlsx` (the MFH results) should be there in either case; `outputs/final_report.html` and `final_report.docx` only if the report rendered.

**If you get "report unavailable".** Your MFH and UFH results are already complete in `outputs/data/`, so nothing is lost. To get the report as well, install Pandoc yourself from https://pandoc.org/installing.html – on Windows the `.msi` installer, on the Mac the `.pkg` installer; neither needs administrator rights – then start the launcher again and re-run. The app will find the installed copy. If your laptop does not allow even that installer, tell me and we will arrange the file through IT.

Whatever the outcome, please send me `startup_setup.log` (in the package folder) and `run.log` from the run folder under `app_runs\`, plus a screenshot of the final status. Those two files tell me everything I need.

Many thanks,
Nobuo
