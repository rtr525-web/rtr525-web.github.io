<#
 Jayhil Bridge for Windows (Alienware) - port of JayhilBridge-v2.command.
 Safety: never reads/stores/types passwords; never runs commands sent to it.
 Watch mode accepts ONLY the whitelisted task types below; anything else is
 refused and logged. Emptying the Recycle Bin asks on-screen first (once per session).

 Usage:  JayhilBridge.ps1            -> self-test + menu
         JayhilBridge.ps1 -Watch     -> watch the task inbox every 15 s
         JayhilBridge.ps1 -SelfTest  -> write status.txt and print it
         JayhilBridge.ps1 -Run <file.json>

 Task file examples (drop into %USERPROFILE%\JayhilBridge\tasks\):
   {"type": "open_urls", "urls": ["https://photos.google.com/upload"]}
   {"type": "google_photos_assist", "folder": "C:\\Users\\you\\Pictures\\Set1"}
   {"type": "open_folder", "folder": "C:\\Users\\you\\Downloads"}
   {"type": "set_wallpaper", "path": "C:\\Users\\you\\Pictures\\photo.jpg"}
   {"type": "empty_trash"}
   {"type": "write_status"}
#>
param([switch]$Watch, [switch]$SelfTest, [string]$Run)

$BridgeHome = Join-Path $env:USERPROFILE 'JayhilBridge'
$TasksDir   = Join-Path $BridgeHome 'tasks'
$DoneDir    = Join-Path $TasksDir 'done'
$ResultsDir = Join-Path $BridgeHome 'results'
$LogsDir    = Join-Path $BridgeHome 'logs'
$StatusFile = Join-Path $BridgeHome 'status.txt'
$LogFile    = Join-Path $LogsDir 'bridge.log'
$FeedUrl    = 'https://rtr525-web.github.io/ai-sync/status.json'
$script:ConfirmedTrash = $false

foreach ($d in $TasksDir, $DoneDir, $ResultsDir, $LogsDir) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
Add-Type -AssemblyName System.Windows.Forms

function Log([string]$m) { Add-Content -Path $LogFile -Value ("{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) }
function AskYesNo([string]$q) {
  [System.Windows.Forms.MessageBox]::Show($q, 'Jayhil Bridge', 'YesNo', 'Question') -eq 'Yes'
}

function Write-Status {
  $lines = @("Jayhil Bridge (Windows) self-test - $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
  foreach ($d in $TasksDir, $ResultsDir, $LogsDir) {
    $lines += if (Test-Path $d) { "PASS folder exists: $d" } else { "FAIL missing folder: $d" }
  }
  try {
    $s = Invoke-RestMethod -Uri $FeedUrl -TimeoutSec 15
    $lines += if ($s.overall -eq 'LIVE') { "PASS empire site: LIVE (checked $($s.checked_at))" } else { "FAIL empire site: $($s.overall) - $($s.problems -join ', ')" }
  } catch { $lines += "FAIL could not reach $FeedUrl" }
  $lines | Set-Content -Path $StatusFile
  return $lines
}

function Is-WebUrl([string]$u) { $u -match '^https?://' }

function Invoke-Task([string]$file) {
  $base = [IO.Path]::GetFileNameWithoutExtension($file)
  $type = ''; $status = 'rejected'; $detail = ''
  try { $t = Get-Content -Raw -Path $file | ConvertFrom-Json; $type = [string]$t.type }
  catch { $detail = 'Task file is not valid JSON - nothing was run.' }

  if (-not $detail) {
    switch ($type) {
      'open_urls' {
        $n = 0
        foreach ($u in @($t.urls)) { if (Is-WebUrl $u) { Start-Process $u; $n++ } else { Log "open_urls: skipped non-web address: $u" } }
        $status = 'done'; $detail = "Opened $n web address(es)."
      }
      'open_folder' {
        if ($t.folder -and (Test-Path -PathType Container $t.folder)) { Start-Process explorer.exe $t.folder; $status='done'; $detail="Opened folder: $($t.folder)" }
        else { $status='failed'; $detail="Folder not found: $($t.folder)" }
      }
      'google_photos_assist' {
        if ($t.folder -and (Test-Path -PathType Container $t.folder)) {
          Start-Process explorer.exe $t.folder; Start-Process 'https://photos.google.com/upload'
          $status='done'; $detail="Opened $($t.folder) and the Google Photos upload page - drag the photos in."
        } else { $status='failed'; $detail="Folder not found: $($t.folder)" }
      }
      'set_wallpaper' {
        $p = [string]$t.path
        if ($p -and (Test-Path -PathType Leaf $p) -and ($p -match '\.(jpe?g|png|bmp)$')) {
          Add-Type -Namespace JB -Name W -MemberDefinition '[DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int SystemParametersInfo(int a,int b,string c,int d);'
          [void][JB.W]::SystemParametersInfo(20, 0, $p, 3)
          $status='done'; $detail="Wallpaper set: $p"
        } else { $status='failed'; $detail="Not a usable picture file: $p" }
      }
      'empty_trash' {
        if (-not $script:ConfirmedTrash) { $script:ConfirmedTrash = AskYesNo 'Muse asked to empty the Recycle Bin. Allow this for this session?' }
        if ($script:ConfirmedTrash) { Clear-RecycleBin -Force -ErrorAction SilentlyContinue; $status='done'; $detail='Recycle Bin emptied.' }
        else { $status='failed'; $detail='Declined on-screen - Recycle Bin not emptied.' }
      }
      'write_status' { [void](Write-Status); $status='done'; $detail='status.txt refreshed.' }
      ''      { $detail = 'Task file has no type - nothing was run.' }
      default { $detail = "Unknown task type '$type' - refused by design." }
    }
  }
  [ordered]@{ task=$base; type=$type; status=$status; detail=$detail; finished_at=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') } |
    ConvertTo-Json | Set-Content -Path (Join-Path $ResultsDir "$base.result.json")
  Move-Item -Force -Path $file -Destination $DoneDir -ErrorAction SilentlyContinue
  Log "task '$base' ($type): $status - $detail"
  Write-Host "[$status] $base - $detail"
}

function Start-Watch {
  Log 'watch_mode: started'
  Write-Host "Jayhil Bridge watch mode is running. Watching $TasksDir every 15 seconds. Close this window to stop."
  while ($true) {
    Get-ChildItem -Path $TasksDir -Filter *.json -File -ErrorAction SilentlyContinue | ForEach-Object { Invoke-Task $_.FullName }
    Start-Sleep -Seconds 15
  }
}

if ($Run)      { Invoke-Task $Run; exit }
if ($SelfTest) { Write-Status | ForEach-Object { Write-Host $_ }; exit }
if ($Watch)    { [void](Write-Status); Start-Watch; exit }

Write-Status | ForEach-Object { Write-Host $_ }
$quit = $false
while (-not $quit) {
  Write-Host "`n  JAYHIL BRIDGE (Windows)`n  1) Watch mode - let Muse send tasks`n  2) Self-test`n  3) Open the Bridge folder`n  0) Quit"
  switch (Read-Host 'Type a number and press Enter') {
    '1' { Start-Watch }
    '2' { Write-Status | ForEach-Object { Write-Host $_ } }
    '3' { Start-Process explorer.exe $BridgeHome }
    '0' { $quit = $true }
    default { Write-Host 'Please type 1, 2, 3, or 0.' }
  }
}
