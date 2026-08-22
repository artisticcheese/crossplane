# Demo 2: a more involved deployment

Matches slide 13 ("A More Involved Deployment"). A virtual network,
storage account, private DNS zone, and a private endpoint — wired
together with resource selectors, all namespaced (one team's network
stack per namespace).

```
Virtual Network ─▶ Subnet ─▶ Private Endpoint ─▶ Storage Account
                                    │
                                    ▼
                          Private DNS Zone + Zone Group
        (resolves the storage account's private FQDN to the
         endpoint's private IP inside the VNet)
```

Resources involved: `VirtualNetwork`, `Subnet`, `Account`,
`PrivateEndpoint`, `PrivateDNSZone`, `PrivateDNSZoneVirtualNetworkLink`.
The "PrivateDNSZoneGroup" the diagram calls out is a block nested inside
`PrivateEndpoint` (`spec.forProvider.privateDnsZoneGroup`), not a
separate CRD — Azure itself models it as a sub-resource of the private
endpoint, so that's how it's represented here too.

**Prerequisite:** demo 1 already run — cluster has Crossplane installed,
`provider-azure-storage` healthy, the `azure-creds` Secret / `default`
ProviderConfig in place, and `demo-rg` / `demosa001` created in the
`team-a` namespace. This demo reuses all of that.

**Unlike demo 1**, which uses the exact `matchControllerRef` selector
shown on slide 12, everything here is wired with `matchLabels` instead —
a selector that doesn't depend on the resources sharing a controller
owner, which independently-applied objects like these don't. Each
manifest carries a `demo.crossplane.io/stack: team-a` /
`demo.crossplane.io/role: <role>` label pair that downstream resources
select against.

## Before you go on stage

```powershell
.\scripts\01-install-network-provider.ps1
.\scripts\02-apply-network-stack.ps1
```

This installs `provider-azure-network`, then applies the VNet, Subnet,
Private DNS Zone, VNet Link, the updated (now-private) storage Account,
and finally the Private Endpoint that ties them together.

## During the talk (safe to run live)

```powershell
kubectl get virtualnetwork,subnet,privatednszone,privatednszonevirtualnetworklink,privateendpoint,account -n team-a -w
```

Wait for everything to show `READY: True`. Worth narrating as you go:
the storage account (`demosa001`) now has `publicNetworkAccessEnabled:
false` — it's only reachable through the private endpoint, over the
VNet, resolved via the linked private DNS zone. None of that wiring was
typed as a literal Azure resource ID anywhere — it's all resolved live by
label selectors.

```powershell
kubectl describe privateendpoint pe-demosa001 -n team-a
```

## After the talk — clean up

```powershell
kubectl delete -f crossplane\private-endpoint.yaml
kubectl delete -f crossplane\private-dns-zone-vnet-link.yaml
kubectl delete -f crossplane\private-dns-zone.yaml
kubectl delete -f crossplane\subnet.yaml
kubectl delete -f crossplane\virtual-network.yaml
```

(Leave `demosa001` and `demo-rg` for demo 1's own cleanup, or delete them
too if you're tearing everything down.)

## Before you present — verify these details

- **API versions**: several of these CRDs' `v1beta1` schema is flagged
  deprecated as of provider release v2.6.0 (still present and
  functional in v2.7.0, which this demo pins). Run
  `kubectl explain privateendpoint.network.azure.upbound.io.spec.forProvider`
  (and the same for the other kinds) once the provider is installed, to
  confirm the field names below still match before you're on stage.
- **Private DNS zone name**: `privatelink.blob.core.windows.net` is not
  a placeholder — Azure's private-link DNS integration for Blob Storage
  specifically depends on that exact zone name to auto-resolve.
