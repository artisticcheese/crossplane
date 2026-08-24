# Demo 2: a more involved deployment

Matches slide 13 ("A More Involved Deployment") and slide 14 ("Why XRs &
XRDs?"). A private-by-default storage account, virtual network, private
DNS zone, and a private endpoint — all created and wired together from
**one namespaced XR**, no Claim.

```
Virtual Network ─▶ Subnet ─▶ Private Endpoint ─▶ Storage Account
                                    │
                                    ▼
                          Private DNS Zone + Zone Group
        (resolves the storage account's private FQDN to the
         endpoint's private IP inside the VNet)
```

Resources composed: `VirtualNetwork`, `Subnet`, `Account` (storage),
`PrivateDNSZone`, `PrivateDNSZoneVirtualNetworkLink`, `PrivateEndpoint`.
The "PrivateDNSZoneGroup" the diagram calls out is a block nested inside
`PrivateEndpoint` (`spec.forProvider.privateDnsZoneGroup`), not a
separate CRD — Azure itself models it as a sub-resource of the private
endpoint, so that's how it's represented here too.

The storage account here is a **fresh account this XR creates itself**,
private from the moment it's provisioned — a deliberate contrast with
demo 1's `demosa001`, which is public until something else changes it.
The two coexist; this demo doesn't touch demo 1's account at all.

**Prerequisite:** demo 1 already run — cluster has Crossplane installed,
`provider-azure-storage` healthy, the `azure-creds` Secret / `default`
ProviderConfig in place, and `demo-rg` created in the `team-a` namespace.
This demo reuses the resource group only.

**Unlike the original version of this demo** (independently-applied
Managed Resources wired with `matchLabels`), this now shows a realistic
platform/consumer split across two directories:

- `crossplane/` — **owned by the platform team.** `xrd.yaml` (the
  namespaced `CompositeResourceDefinition`) and `composition.yaml` (the
  `Composition` running a `function-patch-and-transform` →
  `function-auto-ready` pipeline). Defines the `XPrivateStorage` type
  once; never touched by consuming teams.
- `teams/` — **owned by each consuming team.** `team-a/xr.yaml` and
  `team-b/xr.yaml` are the only things each team applies: a few lines of
  spec (`location`, `storageAccountName`), each into its own namespace
  (`team-a`, `team-b`). Same Composition, fully isolated resources —
  that isolation is *why* `storageAccountName` is a spec field instead
  of hardcoded: it now flows into the composed Account and
  PrivateEndpoint's names, so two teams' instances never collide there.

Because Crossplane sets a controller reference on everything it
composes, resources composed by the *same* XR wire to each other with
the simpler `matchControllerRef: true` — the same mechanism demo 1's
`ResourceGroup`/`Account` pair already uses. `matchLabels` only remains
for the one selector that reaches *outside* this XR, to demo 1's
independently-applied `ResourceGroup` (shared by both teams' instances).

## Before you go on stage

```powershell
.\scripts\01-install-network-provider.ps1
.\scripts\02-apply-network-stack.ps1
.\scripts\03-apply-team-a.ps1
```

The first script installs `provider-azure-network` plus the two
Composition Functions the pipeline needs. The second (platform team)
applies `xrd.yaml` then `composition.yaml` — defines the type, creates
nothing yet. The third (team-a, self-service) creates the `team-a`
namespace and applies `teams\team-a\xr.yaml` — six composed resources.

`03-apply-team-b.ps1` does the same for team-b, but **don't run it while
team-a's instance is still up** — see the Private DNS zone caveat below.

## During the talk (safe to run live)

```powershell
kubectl get xprivatestorage -n team-a -w
kubectl get virtualnetwork,subnet,privatednszone,privatednszonevirtualnetworklink,privateendpoint,account -n team-a -w
```

Wait for everything to show `READY: True`. Worth narrating as you go:
the storage account was created with `publicNetworkAccessEnabled: false`
from the start — it's only reachable through the private endpoint, over
the VNet, resolved via the linked private DNS zone. The Function
pipeline decided *what* to create from one XR; the resources still
resolve *how* they connect via the same selector mechanism as demo 1 —
internally via `matchControllerRef`, since everything here shares this
XR as its controller.

```powershell
kubectl describe privateendpoint pe-demosa2001 -n team-a
```

To show a second team self-serving the same type, tear down team-a's
instance first (see cleanup below), then run `03-apply-team-b.ps1` and
repeat the above with `-n team-b` / `demosb2001`.

## After the talk — clean up

```powershell
kubectl delete -f teams\team-a\xr.yaml     # or teams\team-b\xr.yaml
kubectl delete -f crossplane\composition.yaml
kubectl delete -f crossplane\xrd.yaml
```

Removes the XR (and everything it composed), the Composition, and the
XRD. (Leave `demosa001` and `demo-rg` for demo 1's own cleanup, or
delete them too if you're tearing everything down.)

## Before you present — verify these details

- **API versions**: several of these CRDs' `v1beta1` schema is flagged
  deprecated as of provider release v2.6.0 (still present and
  functional in v2.7.0, which this demo pins). Run
  `kubectl explain privateendpoint.network.azure.upbound.io.spec.forProvider`
  (and the same for the other kinds) once the provider is installed, to
  confirm the field names below still match before you're on stage.
- **Private DNS zone name**: `privatelink.blob.core.windows.net` is not
  a placeholder — Azure's private-link DNS integration for Blob Storage
  specifically depends on that exact zone name to auto-resolve. Because
  it's fixed, it's the one name `storageAccountName` can't parameterize
  away: only one team's instance can compose it at a time. Team-a's
  instance must be torn down before applying team-b's, or vice versa.
- **Function versions**: `functions.yaml` pins
  `function-patch-and-transform:v0.10.9` and
  `function-auto-ready:v0.7.0` — the latest tagged releases of each as of
  this demo's last verification pass. Check
  https://github.com/crossplane-contrib/function-patch-and-transform/releases
  and https://github.com/crossplane-contrib/function-auto-ready/releases
  for anything newer before you're on stage.
