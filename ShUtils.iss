; Don't edit me, edit ShUtils.isb. I'm autogenerated from that file

; Script generated by the Inno Setup Script Wizard.
; SEE THE DOCUMENTATION FOR DETAILS ON CREATING INNO SETUP SCRIPT FILES!

[Setup]
AppName=SIL Shoebox Utilities
AppVerName=SIL Shoebox Utilities 1.24
AppPublisher=SIL International
AppPublisherURL=http://www.sil.org/computing
; AppSupportURL=http://www.sil.org/computing
; AppUpdatesURL=http://www.sil.org/computing
DefaultDirName={pf}\SIL\ShUtils
DefaultGroupName=Shoebox Utilities
; uncomment the following line if you want your installation to run on NT 3.51 too.
; MinVersion=4,3.51
AdminPrivilegesRequired=yes
OutputBaseFilename=SHUtils_1_24
OutputDir=.
; DisableProgramGroupPage=yes
DisableStartupPrompt=yes

[Tasks]
Name: updatepath; Description: "Add installation directory to &PATH"; Flags: restart

[Dirs]
Name: "{app}\docs"

[Files]
Source: "scripts\shutils.par"; DestDir: "{app}"; CopyMode: alwaysoverwrite
Source: "D:\progs\perl\bin\parl.exe"; DestDir: "{app}"; CopyMode: alwaysoverwrite;
Source: "docs\Manual.pdf"; DestDir: "{app}\docs"; CopyMode: alwaysoverwrite
Source: "docs\team_working.pdf"; DestDir: "{app}\docs"; CopyMode: alwaysoverwrite
Source: "docs\shoebox.xsl"; DestDir: "{app}\docs"; CopyMode: alwaysoverwrite
Source: "scripts\zvs.bat"; DestDir: "{app}"; CopyMode: alwaysoverwrite
; Source: "D:\progs\perl\bin\Perl56.dll"; DestDir: "{sys}"; Flags: sharedfile;


[Icons]
Name: "{group}\Interlinear Output Manual"; Filename: "{app}\docs\Manual.pdf"
Name: "{group}\Remote Working"; Filename: "{app}\docs\team_working.pdf"
Name: "{group}\Uninstall Shoebox Utilities"; Filename: "{uninstallexe}"

[Run]
Filename: "{app}\parl.exe"; Parameters: """{app}\shutils.par"" addpath ""{app}"""; Flags: runminimized; Tasks: updatepath
Filename: "{app}\parl.exe"; Parameters: """{app}\shutils.par"" addbats.pl ""{app}"""; Flags: runminimized


[UninstallRun]
Filename: "{app}\parl.exe"; Parameters: """{app}\shutils.par"" addpath -r ""{app}"""; Flags: runminimized; Tasks: updatepath
Filename: "{app}\parl.exe"; Parameters: """{app}\shutils.par"" addbats.pl -r ""{app}"""; Flags: runminimized
