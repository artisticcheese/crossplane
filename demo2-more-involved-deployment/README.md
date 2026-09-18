# Demo 2: a more involved deployment

Matches slide 14 ("A More Involved Deployment") and slide 5 ("Why XRs &
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

Resources composed: `ResourceGroup`, `VirtualNetwork`, `Subnet`,
`Account` (storage), `PrivateDNSZone`,
`PrivateDNSZoneVirtualNetworkLink`, `PrivateEndpoint` — seven, all from
the namespaced `.m.` API groups, and all created in the XR's own
namespace because the XRD declares `scope: Namespaced`.

Every cross-resource reference is `matchControllerRef: true`, which
matches only resources composed by the *same* XR. There is no
`matchLabels` and no reach into another namespace, so two teams' stacks
share no object at all.
The "PrivateDNSZoneGroup" the diagram calls out is a block nested inside
`PrivateEndpoint` (`spec.forProvider.privateDnsZoneGroup`), not a
separate CRD — Azure itself models it as a sub-resource of the private
endpoint, so that's how it's represented here too.

The storage account here is a **fresh account this XR creates itself**,
private from the moment it's provisioned — a deliberate contrast with
demo 1's `demosa001`, which is public until something else changes it.
The two coexist; this demo doesn't touch demo 1's account at all.

## The platform/consumer boundary — the point of this demo

The XRD schema is the whole contract, and it has **three fields**:

| Field | Who decides |
|---|---|
| `location` | consumer |
| `storageAccountName` | consumer (must be globally unique in Azure) |
| `environment` | consumer picks `Production` or `Development` off a list |

Everything else is the platform team's, written into the Composition's
bases with no patch pointing at it: `accountTier: Standard`,
`accountReplicationType: LRS`, `publicNetworkAccessEnabled: false`, the
VNet address space, the subnet prefix, the private-link wiring, the DNS
zone name. A consumer cannot ask for Premium, cannot ask for GRS, and
cannot reopen the public endpoint — **not because a policy engine blocks
it, but because there is no field in the API to put it in.** `kubectl
apply` fails outright on an unknown field rather than dropping it
silently, so an XR that tries is refused.

`environment` is the sharpest version of this. The consumer states an
intent; the platform team decides what it buys. Today that mapping is
blob soft-delete retention — `Production` → 30 days, `Development` → 1
day — done with a `map` transform in the Composition. Change those two
numbers once and every team's stack moves, with no consumer YAML edited.
The consumer never names a number, and can't request one that isn't on
the list.

**Prerequisite:** demo 1 already run — cluster has Crossplane installed,
`provider-azure-storage` healthy, the `azure-creds` Secret / `default`
`ClusterProviderConfig` in place, and `demo-rg` created in the `team-a` namespace.
That is all it needs from demo 1 — it shares no Azure resource with it.
Each XR composes its own resource group, so `demo-rg` and `demosa001`
are untouched.

**[`../demo-run-of-show.ps1`](../demo-run-of-show.ps1) is the demo, and it
holds every manifest.** This folder has no YAML of its own — each
manifest is inline in the script as a here-string. Run the script top to
bottom in one session: demo 2 reuses the credentials demo 1's regions
created, and its cleanup is in the same Cleanup region.

The demo shows a realistic platform/consumer split, and in the
walkthrough that split is the region boundary:

- **Platform team** — `$Demo2XrdYaml` (the namespaced
  `CompositeResourceDefinition`) and `$Demo2CompositionYaml` (the
  `Composition` running a `function-patch-and-transform` →
  `function-auto-ready` pipeline). Defines the `XPrivateStorage` type
  once; never touched by consuming teams. Two separate regions, so you
  can show the API and its implementation one at a time.
- **Consuming teams** — `$TeamAXrYaml` and `$TeamBXrYaml` are the only
  things each team applies: two lines of spec (`location`,
  `storageAccountName`), each into its own namespace (`team-a`,
  `team-b`). Same Composition, fully isolated resources — that isolation
  is *why* `storageAccountName` is a spec field instead of hardcoded: it
  flows into the composed Account and PrivateEndpoint's names, so two
  teams' instances never collide there.

Because Crossplane sets a controller reference on everything it
composes, resources composed by the *same* XR wire to each other with
the simpler `matchControllerRef: true` — the same mechanism demo 1's
`ResourceGroup`/`Account` pair already uses. `matchLabels` only remains
for the one selector that reaches *outside* this XR, to demo 1's
independently-applied `ResourceGroup` (shared by both teams' instances).

## Before you go on stage

Run these regions of the walkthrough, in order — all under
`Demo 2 - [PRIVATE] Setup`:

| Region | What it does |
|---|---|
| `Install network provider + functions` | `provider-azure-network` (same `$ProviderVersion` as demo 1's storage provider) plus `function-patch-and-transform` and `function-auto-ready`. Crossplane v2 has no built-in patch-and-transform, so the functions are required, not optional. Slow — image pulls. |
| `Apply the platform team's XRD` | Defines the `XPrivateStorage` kind. Creates no infrastructure. |
| `Apply the platform team's Composition` | Implements it. Still creates nothing — it only makes the type usable. |
| `Apply team-a's XR instance` | The one object team-a applies. Seven composed resources; allow several minutes to converge. |

The optional region `Demo 2 - [DESTRUCTIVE + PRIVATE] Optional - a second
team` does the same for team-b, and the two **run side by side** — no
teardown needed. Each XR composes its own resource group, and an Azure
private DNS zone name only has to be unique within its resource group,
so both stacks get their own `privatelink.blob.core.windows.net`.

## During the talk (safe to run live)

Region `Demo 2 - [LIVE] Slide 14`. Show the two-line XR team-a authored
(`$TeamAXrYaml`), the single object they applied, then everything it
produced:

```powershell
kubectl get xprivatestorage -n team-a
kubectl get virtualnetworks.network.azure.m.upbound.io,`
  subnets.network.azure.m.upbound.io,`
  privatednszones.network.azure.m.upbound.io,`
  privatednszonevirtualnetworklinks.network.azure.m.upbound.io,`
  privateendpoints.network.azure.m.upbound.io,`
  accounts.storage.azure.m.upbound.io -n team-a
```

(The groups are spelled out because a v2 provider registers each kind
twice — cluster-scoped under `network.azure.upbound.io` and namespaced
under `network.azure.m.upbound.io` — so the short names are ambiguous.)

Wait for everything to show `READY: True`. Worth narrating as you go:
the storage account was created with `publicNetworkAccessEnabled: false`
from the start — it's only reachable through the private endpoint, over
the VNet, resolved via the linked private DNS zone. The Function
pipeline decided *what* to create from one XR; the resources still
resolve *how* they connect via the same selector mechanism as demo 1 —
internally via `matchControllerRef`, since everything here shares this
XR as its controller.

```powershell
kubectl describe privateendpoints.network.azure.m.upbound.io pe-$Demo2StorageAccount -n team-a
```

To show a second team self-serving the same type, run the `Optional - a
second team` region and repeat the above with `-n team-b` /
`$Demo2StorageAccountTeamB` — team-a's instance can stay up. Worth
putting the two side by side: identical Composition, disjoint resources,
and the only difference the teams wrote is `environment: Production` vs
`Development`. Show that turning into 30-day versus 1-day blob
retention:

```powershell
kubectl get accounts.storage.azure.m.upbound.io $Demo2StorageAccount      -n team-a -o jsonpath='{.spec.forProvider.blobProperties[0].deleteRetentionPolicy[0].days}'
kubectl get accounts.storage.azure.m.upbound.io $Demo2StorageAccountTeamB -n team-b -o jsonpath='{.spec.forProvider.blobProperties[0].deleteRetentionPolicy[0].days}'
```

## After the talk — clean up

The walkthrough's `[DESTRUCTIVE] Cleanup` region does this in the right
order — the XRs first, so Crossplane deletes everything they composed,
then the Composition and the XRD:

```powershell
$TeamAXrYaml          | kubectl delete -f - --ignore-not-found
$TeamBXrYaml          | kubectl delete -f - --ignore-not-found
$Demo2CompositionYaml | kubectl delete -f - --ignore-not-found
$Demo2XrdYaml         | kubectl delete -f - --ignore-not-found
```

The same region continues into demo 1's Managed Resources, the Secret,
and the service principal, so running it once tears down everything.

## Before you present — verify these details

- **API versions**: several of these CRDs' `v1beta1` schema is flagged
  deprecated as of provider release v2.6.0 (still present and functional
  in v2.7.1, the `$ProviderVersion` this demo pins). Run
  `kubectl explain privateendpoints.network.azure.m.upbound.io.spec.forProvider`
  (and the same for the other kinds) once the provider is installed, to
  confirm the field names below still match before you're on stage.
- **Private DNS zone name**: `privatelink.blob.core.windows.net` is not
  a placeholder — Azure's private-link DNS integration for Blob Storage
  specifically depends on that exact zone name to auto-resolve, so it's
  the one name the Composition can't parameterize. That used to force
  one team at a time. It no longer does, because each XR composes its own
  resource group and zone names are unique per resource group rather than
  globally — but it's worth confirming on your subscription before you
  rely on running both teams live.
- **The `environment` → retention mapping**: the Composition patches
  `spec.forProvider.blobProperties[0].deleteRetentionPolicy[0].days` with
  a `map` transform whose values are integers (`Production: 30`,
  `Development: 1`). Confirm the field path and that the integer lands as
  a number on your provider version:
  `kubectl explain accounts.storage.azure.m.upbound.io.spec.forProvider.blobProperties`.
  Note also that `Development` gets the **1-day floor rather than soft
  delete switched off**: azurerm's schema exposes only `days` (minimum 1)
  and omitting the block doesn't disable the policy — it falls back to a
  7-day default
  ([terraform-provider-azurerm#17204](https://github.com/hashicorp/terraform-provider-azurerm/issues/17204)).
  If you want to say "disabled" on stage, say "floored at one day"
  instead, or pick a different platform-owned setting to map.
- **Function versions**: the walkthrough's `Install network provider +
  functions` region pins `function-patch-and-transform:v0.10.9` and
  `function-auto-ready:v0.7.0` — the latest tagged releases of each as of
  this demo's last verification pass. Check
  https://github.com/crossplane-contrib/function-patch-and-transform/releases
  and https://github.com/crossplane-contrib/function-auto-ready/releases
  for anything newer before you're on stage.
