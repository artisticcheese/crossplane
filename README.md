# Crossplane Enterprise IaC — live demo materials

Supporting demo for `Crossplane_Enterprise_IaC.pptx`, matching its live
demo section (slides 10-13) exactly. Two demos, run in order against the
same cluster:

1. **[`demo1-single-resource/`](demo1-single-resource/README.md)** —
   slides 10-12: install Crossplane, onboard the Azure storage provider
   with a ProviderConfig backed by a Secret (never committed to git),
   apply a namespaced Managed Resource directly (`ResourceGroup` +
   `Account`) — no Claim, per Crossplane v2.
2. **[`demo2-more-involved-deployment/`](demo2-more-involved-deployment/README.md)**
   — slides 13-14: a private-by-default storage account, virtual
   network, subnet, private DNS zone, and a private endpoint, all
   created and wired together from **one namespaced XR**
   (`XPrivateStorage`) by a `function-patch-and-transform` Composition
   pipeline — a single `kubectl apply`, reusing only demo 1's resource
   group.

Both assume: a Kubernetes cluster is already running, `kubectl` is
pointed at it, PowerShell 7+ is available, and you already have Azure
service principal credentials.

All setup scripts are PowerShell (`.ps1`). See each demo's own README for
the exact run-of-show — what to do privately before the talk versus
what's safe to run live in front of the audience.

No secrets live in this repo. `.gitignore` blocks any credentials/secret
file from ever being staged; committed manifests only ever reference a
Kubernetes Secret by name.
