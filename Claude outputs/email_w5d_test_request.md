**Subject:** EU SAE app – new version w5d for testing (fixes the Mac start-up problem)

Dear Alex and Eirini,

Thank you for the testing so far, and Alex, thank you for sending the Terminal log – it pointed straight at the cause. A new version of the package is ready and I would be grateful if you could each try it once.

**What was wrong.** The previous version tried to fetch Pandoc (the tool that turns the results into the HTML and Word report) through a chain of R packages, and on Alex's Mac one link in that chain was incompatible with the installed version of the `rlang` package. The set-up script then stopped before the app opened.

**What changed in w5d.** The app now finds a Pandoc that is already on the computer (for example the one bundled with RStudio) and, if there is none, downloads one verified copy into your user profile the first time a report is needed (about 40 MB, no administrator rights). If that download is blocked by the network, the analysis still runs to the end; the run then finishes as "Analysis completed – report unavailable" and the log says why. On the Mac, the launcher now also writes a `startup_setup.log` file, as the Windows launcher already did.

**Where to get it.**
[GitHub release: https://github.com/Noboyoshida227/eu-sae-application-package/releases/tag/v5.2.0-rc.6-wizard.5.4 – or the attached EU_SAE_520_w5d.zip]

If you want to check the download, its SHA-256 fingerprint is
`8a7a96773dd2dbbd35a4a9319580f6e4934cba3bcf614d7b5bb7edd6d65da614`
(`Get-FileHash .\EU_SAE_520_w5d.zip -Algorithm SHA256` in PowerShell, or `shasum -a 256 EU_SAE_520_w5d.zip` in Terminal).

**What I would like you to test.** Please do not install Pandoc or update any R packages beforehand – the point of this test is to see the app handle that itself.

1. Extract the zip to a fresh folder (not on top of the old one).
2. Open `Start_Here` and double-click **Start_Wizard.command** (Mac) or **Start_Wizard.bat** (Windows).
   - Mac (macOS 15 or later): the first double-click shows "Apple could not verify…". Close it, open System Settings → Privacy & Security, scroll down, click **Open Anyway** next to Start_Wizard.command, then double-click it again. Once only.
   - Windows: on the "publisher could not be verified" prompt, click **Run**.
3. Leave the window open. The first start checks the R packages and may take a few minutes.
4. In the wizard, run one complete analysis with the example Spain data, with the report enabled, and let it finish.
5. Tell me what the final status line says and whether `outputs/final_report.html` and `final_report.docx` were produced.

Whether it works or not, please send me `startup_setup.log` (in the package folder) and `run.log` from the run folder under `app_runs/`, plus a screenshot if anything looks odd. If the report was not produced, the log will tell us whether the Pandoc download was blocked on your network, which is the one thing I cannot test from here.

Many thanks,
Nobuo
