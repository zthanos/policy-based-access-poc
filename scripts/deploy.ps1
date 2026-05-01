$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

Write-Host "Building REST API image..."
docker build -t authz-poc-rest-api:latest .\app

Write-Host "Applying Kubernetes manifests..."
kubectl apply -f .\k8s\namespaces.yaml
kubectl apply -f .\k8s\observability
kubectl apply -f .\k8s\keycloak
kubectl apply -f .\k8s\opa
kubectl apply -f .\k8s\app
kubectl apply -f .\k8s\envoy
kubectl apply -f .\k8s\apim

Write-Host "Restarting ConfigMap-backed services..."
kubectl rollout restart deployment/keycloak -n identity
kubectl rollout restart deployment/opa -n authorization

Write-Host "Waiting for deployments..."
kubectl rollout status deployment/jaeger -n observability --timeout=120s
kubectl rollout status deployment/otel-collector -n observability --timeout=120s
kubectl rollout status deployment/keycloak -n identity --timeout=240s
kubectl rollout status deployment/opa -n authorization --timeout=120s
kubectl rollout status deployment/rest-api -n app --timeout=120s
kubectl rollout status deployment/envoy -n gateway --timeout=120s
kubectl rollout status deployment/kong -n apim --timeout=120s

Write-Host ""
Write-Host "Deployment complete."
Write-Host "Run '.\scripts\test.ps1' or 'make test' to execute the scenarios."
