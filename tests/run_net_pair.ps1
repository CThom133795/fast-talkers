# Two-process network test driver used by run_net_pair.cmd. See run_net_pair.sh for the same logic in bash.
param([int]$Port = 24651, [string]$Steps = "lobby")
$ErrorActionPreference = "Stop"
$project = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$work = (Resolve-Path (Join-Path $project "..\..\work")).Path
$godot = Join-Path $work "tools\godot\Godot_v4.4.1-stable_win64_console.exe"
$hostLog = Join-Path $work "net-host.log"
$clientLog = Join-Path $work "net-client.log"
$limit = 70
if ($Steps -match "(^|,)round(,|$)") { $limit = 140 }

function Start-Role([string]$role, [string]$log) {
	$errLog = $log + ".err"
	$argList = @("--headless", "--path", "`"$project`"", "--log-file", "`"$log.engine`"", "--script", "res://tests/net_pair.gd", "--", "--role=$role", "--port=$Port", "--steps=$Steps")
	return Start-Process -FilePath $godot -ArgumentList $argList -PassThru -WindowStyle Hidden -RedirectStandardOutput $log -RedirectStandardError $errLog
}
function Stop-Tree($proc) {
	if ($proc -and -not $proc.HasExited) { & taskkill /PID $proc.Id /T /F 2>&1 | Out-Null }
}

Write-Host "net_pair: port $Port, steps '$Steps'"
$hostProc = Start-Role "host" $hostLog
Start-Sleep -Milliseconds 1500
$clientProc = Start-Role "client" $clientLog
$stopwatch = [Diagnostics.Stopwatch]::StartNew()
try {
	while (-not ($hostProc.HasExited -and $clientProc.HasExited)) {
		if ($stopwatch.Elapsed.TotalSeconds -ge $limit) {
			Write-Host "net_pair: hard timeout after ${limit}s, killing what is left"
			break
		}
		Start-Sleep -Milliseconds 500
	}
} finally {
	Stop-Tree $hostProc
	Stop-Tree $clientProc
}
# Merge stderr into the main log so SCRIPT ERROR lines are visible.
foreach ($log in @($hostLog, $clientLog)) {
	if (Test-Path ($log + ".err")) { Get-Content ($log + ".err") | Add-Content $log; Remove-Item ($log + ".err") }
}
$hostResult = Select-String -Path $hostLog -Pattern "NET PAIR HOST RESULT" | Select-Object -Last 1
$clientResult = Select-String -Path $clientLog -Pattern "NET PAIR CLIENT RESULT" | Select-Object -Last 1
$failed = $false
foreach ($pair in @(@($hostResult, "HOST", $hostLog), @($clientResult, "CLIENT", $clientLog))) {
	if ($pair[0]) {
		$text = $pair[0].Line.Trim()
		Write-Host $text
		if ($text -notmatch " 0 failures") { $failed = $true }
	} else {
		Write-Host ("NET PAIR {0} RESULT: MISSING (see {1})" -f $pair[1], $pair[2])
		$failed = $true
	}
}
if ($failed) {
	Write-Host "NET PAIR FAILED. Failing lines:"
	Select-String -Path $hostLog, $clientLog -Pattern "FAIL|SCRIPT ERROR|WATCHDOG" -CaseSensitive | ForEach-Object { $_.Line.Trim() } | Sort-Object -Unique | Select-Object -First 20
	exit 1
}
Write-Host "NET PAIR PASSED"
exit 0
