$ErrorActionPreference = "Stop"

# Clean up stale kubectl port-forwards from previous runs
Write-Host "Cleaning up stale port-forwards..."

Get-CimInstance Win32_Process -Filter "name = 'kubectl.exe'" |
    Where-Object { $_.CommandLine -like '*port-forward*' } |
    Where-Object {
        $_.CommandLine -like '*svc/jaeger*' -or
        $_.CommandLine -like '*svc/otel-collector*' -or
        $_.CommandLine -like '*svc/keycloak*' -or
        $_.CommandLine -like '*svc/envoy*' -or
        $_.CommandLine -like '*svc/kong*'
    } |
    ForEach-Object {
        Write-Host "Stopping stale port-forward: $($_.CommandLine)"
        Stop-Process -Id $_.ProcessId -Force
    }
Write-Host "Deleting PoC namespaces..."
kubectl delete namespace apim gateway authorization app identity observability --ignore-not-found=true

Write-Host "Clean complete."
