<#
.DESCRIPTION
    Paper Vision shutdown - kills all services by PID file + port scan
.EXAMPLE
    .\stop.ps1
    .\stop.ps1 -Force
#>
param(
    [switch]$Force,
    [int]$PortPython  = 5000,
    [int]$PortBackend = 8080,
    [int]$PortFrontend = 5173
)

$ErrorActionPreference = "Continue"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PIDFile    = Join-Path $ScriptDir ".running.pids"

function step($m) { Write-Host "$(Get-Date -Format HH:mm:ss) $m" -ForegroundColor Cyan }
function ok($m)   { Write-Host "  [OK] $m" -ForegroundColor Green }

function Kill-Port($port, $label) {
    $conns = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue |
        Where-Object { $_.State -eq "Listen" }
    if (-not $conns) { Write-Host "  $label not running" -ForegroundColor DarkGray; return }
    $ids = $conns.OwningProcess | Sort-Object -Unique
    foreach ($id in $ids) {
        $p = Get-Process -Id $id -ErrorAction SilentlyContinue
        if ($p) {
            Write-Host "  stop $label PID=$id ($($p.ProcessName))" -ForegroundColor Gray
            Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
            ok "$label stopped"
        }
    }
}

Clear-Host
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "  Paper Vision - Shutdown"
Write-Host "========================================" -ForegroundColor Yellow

if (Test-Path $PIDFile) {
    step "Reading .running.pids ..."
    $pids = Get-Content $PIDFile | Where-Object { $_ -match "^\d+$" } | Sort-Object -Descending
    foreach ($id in $pids) {
        $p = Get-Process -Id $id -ErrorAction SilentlyContinue
        if ($p) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue; Write-Host "  PID $id killed" -ForegroundColor Gray }
    }
    Remove-Item $PIDFile -Force -ErrorAction SilentlyContinue
    ok "PID file cleaned"
} else {
    Write-Host "  No .running.pids found" -ForegroundColor DarkGray
}

step "Scanning ports ..."
Kill-Port $PortFrontend "Vue"
Kill-Port $PortBackend  "SpringBoot"
Kill-Port $PortPython   "Python"

step "Cleaning java/node/python residue ..."
Get-Process -Name "java","node","python" -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "  kill $($_.ProcessName) PID=$($_.Id)" -ForegroundColor DarkGray
    Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
}

Write-Host ""
ok "All services stopped"