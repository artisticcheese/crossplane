# Installs the extra provider this demo needs on top of demo 1.
$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

kubectl apply -f (Join-Path $scriptDir "..\crossplane\provider-azure-network.yaml")
kubectl wait --for=condition=Healthy provider/provider-azure-network --timeout=180s
