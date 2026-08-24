# Applies team-a's own XPrivateStorage instance. Run
# 02-apply-network-stack.ps1 first — this script only creates team-a's
# namespace and instantiates the type the platform team already defined.
$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$teamsDir = Join-Path $scriptDir "..\teams"

kubectl create namespace team-a --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f (Join-Path $teamsDir "team-a\xr.yaml")
kubectl wait --for=condition=Ready xprivatestorage/team-a-storage -n team-a --timeout=300s
