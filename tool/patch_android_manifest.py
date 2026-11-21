from pathlib import Path


manifest_path = Path("android/app/src/main/AndroidManifest.xml")
manifest = manifest_path.read_text(encoding="utf-8")
permission = 'android.permission.INTERNET'
if permission in manifest:
    raise SystemExit(0)

lines = manifest.splitlines(keepends=True)
application_index = next(
    (index for index, line in enumerate(lines) if line.lstrip().startswith("<application")),
    None,
)
if application_index is None:
    raise SystemExit("Android manifest has no application element.")

application_indent = lines[application_index][: len(lines[application_index]) - len(lines[application_index].lstrip())]
lines.insert(
    application_index,
    f'{application_indent}<uses-permission android:name="android.permission.INTERNET" />\n',
)
manifest_path.write_text("".join(lines), encoding="utf-8")
