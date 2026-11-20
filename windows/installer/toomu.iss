; Toomu's Windows installer (Inno Setup 6), built by CI from the release folder:
;   iscc /DAppVersion=<version> /DSourceDir=<Release folder> /DOutputDir=<dist> windows\installer\toomu.iss

#ifndef AppVersion
  #define AppVersion "dev"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif

[Setup]
; Never change the AppId: Windows uses it to find the installed copy to update or uninstall.
AppId={{8F3C2A61-7B4E-4D2A-9C1F-5E6B7A8D9C02}
AppName=Toomu
AppVersion={#AppVersion}
AppPublisher=Toomu
AppPublisherURL=https://github.com/sajjadhossainshohag/toomu
AppSupportURL=https://github.com/sajjadhossainshohag/toomu/issues
DefaultDirName={autopf}\Toomu
DefaultGroupName=Toomu
DisableProgramGroupPage=yes
; Installs for the current user without asking for admin rights (into their own Programs folder).
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=toomu-windows-setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\toomu.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; Toomu open during an update: close it, update, then start it again.
CloseApplications=yes
RestartApplications=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Toomu"; Filename: "{app}\toomu.exe"
Name: "{autodesktop}\Toomu"; Filename: "{app}\toomu.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\toomu.exe"; Description: "{cm:LaunchProgram,Toomu}"; Flags: nowait postinstall skipifsilent
; Toomu's own update runs this installer silently with /relaunch=yes: start the new version when done.
Filename: "{app}\toomu.exe"; Flags: nowait; Check: Relaunch

[UninstallDelete]
; yt-dlp, FFmpeg and Deno (a few hundred MB) download on first launch into the app's support folder
; (%APPDATA%\<CompanyName>\<ProductName>, from Runner.rc); settings beside them are kept.
Type: filesandordirs; Name: "{userappdata}\Toomu\Toomu\tools"

[Code]
function Relaunch: Boolean;
begin
  Result := WizardSilent and (ExpandConstant('{param:relaunch|no}') = 'yes');
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Dir: String;
begin
  Dir := ExpandConstant('{userappdata}\Toomu\Toomu\private');
  // Kept unless the user says otherwise; a silent uninstall never deletes it.
  if (CurUninstallStep = usPostUninstall) and DirExists(Dir) and not UninstallSilent and
     (MsgBox('Also delete the files in Toomu''s private folder?' + #13#10#13#10 +
             'Choose No to keep them; they come back when you install Toomu again.',
             mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES) then
    DelTree(Dir, True, True, True);
end;
