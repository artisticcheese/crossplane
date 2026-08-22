# Copy this file to set-env.ps1 (gitignored) and fill in the real value.
# Never commit set-env.ps1 — only set-env.example.ps1 (this file) is tracked.
#
# Only the service principal's client secret (password) goes here. The
# non-secret identifiers (clientId, tenantId, subscriptionId, endpoint
# URLs) go in azure-sp-config.json instead — see
# azure-sp-config.example.json.
$env:AZURE_CLIENT_SECRET = '<paste-the-service-principal-client-secret-here>'
