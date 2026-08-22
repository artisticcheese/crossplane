# Applies the private-networking stack around demo 1's storage account:
# VNet -> Subnet -> Private Endpoint <-> Storage Account, resolved via a
# Private DNS Zone linked to the VNet.
$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$crossplaneDir = Join-Path $scriptDir "..\crossplane"

kubectl apply -f (Join-Path $crossplaneDir "virtual-network.yaml")
kubectl apply -f (Join-Path $crossplaneDir "subnet.yaml")
kubectl apply -f (Join-Path $crossplaneDir "private-dns-zone.yaml")
kubectl apply -f (Join-Path $crossplaneDir "private-dns-zone-vnet-link.yaml")
kubectl apply -f (Join-Path $crossplaneDir "storage-account-private.yaml")
kubectl apply -f (Join-Path $crossplaneDir "private-endpoint.yaml")
