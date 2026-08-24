# Applies team-b's own XPrivateStorage instance. Run
# 02-apply-network-stack.ps1 first — this script only creates team-b's
# namespace and instantiates the type the platform team already defined.
#
# Don't run this alongside team-a's instance still being up: both share
# the same fixed-name PrivateDNSZone (see the caveat in
# crossplane/composition.yaml), so the second one to apply will fail
# trying to recreate it. Tear down team-a's instance first, or only
# present one team live.
$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$teamsDir = Join-Path $scriptDir "..\teams"

kubectl create namespace team-b --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f (Join-Path $teamsDir "team-b\xr.yaml")
kubectl wait --for=condition=Ready xprivatestorage/team-b-storage -n team-b --timeout=300s
