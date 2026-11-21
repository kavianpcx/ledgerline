from pathlib import Path
import re


manifest_path = Path("android/app/src/main/AndroidManifest.xml")
manifest = manifest_path.read_text(encoding="utf-8")
permissions = (
    "android.permission.INTERNET",
    "android.permission.USE_BIOMETRIC",
)
missing_permissions = [permission for permission in permissions if permission not in manifest]
if missing_permissions:
    lines = manifest.splitlines(keepends=True)
    application_index = next(
        (index for index, line in enumerate(lines) if line.lstrip().startswith("<application")),
        None,
    )
    if application_index is None:
        raise SystemExit("Android manifest has no application element.")

    application_indent = lines[application_index][: len(lines[application_index]) - len(lines[application_index].lstrip())]
    for permission in reversed(missing_permissions):
        lines.insert(
            application_index,
            f'{application_indent}<uses-permission android:name="{permission}" />\n',
        )
    manifest_path.write_text("".join(lines), encoding="utf-8")

activity_files = list(Path("android/app/src/main/kotlin").glob("**/MainActivity.kt"))
if len(activity_files) != 1:
    raise SystemExit(f"Expected one generated MainActivity.kt, found {len(activity_files)}.")
activity_path = activity_files[0]
activity = activity_path.read_text(encoding="utf-8")
activity = activity.replace(
    "import io.flutter.embedding.android.FlutterActivity",
    "import io.flutter.embedding.android.FlutterFragmentActivity",
)
activity = re.sub(r":\s*FlutterActivity\s*\(", ": FlutterFragmentActivity(", activity)
if "FlutterFragmentActivity" not in activity:
    raise SystemExit("Could not convert the generated Android activity to FlutterFragmentActivity.")
activity_path.write_text(activity, encoding="utf-8")

style_files = list(Path("android/app/src/main/res").glob("**/styles.xml"))
if not style_files:
    raise SystemExit("Generated Android project has no styles.xml resources.")
found_launch_theme = False
for style_path in style_files:
    styles = style_path.read_text(encoding="utf-8")
    updated, replacements = re.subn(
        r'(<style\s+name="LaunchTheme"\s+parent=")[^"]+("[^>]*>)',
        r'\1Theme.AppCompat.DayNight\2',
        styles,
    )
    if replacements:
        found_launch_theme = True
        style_path.write_text(updated, encoding="utf-8")
if not found_launch_theme:
    raise SystemExit("Could not update the generated Android LaunchTheme for biometric authentication.")
