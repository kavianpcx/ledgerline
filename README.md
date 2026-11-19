# Ledgerline

Ledgerline is an offline-first accounting and business-management application in active development for Windows 10/11 and Android phones and tablets. The product target includes bookkeeping, retail POS, restaurant orders, inventory, document import, and optional secure device synchronization. The latest published build is a Windows-only prerelease. No Android build is available yet.

The complete product requirements are in [docs/PRODUCT_SPECIFICATION.md](docs/PRODUCT_SPECIFICATION.md). The current code status, evidence, and risks are assessed in [docs/PRODUCT_AUDIT.md](docs/PRODUCT_AUDIT.md).

## Verified Windows prerelease

The tagged v0.5.1-beta.1 Windows prerelease provides a basic single-device ledger with the following features. It predates the current `main` branch's product CSV importer and is not a POS release:

- Local SQLite storage for accounts, journal entries and lines, products, invoices, invoice lines, invoice payments, and application settings.
- Integer arithmetic for recorded amounts and balanced journal posting for supported entries, inventory opening, sales, and invoice payments. Current reports are limited.
- A dashboard, chart of accounts, journal, basic product/inventory screen, sales invoices, and partial invoice receipt workflow.
- English and Persian RTL, light and dark themes, persisted preferences, and a bounded searchable currency selector. Currency selection in this release is not full multi-currency accounting or an exchange-rate conversion.
- Journal CSV import and offline English/Persian Tesseract OCR that extracts editable text. Product-catalog CSV mapping and transactional opening-inventory posting are now merged into `main`; OCR still extracts text only and does not classify documents or create records automatically.
- SQLite backup export and integrity-checked restore, keeping a recovery copy of the prior database.
- An integrated Windows caption area, keyboard shortcuts, per-user installer, and GitHub Actions build/test workflow.

PR [#2](https://github.com/kavianpcx/ledgerline/pull/2) restored permanent left-side Windows navigation at wide, medium, and narrow widths. The successful [PR workflow](https://github.com/kavianpcx/ledgerline/actions/runs/44306432838) built and smoke-installed the installer, ran the test matrix, and captured Windows sidebar and settings scenarios. The screenshots are retained as CI artifacts; they have not been manually pixel-reviewed in this workspace. High-DPI and Windows Snap behavior have not been separately verified.

## Current source and development work

PRs #3 through #18 are merged into `main`. PR #18 merged as `f191f1ba2ea92be24c2cead6040d204ef9843cb2`. Its [PR workflow run](https://github.com/kavianpcx/ledgerline/actions/runs/44492408849) and [post-merge main run](https://github.com/kavianpcx/ledgerline/actions/runs/44494674461) passed analysis, all ten test suites, and Windows packaging. The post-merge run skipped public publishing because its commit message lacked the explicit `[release]` marker.

The POS supports split cash and bank-transfer tenders, invoice payment history and reconciliation, a saved default tax rate, invoice discounts, full and partial-line returns with stock and ledger reversals, and A4/80 mm invoice PDF output through the system print dialog. Partial returns use schema v11, preserve older invoices and payments, prorate saved line values, and post refunds, receivables, inventory, and journals transactionally. Printed documents use saved invoice snapshots and a bundled Noto Arabic font for English and Persian. Physical printer output has not been tested. Schema v7 links older receipts only when the journal match is exact; unmatched history remains flagged for review. These source changes are not part of the published Windows release.

Run [44487141126](https://github.com/kavianpcx/ledgerline/actions/runs/44487141126) passed analysis, Windows packaging, and all ten tests, while `publish-release` was skipped. The workflow publishes only on a push to `main` whose head commit message contains `[release]`; the gate was not satisfied. The latest published prerelease remains [v0.5.1-beta.1](https://github.com/kavianpcx/ledgerline/releases/tag/v0.5.1-beta.1), published November 18, 2026. That release's UI screenshots remain defective: currency popup, Persian settings, and title bar captures are nearly blank, and the narrow-sidebar image shows a blank app with a console behind it.

The open, review-only [PR #19](https://github.com/kavianpcx/ledgerline/pull/19) is based on main and currently points to `e3397eea2e607103f59ea0ee764b3a9ecf05b8a7`. Its [run 44510332969](https://github.com/kavianpcx/ledgerline/actions/runs/44510332969) passed analysis, all ten test suites, Windows release packaging, visible-content checks, and an installer launch smoke check. OCR assertions verified the dashboard, title bar, wide/medium/narrow sidebars, light and dark settings, Persian RTL settings, and currency popup. The contact sheet was visually inspected and shows the Ledgerline window and expected controls/content in each screen. The Windows job silently installed the packaged installer, launched the installed executable, recognized dashboard text, and recorded its SHA-256 in the evidence report. The [run artifacts](https://github.com/kavianpcx/ledgerline/actions/runs/44510332969) contain the screenshots, report, and installer. This verifies the CI silent-install and launch path; it does not verify interactive installer UX, Authenticode signing, or physical printer output.

This remains a review candidate only. No `[release]` marker was added to `main`, no existing tag or release asset was changed, and no public release was published.
## Known limitations

Ledgerline is not production-ready. The Android application, secure roles and authentication, multi-device synchronization, complete multi-currency accounting, restaurant table/kitchen workflows, persistent customer records, DOCX/PDF parsing with structured OCR, encrypted backups, payroll/tax rules, market data, a complete updater, and physical printer acceptance remain unfinished. POS F2/F4 shortcuts and recent-invoice customer suggestions are merged into `main`; persistent customer records remain open. Product photos, curated icons, and reviewed XLSX product import are in `main`. The product requirements stay active; see the audit for risks and implementation status.

## Install the verified Windows release

Download the Windows prerelease from [GitHub Releases](https://github.com/kavianpcx/ledgerline/releases), run the installer, then launch Ledgerline from the Start menu or desktop shortcut. The per-user installer does not require administrator privileges. The release page does not contain an Android APK.

## Build and verify

Use Flutter stable and Visual Studio 2022 with the Desktop development with C++ workload to build Windows locally. CI uses GitHub-hosted Windows and Ubuntu runners. From the repository root:

```powershell
flutter pub get
flutter analyze
flutter test --reporter expanded
flutter run -d windows
flutter build windows --release
```

The Windows Actions workflow builds and packages the application, runs automated checks, and captures UI evidence. Android packaging and physical-device camera acceptance tests are not available yet.

## Local data, OCR, and updates

Ledgerline stores its SQLite database in the operating system's application-support directory. Local business data remains on the device. Smart Import supports reviewed CSV and XLSX product catalogs and offline image-to-text OCR. DOCX/PDF parsing and structured OCR extraction remain open. Invoice and 80 mm receipt PDFs can be sent to the operating system print dialog; printer-specific output has not been physically verified. Extracted OCR text requires user review and is not automatically posted to the ledger.

The update flow can discover GitHub Releases and check the published asset digest before offering the installer. It is not a complete standalone updater: publisher signature verification, genuine download progress and cancellation, install progress, rollback, and an older-to-newer end-to-end test are not implemented.

Backups in the published release are not encrypted, and installer packages are not Authenticode-signed. Do not use this prerelease for highly sensitive production data.

## Development status

This repository is evolving. Changes should preserve accounting history, use tested database migrations, and include automated coverage for financial behavior. A green workflow proves only the code paths exercised by that run. Release notes must identify actual artifacts and distinguish CI and emulator evidence from physical-device tests.

## License

No source license has been selected in the repository. Until a license is added, redistribution permissions are not granted.
