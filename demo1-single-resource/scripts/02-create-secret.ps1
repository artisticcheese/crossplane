<#
Loads Azure service principal credentials into the cluster as a Secret,
for the Azure ProviderConfig to reference. Does NOT create a service
principal — point it at one that already exists.

Only the client secret is ever kept in an environment variable
($env:AZURE_CLIENT_SECRET, set by set-env.ps1 — gitignored). The
non-secret identifiers (clientId, tenantId, subscriptionId, endpoint
URLs) live in azure-sp-config.json (also gitignored, but contains no
secret material) next to this script's parent folder.

Never run this on shared screen/recording — do it before the talk.
#>
param(
    [string]$ConfigFile = (Join-Path $PSScriptRoot "..\azure-sp-config.json")
)
$ErrorActionPreference = "Stop"

if (-not (Test-Path $ConfigFile)) {
    Write-Error "Config file not found: $ConfigFile (copy azure-sp-config.example.json to azure-sp-config.json and fill in your SP's non-secret identifiers)"
    exit 1
}
if (-not $env:AZURE_CLIENT_SECRET) {
    Write-Error "Set `$env:AZURE_CLIENT_SECRET first (see set-env.example.ps1)"
    exit 1
}

$config = Get-Content -Raw $ConfigFile | ConvertFrom-Json
$config.PSObject.Properties.Remove('_comment')
$config | Add-Member -NotePropertyName clientSecret -NotePropertyValue $env:AZURE_CLIENT_SECRET -Force
$credsJson = $config | ConvertTo-Json -Compress

kubectl create namespace crossplane-system --dry-run=client -o yaml | kubectl apply -f -

# Written briefly to a temp file because kubectl --from-file needs a real
# path (no stdin support) — the file is removed immediately after use, and
# only its path (never the secret value) ever appears on the command line.
$tempFile = Join-Path $env:TEMP "azure-creds-$([guid]::NewGuid()).json"
try {
    Set-Content -Path $tempFile -Value $credsJson -NoNewline
    kubectl create secret generic azure-creds `
      -n crossplane-system `
      --from-file=creds=$tempFile `
      --dry-run=client -o yaml | kubectl apply -f -
}
finally {
    Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
}

Write-Host "Secret 'azure-creds' created in namespace crossplane-system."
