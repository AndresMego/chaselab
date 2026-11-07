; SPDX-License-Identifier: Apache-2.0
#define AppVersion "0.1.0-demo.1"
[Setup]
AppId={{942BE0A2-62EF-45FA-8A57-A1353E00C201}
AppName=ChaseLab_MM Windows Demo
AppVersion={#AppVersion}
DefaultDirName={localappdata}\Programs\ChaseLab_MM-WindowsDemo
DefaultGroupName=ChaseLab_MM
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
OutputDir=..\..\dist\windows
OutputBaseFilename=ChaseLab_MM-Windows-x64-0.1.0-demo.1-Setup
Compression=lzma2
SolidCompression=yes
UninstallDisplayIcon={app}\ChaseLab_MM.exe
[Files]
Source: "..\..\build\windows\app\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\docs\WINDOWS-DEMO.md"; DestDir: "{app}"
Source: "..\..\LICENSE"; DestDir: "{app}"
Source: "..\..\third_party\ffgl\LICENSE.md"; DestDir: "{app}"; DestName: "FFGL-LICENSE.md"
[Icons]
Name: "{group}\ChaseLab_MM Windows Demo"; Filename: "{app}\ChaseLab_MM.exe"
Name: "{group}\Desinstalar ChaseLab_MM Windows Demo"; Filename: "{uninstallexe}"
[Run]
Filename: "{app}\ChaseLab_MM.exe"; Description: "Abrir ChaseLab_MM Windows Demo"; Flags: nowait postinstall skipifsilent
; User projects/recovery and the manually installed Arena DLL are deliberately not deleted.
