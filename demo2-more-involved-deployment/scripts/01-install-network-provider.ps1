# Installs the extra provider and the two Composition Functions this
# demo needs on top of demo 1.
$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$crossplaneDir = Join-Path $scriptDir "..\crossplane"

kubectl apply -f (Join-Path $crossplaneDir "provider-azure-network.yaml")
kubectl apply -f (Join-Path $crossplaneDir "functions.yaml")

kubectl wait --for=condition=Healthy provider/provider-azure-network --timeout=180s
kubectl wait --for=condition=Healthy function/function-patch-and-transform --timeout=180s
kubectl wait --for=condition=Healthy function/function-auto-ready --timeout=180s
