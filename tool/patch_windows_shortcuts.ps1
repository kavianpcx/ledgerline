$ErrorActionPreference = 'Stop'
$path = 'windows/runner/flutter_window.cpp'
$source = [System.IO.File]::ReadAllText($path)
$anchor = @'
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
'@
$replacement = @'
  // Ledgerline's integrated title bar keeps explicit window shortcuts in Win32
  // so they work regardless of which Flutter control currently has focus.
  if ((message == WM_KEYDOWN || message == WM_SYSKEYDOWN) &&
      (GetAsyncKeyState(VK_CONTROL) & 0x8000) != 0 &&
      (GetAsyncKeyState(VK_SHIFT) & 0x8000) != 0) {
    if (wparam == 'F') {
      ShowWindow(hwnd, IsZoomed(hwnd) ? SW_RESTORE : SW_MAXIMIZE);
      return 0;
    }
    if (wparam == 'M') {
      ShowWindow(hwnd, SW_MINIMIZE);
      return 0;
    }
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
'@
if (-not $source.Contains($anchor)) {
  throw "The generated Flutter window source did not contain the expected message-handler anchor: $path"
}
[System.IO.File]::WriteAllText($path, $source.Replace($anchor, $replacement), [System.Text.UTF8Encoding]::new($false))
Write-Host 'Installed Ledgerline Win32 titlebar keyboard shortcuts.'
