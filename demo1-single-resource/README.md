# Live demo: Install → onboard Azure → first resources

Matches slides 11-13 of the deck ("Installing Crossplane" /
"Onboarding the Azure Provider" / "Your First Resources"). Walks through
installing Crossplane, onboarding an Azure provider, and applying a
namespaced Managed Resource directly — no Claim, per Crossplane v2 —
without ever putting a secret in git or on screen.

Both resources come from the namespaced `.m.` API groups
(`azure.m.upbound.io`, `storage.azure.m.upbound.io`) — the v2 shape that
accepts `metadata.namespace`. Credentials are a `ClusterProviderConfig`
named `default`, which is what a Managed Resource with no
`providerConfigRef` falls back to, so neither object needs one.

**[`../demo-run-of-show.ps1`](../demo-run-of-show.ps1) is the demo, and it
holds every manifest.** This folder has no YAML of its own — the script
carries each manifest inline as a here-string and pipes it to `kubectl
apply -f -`, so there is exactly one copy of every resource and nothing
that can drift out of sync with what's on the slides.

Every `#region` under the "Demo 1" banner corresponds to a step below,
labelled `[PRIVATE]`, `[LIVE]`, or `[DESTRUCTIVE]` so you can tell at a
glance what is safe on a shared screen. Open it in VS Code, collapse the
regions in the gutter, and step through with F8 (Run Selection). This
README is the narrative: why each step exists and what to say while it
runs.

Assumes only: a running Kubernetes cluster with `kubectl` pointed at it.
You do **not** need an existing service principal — the run-of-show
creates its own.

## Prerequisites

- `kubectl`, `helm`, `az` CLI installed and on PATH
- A working `kubectl` context for your cluster
- PowerShell 7+ (`pwsh`)
- Azure rights to create an app registration / service principal (e.g.
  Application Administrator) and to assign Contributor at the
  subscription scope (e.g. Owner or User Access Administrator)

## Before you go on stage (do this in private, not on shared screen)

Run these regions of the walkthrough, in order:

| Region | What it does |
|---|---|
| `0. Session setup` | Sets `$ProviderVersion` and the storage account names. Everything downstream reads them, so run it first. |
| `Demo 1 - [PRIVATE] Slide 11 - Installing Crossplane` | `helm upgrade --install` of the control plane. Slow — the pull and rollout outlast an audience's patience. |
| `Demo 1 - [PRIVATE] Slide 12 - Onboarding the Azure Provider` | Applies the `Provider` and waits for Healthy. |
| `Demo 1 - [PRIVATE] Credentials` | Creates the service principal *and* the Secret in one pass — no pasted secret, no placeholder clientId to fill in first. |
| `Demo 1 - [PRIVATE] Preflight check` | Server-side dry run of the two Managed Resources, plus the `team-a` namespace. |

What that region does, in order:

1. Creates a **brand-new Azure AD app registration + service principal**
   named `crossplane-demo-<timestamp>`, scoped Contributor on the current
   subscription — created with `--create-password false`, then given a
   secret with a **4-hour expiry** (`az ad app credential reset
   --end-date`) rather than az's default one year.
2. Assembles the credential document **in memory** — clientId, tenantId,
   subscriptionId and endpoint URLs, none of them secret. It prints
   those, which is safe; nothing is written to disk.
3. Adds the client secret to that in-memory copy, base64-encodes it, and
   pipes a Secret manifest to `kubectl apply` over **stdin** — so the
   value never becomes a command-line argument and never lands in your
   PowerShell history. That produces `azure-creds` in `crossplane-system`,
   matching slide 12's `secretRef.name`.
4. Clears `$DemoAdClientSecret` from the session immediately afterwards.

Cleanup later runs `az ad sp delete`, so the service principal is
actively removed rather than left to expire.

Then create the namespace:

```powershell
kubectl create namespace team-a --dry-run=client -o yaml | kubectl apply -f -
```

Verify the secret exists but never print its contents on screen:

```powershell
kubectl get secret azure-creds -n crossplane-system
```

**Talking point (from slide 12):** Workload Identity removes the need for
a long-lived service principal secret entirely when running in AKS — this
demo uses a secret because it targets an arbitrary/local cluster, but
it's worth naming the AKS-native alternative live.

## During the talk (safe to run live)

Region `Demo 1 - [LIVE] Slide 13 - Your First Resources`. It applies the
`ClusterProviderConfig` and the two Managed Resources, then shows what
landed in the namespace:

```powershell
$DemoResourcesYaml | kubectl apply -f - -n team-a
kubectl get resourcegroups.azure.m.upbound.io,accounts.storage.azure.m.upbound.io -n team-a
```

Wait for both to show `READY: True` — the walkthrough's `Wait-ForReady`
helper polls for you, since `kubectl get -w` never returns in a
stepped-through script. Then optionally show them in the Azure Portal
or:

```powershell
az group show --name demo-rg
```

To land the "continuous reconciliation" point live: delete either object
and watch Crossplane recreate it to match spec.

Region `Demo 1 - [LIVE] The reconciliation moment`:

```powershell
kubectl delete accounts.storage.azure.m.upbound.io $Demo1StorageAccount -n team-a
Wait-ForReady -Resource "accounts.storage.azure.m.upbound.io/$Demo1StorageAccount" -Namespace team-a
```

## After the talk — clean up

Run the walkthrough's `[DESTRUCTIVE] Cleanup` region. It deletes demo 2's
objects first (so Crossplane tears down what it composed), then demo 1's
Managed Resources and Secret, then the service principal itself:

```powershell
$DemoResourcesYaml | kubectl delete -f - --ignore-not-found
kubectl delete secret azure-creds -n crossplane-system --ignore-not-found
az ad sp delete --id $DemoAdAppId
```

## Why this is safe to demo live

- The service principal is **created for this demo and deleted after it**
  — scoped to one subscription, with a 4-hour secret expiry, and removed
  outright by `az ad sp delete` at cleanup. Nothing long-lived is
  involved, so there is no standing credential to leak.
- The client secret never touches disk, a command line, or an
  environment variable — it lives in one session variable, goes into the
  cluster Secret over stdin, and is cleared immediately.
- Nothing credential-shaped is written to disk at all. The identifiers
  and the secret are assembled in memory and handed to `kubectl` over
  stdin, so there is no config file to gitignore and no artifact left
  behind after the talk.
- The only things committed to this repo are references (Secret
  **name**, namespace, key) — never values.

## Why the kubectl commands spell out the API group

A Crossplane v2 provider registers every kind twice: once cluster-scoped
under the v1 group (`accounts.storage.azure.upbound.io`) and once
namespaced under the v2 `.m.` group
(`accounts.storage.azure.m.upbound.io`). Both CRDs claim the short name
`account`, so `kubectl get account -n team-a` may resolve to the
cluster-scoped CRD and quietly return nothing. Qualifying the group
avoids that on stage.

## Before you present — verify this specific detail

`$DemoResourcesYaml` in the walkthrough uses
`resourceGroupNameSelector.matchControllerRef: true` on the `Account`,
exactly as shown on slide 13. That selector
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
