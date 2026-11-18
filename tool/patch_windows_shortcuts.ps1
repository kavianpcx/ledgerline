$ErrorActionPreference = 'Stop'
$path = 'windows/runner/flutter_window.cpp'
$source = [System.IO.File]::ReadAllText($path)
if ($source.Contains('ledgerline_keyboard_hook')) {
  throw 'Ledgerline keyboard hook was already applied.'
}

$includeAnchor = '#include "flutter/generated_plugin_registrant.h"'
$hook = @'
namespace {
HHOOK ledgerline_keyboard_hook = nullptr;
HWND ledgerline_main_window = nullptr;
DWORD ledgerline_suppressed_key_up = 0;

LRESULT CALLBACK LedgerlineKeyboardProc(int code, WPARAM message, LPARAM data) {
  if (code == HC_ACTION) {
    const auto* key = reinterpret_cast<const KBDLLHOOKSTRUCT*>(data);
    const bool key_down = message == WM_KEYDOWN || message == WM_SYSKEYDOWN;
    const bool key_up = message == WM_KEYUP || message == WM_SYSKEYUP;

    if (key_up && ledgerline_suppressed_key_up == key->vkCode) {
      ledgerline_suppressed_key_up = 0;
      return 1;
    }

    if (key_down &&
        (key->vkCode == 0x46 || key->vkCode == 0x4D) &&
        ledgerline_suppressed_key_up != key->vkCode) {
      const HWND foreground = GetForegroundWindow();
      const HWND root = foreground == nullptr ? nullptr : GetAncestor(foreground, GA_ROOT);
      if (root == ledgerline_main_window &&
          (GetAsyncKeyState(VK_CONTROL) & 0x8000) != 0 &&
          (GetAsyncKeyState(VK_SHIFT) & 0x8000) != 0) {
        ledgerline_suppressed_key_up = key->vkCode;
        if (key->vkCode == 0x46) {
          ShowWindow(ledgerline_main_window,
                     IsZoomed(ledgerline_main_window) ? SW_RESTORE : SW_MAXIMIZE);
        } else {
          ShowWindow(ledgerline_main_window, SW_MINIMIZE);
        }
        return 1;
      }
    }

    if (key_down && ledgerline_suppressed_key_up == key->vkCode) {
      return 1;
    }
  }

  return CallNextHookEx(ledgerline_keyboard_hook, code, message, data);
}
}  // namespace

'@
if (-not $source.Contains($includeAnchor)) {
  throw "The generated Flutter window source did not contain the expected include anchor: $path"
}
$source = $source.Replace($includeAnchor, $includeAnchor + [Environment]::NewLine + [Environment]::NewLine + $hook.TrimEnd())
$createAnchor = '  SetChildContent(flutter_controller_->view()->GetNativeWindow());'
$createPatch = @'
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  ledgerline_main_window = GetHandle();
  ledgerline_keyboard_hook = SetWindowsHookExW(
      WH_KEYBOARD_LL, LedgerlineKeyboardProc, GetModuleHandleW(nullptr), 0);
'@
if (-not $source.Contains($createAnchor)) {
  throw "The generated Flutter window source did not contain the expected child-window anchor: $path"
}
$source = $source.Replace($createAnchor, $createPatch.TrimEnd())
$destroyAnchor = @'
void FlutterWindow::OnDestroy() {
'@
$destroyPatch = @'
void FlutterWindow::OnDestroy() {
  if (ledgerline_keyboard_hook != nullptr) {
    UnhookWindowsHookEx(ledgerline_keyboard_hook);
    ledgerline_keyboard_hook = nullptr;
  }
  ledgerline_main_window = nullptr;
'@
if (-not $source.Contains($destroyAnchor)) {
  throw "The generated Flutter window source did not contain the expected destroy anchor: $path"
}
$source = $source.Replace($destroyAnchor, $destroyPatch.TrimEnd())
[System.IO.File]::WriteAllText($path, $source, [System.Text.UTF8Encoding]::new($false))
Write-Host 'Installed Ledgerline foreground-scoped Win32 titlebar shortcuts.'
