; Solo Thirai Player - Windows installer (Inno Setup 6)
#ifndef AppVer
  #define AppVer "1.0.0"
#endif

[Setup]
AppId={{8F3C2A51-7B7E-4C1D-9A2E-5D1F0B7C9E11}
AppName=Solo Thirai Player
AppVersion={#AppVer}
AppPublisher=Xiasolo
DefaultDirName={autopf}\Solo Thirai Player
DefaultGroupName=Solo Thirai Player
OutputDir=..\dist
OutputBaseFilename=SoloThiraiPlayer-Setup-{#AppVer}
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
ChangesAssociations=yes
UninstallDisplayIcon={app}\thirai_player.exe
PrivilegesRequiredOverridesAllowed=dialog
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "Desktop shortcut create pannu"; GroupDescription: "Extra:"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{group}\Solo Thirai Player"; Filename: "{app}\thirai_player.exe"
Name: "{group}\Uninstall Solo Thirai Player"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Solo Thirai Player"; Filename: "{app}\thirai_player.exe"; Tasks: desktopicon

[Registry]
; "Open with -> Solo Thirai Player" for video files
Root: HKA; Subkey: "Software\Classes\ThiraiPlayer.Video"; ValueType: string; ValueData: "Video (Solo Thirai Player)"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\ThiraiPlayer.Video\DefaultIcon"; ValueType: string; ValueData: "{app}\thirai_player.exe,0"
Root: HKA; Subkey: "Software\Classes\ThiraiPlayer.Video\shell\open\command"; ValueType: string; ValueData: """{app}\thirai_player.exe"" ""%1"""
Root: HKA; Subkey: "Software\Classes\.mp4\OpenWithProgids"; ValueType: string; ValueName: "ThiraiPlayer.Video"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.mkv\OpenWithProgids"; ValueType: string; ValueName: "ThiraiPlayer.Video"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.avi\OpenWithProgids"; ValueType: string; ValueName: "ThiraiPlayer.Video"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.mov\OpenWithProgids"; ValueType: string; ValueName: "ThiraiPlayer.Video"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.wmv\OpenWithProgids"; ValueType: string; ValueName: "ThiraiPlayer.Video"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.flv\OpenWithProgids"; ValueType: string; ValueName: "ThiraiPlayer.Video"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.webm\OpenWithProgids"; ValueType: string; ValueName: "ThiraiPlayer.Video"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.m4v\OpenWithProgids"; ValueType: string; ValueName: "ThiraiPlayer.Video"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.ts\OpenWithProgids"; ValueType: string; ValueName: "ThiraiPlayer.Video"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.m2ts\OpenWithProgids"; ValueType: string; ValueName: "ThiraiPlayer.Video"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.mts\OpenWithProgids"; ValueType: string; ValueName: "ThiraiPlayer.Video"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.mpg\OpenWithProgids"; ValueType: string; ValueName: "ThiraiPlayer.Video"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.mpeg\OpenWithProgids"; ValueType: string; ValueName: "ThiraiPlayer.Video"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.3gp\OpenWithProgids"; ValueType: string; ValueName: "ThiraiPlayer.Video"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.vob\OpenWithProgids"; ValueType: string; ValueName: "ThiraiPlayer.Video"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.rmvb\OpenWithProgids"; ValueType: string; ValueName: "ThiraiPlayer.Video"; ValueData: ""; Flags: uninsdeletevalue

[Run]
Filename: "{app}\thirai_player.exe"; Description: "Solo Thirai Player open pannu"; Flags: nowait postinstall skipifsilent
