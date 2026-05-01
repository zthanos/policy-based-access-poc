$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Test-PortOpen {
    param([int] $Port)

    $client = New-Object Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect("127.0.0.1", $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne(200)) {
            return $false
        }
        $client.EndConnect($async)
        return $true
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

function Test-JaegerUi {
    try {
        $response = Invoke-WebRequest -UseBasicParsing http://localhost:16686 -TimeoutSec 3
        return $response.StatusCode -eq 200 -and $response.Content -match "<title>Jaeger UI</title>"
    } catch {
        return $false
    }
}

function Start-PortForward {
    param(
        [string] $Name,
        [string] $Namespace,
        [string] $Service,
        [int] $LocalPort,
        [int] $RemotePort,
        [scriptblock] $ReadyCheck = $null
    )

    $isReady = if ($ReadyCheck) { & $ReadyCheck } else { Test-PortOpen -Port $LocalPort }

    if ($isReady) {
        Write-Host "$Name already reachable on localhost:$LocalPort"
        return $null
    }

    Write-Host "Starting $Name port-forward localhost:$LocalPort -> $Service`:$RemotePort"
    $process = Start-Process kubectl `
        -ArgumentList @("port-forward", "-n", $Namespace, "svc/$Service", "$LocalPort`:$RemotePort") `
        -WindowStyle Hidden `
        -PassThru

    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 250
        $isReady = if ($ReadyCheck) { & $ReadyCheck } else { Test-PortOpen -Port $LocalPort }
        if ($isReady) {
            return $process
        }
        if ($process.HasExited) {
            throw "$Name port-forward exited before localhost:$LocalPort became reachable."
        }
    }

    throw "$Name port-forward did not become reachable on localhost:$LocalPort."
}

function Get-PythonCommand {
    if ($env:PYTHON -and (Get-Command $env:PYTHON -ErrorAction SilentlyContinue)) {
        return @($env:PYTHON)
    }

    $python = Get-Command python -ErrorAction SilentlyContinue
    if ($python) {
        return @($python.Source)
    }

    $py = Get-Command py -ErrorAction SilentlyContinue
    if ($py) {
        return @($py.Source, "-3")
    }

    return $null
}

function Invoke-Client {
    Write-Host "Running the traced external client with Docker."
    docker run --rm `
        -v "$root\client:/client:ro" `
        -e KEYCLOAK_URL=http://host.docker.internal:8031 `
        -e KEYCLOAK_HOST_HEADER=localhost:8031 `
        -e API_URL=http://host.docker.internal:10000 `
        -e OTEL_EXPORTER_OTLP_ENDPOINT=http://host.docker.internal:4318/v1/traces `
        python:3.12-slim `
        sh -c "pip install --quiet -r /client/requirements.txt && python /client/client.py"
}

$forwards = @()
$keepAliveForwards = @()
$clientExitCode = 0
try {
    $keycloakForward = Start-PortForward -Name "Keycloak" -Namespace "identity" -Service "keycloak" -LocalPort 8031 -RemotePort 8031
    if ($keycloakForward) { $forwards += $keycloakForward }

    $gatewayForward = Start-PortForward -Name "Envoy" -Namespace "gateway" -Service "envoy" -LocalPort 10080 -RemotePort 80
    if ($gatewayForward) { $forwards += $gatewayForward }

    $apimForward = Start-PortForward -Name "Kong APIM Simulator" -Namespace "apim" -Service "kong" -LocalPort 10000 -RemotePort 8000
    if ($apimForward) { $forwards += $apimForward }

    $collectorForward = Start-PortForward -Name "OpenTelemetry Collector" -Namespace "observability" -Service "otel-collector" -LocalPort 4318 -RemotePort 4318
    if ($collectorForward) { $forwards += $collectorForward }

    $jaegerForward = Start-PortForward -Name "Jaeger" -Namespace "observability" -Service "jaeger" -LocalPort 16686 -RemotePort 16686 -ReadyCheck { Test-JaegerUi }
    if ($jaegerForward) { $keepAliveForwards += $jaegerForward }

    Write-Host ""
    Write-Host "APIM Simulator: http://localhost:10000"
    Write-Host "Envoy debug:    http://localhost:10080"
    Write-Host "Jaeger UI: http://localhost:16686"
    Write-Host ""
    Invoke-Client
    $clientExitCode = $LASTEXITCODE

    Write-Host "Waiting briefly for trace export to settle..."
    Start-Sleep -Seconds 3

    Write-Host ""
    Write-Host "Jaeger UI remains open at http://localhost:16686"
    Write-Host "Close it later with: Get-CimInstance Win32_Process -Filter ""name = 'kubectl.exe'"" | Where-Object { `$_.CommandLine -like '*svc/jaeger*16686*' } | ForEach-Object { Stop-Process -Id `$_.ProcessId -Force }"
} finally {
    foreach ($forward in $forwards) {
        if (-not $forward.HasExited) {
            Stop-Process -Id $forward.Id -Force
        }
    }
}

if ($clientExitCode -ne 0) {
    exit $clientExitCode
}
