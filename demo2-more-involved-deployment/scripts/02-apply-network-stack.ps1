# Applies the platform team's half of this demo: xrd.yaml defines the
# namespaced XPrivateStorage kind, composition.yaml implements it with a
# function-patch-and-transform -> function-auto-ready pipeline that wires
# a private-by-default storage account behind a VNet -> Subnet -> Private
# Endpoint, resolved via a Private DNS Zone linked to the VNet. Only
# demo 1's ResourceGroup is reused from outside this XR.
#
# No instance is created here — each consuming team applies their own
# from teams\<team>\xr.yaml via 03-apply-team-a.ps1 / 03-apply-team-b.ps1.
$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$crossplaneDir = Join-Path $scriptDir "..\crossplane"

# Order matters: xrd.yaml defines the XPrivateStorage kind that
# composition.yaml implements.
kubectl apply -f (Join-Path $crossplaneDir "xrd.yaml")
kubectl apply -f (Join-Path $crossplaneDir "composition.yaml")
