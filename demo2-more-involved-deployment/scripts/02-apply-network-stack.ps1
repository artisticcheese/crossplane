# Applies composition.yaml: one namespaced XR whose Composition Function
# pipeline creates and wires a private-by-default storage account behind
# a VNet -> Subnet -> Private Endpoint, resolved via a Private DNS Zone
# linked to the VNet. Only demo 1's ResourceGroup is reused from outside
# this XR.
$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$crossplaneDir = Join-Path $scriptDir "..\crossplane"

kubectl apply -f (Join-Path $crossplaneDir "composition.yaml")
kubectl wait --for=condition=Ready xprivatestorage/team-a-storage -n team-a --timeout=300s
