# Changelog

## Unreleased

- Require an explicit base accounting currency before recording monetary data.
- Ask owners to confirm the currency of legacy records without changing amounts.
- Lock base currency changes once monetary history exists.
- Add integer-only amount parsing and formatting for decimal and zero-decimal currencies, including IRR and the internal TOMAN unit.
- Add currency precision, Iranian unit conversion, and repository currency-safety tests.


## 0.5.1-beta.1

Windows-only milestone prerelease.

- Restore the permanent left Windows sidebar at wide, medium, and narrow window widths.
- Move primary page navigation out of the integrated title bar while retaining the app identity and window controls.
- Add grouped searchable navigation, compact-mode tooltips, sidebar collapse animation, and persisted sidebar preference.
- Keep Android navigation adaptive in source, but this prerelease does not include an Android build.
- Capture Windows screenshots for sidebar widths, title bar, light/dark appearance, Persian layout, and the currency selector.

This is an unfinished product milestone. It does not include the full Android application, secure multi-user access, device synchronization, complete POS/restaurant workflows, full document import, or production-ready financial/security controls.
