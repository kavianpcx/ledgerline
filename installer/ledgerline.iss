#define AppName "Ledgerline"
#define AppVersion "0.1.0"

[Setup]
AppId={{D27D10AE-ADE0-46B9-9F9F-88C502B60BA1}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Ledgerline
DefaultDirName={localappdata}\Programs\Ledgerline
DefaultGroupName=Ledgerline
UninstallDisplayIcon={app}\ledgerline.exe
OutputDir=output
OutputBaseFilename=ledgerline-windows-setup
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=lowest
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Ledgerline"; Filename: "{app}\ledgerline.exe"
Name: "{autodesktop}\Ledgerline"; Filename: "{app}\ledgerline.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"; Flags: unchecked

[Run]
Filename: "{app}\ledgerline.exe"; Description: "Launch Ledgerline"; Flags: postinstall nowait skipifsilent
