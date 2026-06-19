<#
.DESCRIPTION
    Paper Vision launcher - opens 3 services in separate windows
    Double-click start.bat to use this script
.EXAMPLE
    .\start.ps1
    .\start.ps1 -SkipPython
#>
param(
    [switch]$SkipPython,
    [switch]$SkipBackend,
    [switch]$SkipFrontend,
    [int]$PortPython  = 5001,
    [int]$PortBackend = 8080,
    [int]$PortFrontend = 5173
)

$ErrorActionPreference = "Continue"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PIDFile    = Join-Path $ScriptDir ".running.pids"

function header($m)   { Write-Host ">>> $m" -ForegroundColor Cyan }
function ok($m)       { Write-Host "    [OK] $m" -ForegroundColor Green }
function fail($m)     { Write-Host "    [XX] $m" -ForegroundColor Red }
function info($m)     { Write-Host "    $m" -ForegroundColor Gray }

# Clean old PID file
if (Test-Path $PIDFile) { Remove-Item $PIDFile -Force -ErrorAction SilentlyContinue }

Write-Host ""
Write-Host "  Paper Vision Launcher" -ForegroundColor Blue
Write-Host "  Each service opens in its own window. Check each window for errors."
Write-Host ""

# ---- MySQL quick check ----
header "MySQL check"
$null = cmd /c "mysql -u root -p123456 -e `"SELECT 1`" 2>&1"
if ($LASTEXITCODE -eq 0) { ok "MySQL OK" } else { fail "MySQL failed" }

# ---- 1. Python ----
if (-not $SkipPython) {
    header "Python render service (port $PortPython)"
    $pyDir = Join-Path $ScriptDir "python-service"
    if (-not (Test-Path (Join-Path $pyDir "main.py"))) { fail "main.py missing" }
    else {
        $py = Get-Command python -ErrorAction SilentlyContinue
        if (-not $py) { $py = Get-Command python3 -ErrorAction SilentlyContinue }
        if (-not $py) { fail "python not in PATH" }
        else {
            # Check deps, install if needed
            $null = cmd /c "pip show fastapi 2>&1"
            if ($LASTEXITCODE -ne 0) {
                info "Installing pip deps..."
                $null = cmd /c "cd /d `"$pyDir`" && pip install -r requirements.txt 2>&1"
                if ($LASTEXITCODE -eq 0) { ok "deps installed" } else { fail "pip install failed" }
            }
            # Launch in new visible window
            $proc = Start-Process "cmd" -ArgumentList "/c `"cd /d $pyDir && python main.py && pause`"" -PassThru
            if ($proc) {
                Add-Content -Path $PIDFile -Value $proc.Id
                ok "Python launched in new window (PID=$($proc.Id)). Check that window for errors."
            } else { fail "Python failed to start" }
        }
    }
}

# ---- 2. Spring Boot ----
if (-not $SkipBackend) {
    header "Spring Boot backend (port $PortBackend)"
    $beDir = Join-Path $ScriptDir "backend"
    if (-not (Test-Path (Join-Path $beDir "pom.xml"))) { fail "backend\pom.xml missing" }
    else {
        $mvn = Get-Command mvn -ErrorAction SilentlyContinue
        if (-not $mvn) { fail "mvn not in PATH" }
        else {
            $proc = Start-Process "cmd" -ArgumentList "/c `"cd /d $beDir && mvn spring-boot:run && pause`"" -PassThru
            if ($proc) {
                Add-Content -Path $PIDFile -Value $proc.Id
                ok "SpringBoot launched in new window (PID=$($proc.Id)). First startup takes 1-2 min for Maven downloads."
            } else { fail "SpringBoot failed to start" }
        }
    }
}

# ---- 3. Vue ----
if (-not $SkipFrontend) {
    header "Vue frontend (port $PortFrontend)"
    $feDir = Join-Path $ScriptDir "frontend"
    if (-not (Test-Path (Join-Path $feDir "package.json"))) { fail "frontend\package.json missing" }
    else {
        $npm = Get-Command npm -ErrorAction SilentlyContinue
        if (-not $npm) { fail "npm not in PATH" }
        else {
            if (-not (Test-Path (Join-Path $feDir "node_modules"))) {
                info "Installing npm deps..."
                $null = cmd /c "cd /d `"$feDir`" && npm install 2>&1"
                if ($LASTEXITCODE -eq 0) { ok "npm install done" } else { fail "npm install failed" }
            }
            $proc = Start-Process "cmd" -ArgumentList "/c `"cd /d $feDir && npm run dev && pause`"" -PassThru
            if ($proc) {
                Add-Content -Path $PIDFile -Value $proc.Id
                ok "Vue launched in new window (PID=$($proc.Id))"
            } else { fail "Vue failed to start" }
        }
    }
}

# ---- Done ----
Write-Host ""
Write-Host "  Three cmd windows should now be open:" -ForegroundColor Green
Write-Host "    1. Python  -> http://localhost:$PortPython/health"
Write-Host "    2. Backend -> http://localhost:$PortBackend (SpringBoot takes 30-120s)"
Write-Host "    3. Vue     -> http://localhost:$PortFrontend"
Write-Host ""
Write-Host "  Close all: .\stop.ps1  or close each window manually" -ForegroundColor Gray
Write-Host ""

Start-Sleep 3
# Try to open browser after a moment
try { Start-Process "http://localhost:${PortFrontend}" } catch {}