# Builds the friends playtest zip: exported exe (pck embedded), GodotSteam DLLs, steam_appid.txt (480),
# the walkthrough and licences. Never touches ../play-fast-talkers (the user's own exe).
#   powershell -ExecutionPolicy Bypass -File tools\build_playtest.ps1
# Output: ..\playtest-build\Fast Talkers\ and ..\Fast Talkers Playtest.zip (next to the project folder).
param([string]$OutRoot = "")
$ErrorActionPreference = "Stop"
$project = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$outputs = (Resolve-Path (Join-Path $project "..")).Path
if ($OutRoot -eq "") { $OutRoot = Join-Path $outputs "playtest-build" }
$godot = (Resolve-Path (Join-Path $project "..\..\work\tools\godot\Godot_v4.4.1-stable_win64_console.exe")).Path
$folder = Join-Path $OutRoot "Fast Talkers"
$exe = Join-Path $folder "Fast Talkers.exe"
$zip = Join-Path $outputs "Fast Talkers Playtest.zip"
$log = Join-Path $outputs "..\work\export-playtest.log"

if (Test-Path $folder) { Remove-Item -Recurse -Force $folder }
New-Item -ItemType Directory -Force $folder | Out-Null
Write-Host "Exporting to $exe"
& $godot --headless --path $project --log-file $log --export-release "Windows Desktop" $exe | Out-Null
if (-not (Test-Path $exe)) { throw "Export failed: no exe. See $log" }

# The GDExtension libraries land next to the exe on export; check rather than trust.
foreach ($dll in @("libgodotsteam.windows.template_release.x86_64.dll", "steam_api64.dll")) {
	if (-not (Test-Path (Join-Path $folder $dll))) {
		$src = Join-Path $project "addons\godotsteam\win64\$dll"
		Write-Host "Copying $dll (the export did not)"
		Copy-Item $src $folder
	}
}
Set-Content -Path (Join-Path $folder "steam_appid.txt") -Value "480" -NoNewline -Encoding ascii
Copy-Item (Join-Path $project "tools\playtest\HOW TO PLAY WITH FRIENDS.txt") $folder
Copy-Item (Join-Path $project "addons\godotsteam\license.md") (Join-Path $folder "GODOTSTEAM-LICENSE.txt")
$godotLicense = Join-Path $outputs "play-fast-talkers\GODOT-LICENSE.txt"
if (Test-Path $godotLicense) { Copy-Item $godotLicense $folder }
$notices = Join-Path $outputs "play-fast-talkers\GODOT-THIRD-PARTY-NOTICES.txt"
if (Test-Path $notices) { Copy-Item $notices $folder }

if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path $folder -DestinationPath $zip
$size = [math]::Round((Get-Item $zip).Length / 1MB, 1)
Write-Host "Built $zip ($size MB)"
Get-ChildItem $folder | Select-Object Name, Length | Format-Table -AutoSize
