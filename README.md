# Ledgerline

Ledgerline is a Windows-first, offline accounting desktop app. It stores its books in a local SQLite database and posts transactions using integer minor units and double-entry accounting.

## Current capabilities

- Dashboard, chart of accounts, journal, income statement, and balance summary.
- Balanced journal entries with validation and atomic SQLite transactions.
- Product catalog, stock tracking, and sales invoices that post receivables, revenue, tax, cost of goods sold, and inventory together.
- English interface by default, Persian translation with right-to-left layout, and persisted light/dark themes.
- Smart Import with CSV preview/import and an in-app image OCR flow for review before posting.
- Windows installer built by GitHub Actions and attached to tagged GitHub Releases.

The initial account list and USD display are defaults. The app is designed for one local business file on one Windows device. The accessible conversation did not contain a full separate MASTER PROMPT or `SPEC.md`, so remaining detailed product policy is listed in [`docs/PRODUCT_SPECIFICATION.md`](docs/PRODUCT_SPECIFICATION.md).

Windows OCR is connected to the Windows on-device OCR engine. Microsoft documents that this API requires package identity (MSIX). The current Inno Setup EXE is unpackaged, so OCR is not verified as usable from that installer; a signed MSIX package identity must be added before describing OCR as delivered in the EXE build.

## Install

Download `ledgerline-windows-setup.exe` from the [Releases page](https://github.com/kavianpcx/ledgerline/releases), run it, and launch Ledgerline from the Start menu or desktop shortcut.

## Build and test

Use Flutter stable and Visual Studio 2022 with the Desktop development with C++ workload. From the repository root:

```powershell
flutter create --platforms=windows --project-name=ledgerline --org=com.ledgerline .
flutter pub get
flutter analyze
flutter test --reporter expanded
flutter run -d windows
flutter build windows --release
```

The GitHub Actions workflow performs dependency resolution, analysis, tests, Windows release build, and Inno Setup packaging on `windows-latest`. It does not create an Android project or build.

## Local data and privacy

The SQLite database is stored in the operating system's application-support directory. Journal entries, product data, invoices, and preferences remain on the device. Smart Import OCR is intended to process the selected image locally; recognized text is shown for review and is not posted until the user imports it.

## Updates

Release assets are published from successful tagged builds. The application does not yet perform unattended self-updates. Secure automatic installation requires a stable Windows code-signing identity and update trust policy, neither of which is available in the project requirements or connected repository settings.

## License

No project license has been selected yet. Do not redistribute this source until the owner chooses one.
