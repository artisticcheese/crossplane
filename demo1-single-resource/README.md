# Live demo: Install → onboard Azure → first resources

Matches slides 10-12 of the deck ("Installing Crossplane" /
"Onboarding the Azure Provider" / "Your First Resources"). Walks through
installing Crossplane, onboarding an Azure provider, and applying a
namespaced Managed Resource directly — no Claim, per Crossplane v2 —
without ever putting a secret in git or on screen.

Assumes you already have: a running Kubernetes cluster (`kubectl` pointed
at it) and an existing Azure service principal.

## Prerequisites

- `kubectl`, `helm`, `az` CLI installed and on PATH
- A working `kubectl` context for your cluster
- The service principal's identifiers (clientId, tenantId,
  subscriptionId) and its client secret (from an existing
  `az ad sp create-for-rbac`)
- PowerShell 7+ (`pwsh`)

## Before you go on stage (do this in private, not on shared screen)

```powershell
.\scripts\01-install-crossplane.ps1
kubectl apply -f crossplane\provider.yaml
kubectl wait --for=condition=Healthy provider/provider-azure-storage --timeout=180s

Copy-Item azure-sp-config.example.json azure-sp-config.json   # first time only, then fill in clientId/tenantId/subscriptionId
Copy-Item set-env.example.ps1 set-env.ps1                       # first time only, then fill in the client secret
. .\set-env.ps1
.\scripts\02-create-secret.ps1

kubectl create namespace team-a --dry-run=client -o yaml | kubectl apply -f -
```

`02-create-secret.ps1` does not create a service principal — it merges
two things and loads the result into the cluster as the `azure-creds`
Kubernetes Secret (matching slide 11's `secretRef.name`):

- **`azure-sp-config.json`** — the non-secret identifiers (clientId,
  tenantId, subscriptionId, endpoint URLs). Gitignored, but contains no
  secret material — only `azure-sp-config.example.json` is tracked.
- **`$env:AZURE_CLIENT_SECRET`** — *only* the client secret/password,
  set by `set-env.ps1` (gitignored — only `set-env.example.ps1` is
  tracked). This is the one genuinely sensitive value, and it's the only
  thing that ever touches an environment variable.

The merged JSON is briefly written to a temp file only because
`kubectl --from-file` requires a real path, and that file is deleted
immediately after use — its content never appears as a command-line
argument, so it won't show up in your PowerShell history either.

Once you're done for the day, clear the variable from your shell:

```powershell
Remove-Item Env:\AZURE_CLIENT_SECRET
```

A different config file path may be passed for one-off use:
`.\scripts\02-create-secret.ps1 -ConfigFile C:\path\to\azure-sp-config.json`

Verify the secret exists but never print its contents on screen:

```powershell
kubectl get secret azure-creds -n crossplane-system
```

**Talking point (from slide 11):** Workload Identity removes the need for
a long-lived service principal secret entirely when running in AKS — this
demo uses a secret because it targets an arbitrary/local cluster, but
it's worth naming the AKS-native alternative live.

## During the talk (safe to run live)

```powershell
kubectl apply -f crossplane\provider-config.yaml
kubectl apply -f crossplane\resources.yaml
kubectl get resourcegroup,account -n team-a -w
```

Wait for both to show `READY: True`, then optionally show them in the
Azure Portal or:

```powershell
az group show --name demo-rg
```

To land the "continuous reconciliation" point live: delete either object
and watch Crossplane recreate it to match spec.

```powershell
kubectl delete account demosa001 -n team-a
kubectl get account demosa001 -n team-a -w
```

## After the talk — clean up

```powershell
kubectl delete -f crossplane\resources.yaml
kubectl delete secret azure-creds -n crossplane-system
Remove-Item Env:\AZURE_CLIENT_SECRET
```

## Why this is safe to demo live

- Only the client secret ever lives in an environment variable — the
  identifiers around it (`azure-sp-config.json`) aren't secret, so
  there's less to protect and less that could accidentally leak the
  wrong thing.
- `set-env.ps1` and `azure-sp-config.json` are both gitignored — only
  their `*.example.*` templates, which have no real values, are tracked.
- The only things that get committed are references (Secret **name**,
  namespace, key) — never values.
- Secret creation happens before you're on stage, reading the secret from
  an environment variable into a briefly-lived temp file (not typed
  literally, not `--from-literal`), so the value never appears in
  PowerShell history or on screen.

## Before you present — verify this specific detail

`crossplane/resources.yaml` uses `resourceGroupNameSelector.matchControllerRef:
true` on the `Account`, exactly as shown on slide 12. That selector
normally matches a resource sharing the same controller/owner reference
(e.g. objects created by the same Composition) — since these two objects
are applied directly with no XR owning either one, do a dry run before
the talk to confirm it resolves as expected on your provider version. If
it doesn't, fall back to an explicit reference:

```yaml
resourceGroupNameRef:
  name: demo-rg
```

## A note on execution policy

If running `.ps1` scripts is blocked on your machine, either run this
session with a relaxed policy or invoke the file directly:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\01-install-crossplane.ps1
```
