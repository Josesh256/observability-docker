# PowerShell Automated Setup for Observability & VPN Stack
# Designed to run unattended and auto-configure

$ErrorActionPreference = "Stop"

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "   Observability & VPN Stack Initializer     " -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

# 1. Check for Docker
if (-not (Get-Command "docker" -ErrorAction SilentlyContinue)) {
    Write-Error "Docker is not installed or not in PATH. Please install Docker Desktop and try again."
    Exit 1
}

# 2. Check and Load .env
$EnvFile = Join-Path $PSScriptRoot ".env"
if (-not (Test-Path $EnvFile)) {
    Write-Host "Creating default .env file..." -ForegroundColor Yellow
    $DefaultEnv = @'
PROJECT_NAME=observability-stack
NGINX_PORT=8080
GRAFANA_PORT=3000
PROMETHEUS_PORT=9090
WIREGUARD_PORT=51820
GF_SECURITY_ADMIN_PASSWORD=admin
WG_SERVERURL=127.0.0.1
WG_PEERS=laptop,phone
WG_PEER_DNS=1.1.1.1
WG_INTERNAL_SUBNET=10.13.13.0/24
'@
    Set-Content -Path $EnvFile -Value $DefaultEnv
}

# Function to read .env file
function Get-EnvVar($key, $default) {
    $line = Get-Content $EnvFile | Get-Unique | Where-Object { $_ -match "^$key=" }
    if ($line) {
        return ($line -split '=', 2)[1].Trim()
    }
    return $default
}

# Function to update .env file
function Set-EnvVar($key, $value) {
    $content = Get-Content $EnvFile
    $replaced = $false
    for ($i = 0; $i -lt $content.Length; $i++) {
        if ($content[$i] -match "^$key=") {
            $content[$i] = "$key=$value"
            $replaced = $true
            break
        }
    }
    if (-not $replaced) {
        $content += "$key=$value"
    }
    Set-Content -Path $EnvFile -Value $content
}

# Load current ports
$NginxPort = [int](Get-EnvVar "NGINX_PORT" "8080")
$GrafanaPort = [int](Get-EnvVar "GRAFANA_PORT" "3000")
$PrometheusPort = [int](Get-EnvVar "PROMETHEUS_PORT" "9090")
$WireguardPort = [int](Get-EnvVar "WIREGUARD_PORT" "51820")
$WireguardUiPort = [int](Get-EnvVar "WG_UI_PORT" "51821")


# Helper to check if a TCP port is available
function Test-TcpPortAvailable($port) {
    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $port)
        $listener.Start()
        $listener.Stop()
        return $true
    } catch {
        return $false
    }
}

# Helper to check if a UDP port is available
function Test-UdpPortAvailable($port) {
    try {
        $listener = [System.Net.Sockets.UdpClient]::new($port)
        $listener.Close()
        return $true
    } catch {
        return $false
    }
}

# Validate and assign ports dynamically
Write-Host "Validating port availability..." -ForegroundColor Gray

# Nginx
while (-not (Test-TcpPortAvailable $NginxPort)) {
    Write-Host "Port $NginxPort is occupied. Trying next..." -ForegroundColor Yellow
    $NginxPort++
}
Set-EnvVar "NGINX_PORT" $NginxPort

# Grafana
while (-not (Test-TcpPortAvailable $GrafanaPort)) {
    Write-Host "Port $GrafanaPort is occupied. Trying next..." -ForegroundColor Yellow
    $GrafanaPort++
}
Set-EnvVar "GRAFANA_PORT" $GrafanaPort

# Prometheus
while (-not (Test-TcpPortAvailable $PrometheusPort)) {
    Write-Host "Port $PrometheusPort is occupied. Trying next..." -ForegroundColor Yellow
    $PrometheusPort++
}
Set-EnvVar "PROMETHEUS_PORT" $PrometheusPort

# WireGuard (UDP)
while (-not (Test-UdpPortAvailable $WireguardPort)) {
    Write-Host "UDP Port $WireguardPort is occupied. Trying next..." -ForegroundColor Yellow
    $WireguardPort++
}
Set-EnvVar "WIREGUARD_PORT" $WireguardPort

# WireGuard UI (TCP)
while (-not (Test-TcpPortAvailable $WireguardUiPort)) {
    Write-Host "Port $WireguardUiPort is occupied. Trying next..." -ForegroundColor Yellow
    $WireguardUiPort++
}
Set-EnvVar "WG_UI_PORT" $WireguardUiPort

# Load final configurations
$ProjectName = Get-EnvVar "PROJECT_NAME" "observability-stack"
$AdminPassword = Get-EnvVar "GF_SECURITY_ADMIN_PASSWORD" "admin"

Write-Host "`nConfiguration set:" -ForegroundColor Green
Write-Host "--------------------"
Write-Host "Project Name:    $ProjectName"
Write-Host "Nginx Port:      $NginxPort"
Write-Host "Grafana Port:    $GrafanaPort"
Write-Host "Prometheus Port: $PrometheusPort"
Write-Host "WireGuard Port:  $WireguardPort (UDP)"
Write-Host "WireGuard UI:    $WireguardUiPort"
Write-Host "--------------------`n"

# 3. Create persistent directories
Write-Host "Preparing persistent folders..." -ForegroundColor Gray
$Dirs = @("vpn/config", "apps/web/html", "monitoring/prometheus", "monitoring/grafana/provisioning/datasources", "monitoring/grafana/provisioning/dashboards")
foreach ($dir in $Dirs) {
    $path = Join-Path $PSScriptRoot $dir
    if (-not (Test-Path $path)) {
        New-Item -ItemType Directory -Force -Path $path | Out-Null
    }
}

# 3.5 Generate Alertmanager configuration with Telegram keys
Write-Host "Generating Alertmanager configuration from template..." -ForegroundColor Gray
$TelegramToken = Get-EnvVar "TELEGRAM_BOT_TOKEN" "YOUR_TELEGRAM_BOT_TOKEN"
$TelegramChatId = Get-EnvVar "TELEGRAM_CHAT_ID" "YOUR_TELEGRAM_CHAT_ID"

$TemplatePath = Join-Path $PSScriptRoot "monitoring/alertmanager/alertmanager.yml.template"
$OutputPath = Join-Path $PSScriptRoot "monitoring/alertmanager/alertmanager.yml"

if (Test-Path $TemplatePath) {
    $Config = Get-Content -Raw -Path $TemplatePath
    $Config = $Config.Replace("TELEGRAM_BOT_TOKEN_PLACEHOLDER", $TelegramToken)
    $Config = $Config.Replace("TELEGRAM_CHAT_ID_PLACEHOLDER", $TelegramChatId)
    # Ensure the parent directory exists
    $ParentDir = Split-Path $OutputPath
    if (-not (Test-Path $ParentDir)) {
        New-Item -ItemType Directory -Force -Path $ParentDir | Out-Null
    }
    Set-Content -Path $OutputPath -Value $Config
} else {
    Write-Warning "Alertmanager configuration template not found!"
}

# 4. Spin up the containers
Write-Host "Spinning up Docker containers..." -ForegroundColor Green
docker compose -p $ProjectName up -d

Write-Host "`nStack deployed successfully! 🎉" -ForegroundColor Green
Write-Host "Access URLs:"
Write-Host "- Web App:      http://localhost:$NginxPort" -ForegroundColor Cyan
Write-Host "- Grafana:      http://localhost:$GrafanaPort" -ForegroundColor Cyan
Write-Host "- Prometheus:   http://localhost:$PrometheusPort" -ForegroundColor Cyan
Write-Host "- WireGuard UI: http://localhost:$WireguardUiPort" -ForegroundColor Cyan
Write-Host "`nWireGuard configurations can be managed via the Web UI!" -ForegroundColor Yellow
