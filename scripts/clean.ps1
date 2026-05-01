$ErrorActionPreference = "Stop"

Write-Host "Deleting PoC namespaces..."
kubectl delete namespace apim gateway authorization app identity observability --ignore-not-found=true

Write-Host "Clean complete."
