# Crossplane Enterprise IaC — live demo materials

Supporting demo for `Crossplane_Enterprise_IaC.pptx`, matching its live
demo section (slides 11-14) exactly. Two demos, run in order against the
same cluster:

1. **[`demo1-single-resource/`](demo1-single-resource/README.md)** —
   slides 11-13: install Crossplane, onboard the Azure storage provider
   with a `ClusterProviderConfig` backed by a Secret (never committed to
   git), apply a namespaced Managed Resource directly (`ResourceGroup` +
   `Account`, both from the `.m.` API groups) — no Claim, per
   Crossplane v2.
2. **[`demo2-more-involved-deployment/`](demo2-more-involved-deployment/README.md)**
   — slide 14 (with slide 5 as the rationale): a private-by-default storage account, virtual
   network, subnet, private DNS zone, and a private endpoint, all
   created and wired together from **one namespaced XR**
   (`XPrivateStorage`) by a `function-patch-and-transform` Composition
   pipeline — a single `kubectl apply`, reusing only demo 1's resource
   group.

Both assume: a Kubernetes cluster is already running, `kubectl` is
pointed at it, and PowerShell 7+ is available. You do **not** need an
existing Azure service principal — the demo creates its own, scoped to
one subscription with a 4-hour secret, and deletes it at cleanup.

## Run it from [`demo-run-of-show.ps1`](demo-run-of-show.ps1)

**That single file is the demo, and it holds every manifest.** There is no
YAML anywhere else in this repo: each manifest is written inline in the
script as a here-string and piped to `kubectl apply -f -`. It reads no
external file and writes none, so there is one copy of every resource,
nothing to keep in sync with the slides, and no path to configure —
copy the file anywhere and it runs.

It covers both demos end to end, in order, as a sequence of collapsible
`#region` blocks labelled:

- `[PRIVATE]` — run before you go on stage; not for a shared screen
- `[LIVE]` — safe to run in front of the audience
- `[DESTRUCTIVE]` — deletes cluster or cloud resources

Open it in VS Code, collapse the regions in the editor gutter, and step
through one block at a time with F8 (Run Selection). Each region's name
labels which step produced the output beneath it. There is no path to
set up first — run the `Session setup` region and go.

`kubectl get -w` never returns in a stepped-through script, so every
watch is a `kubectl wait` or the `Wait-ForReady` polling helper, both of
which time out and return.

The `Session setup` region at the top holds the only values worth
changing before a run: `$ProviderVersion` (one tag for the whole Azure
provider family — the in-family storage and network packages must not be
pinned apart) and the three globally-unique storage account names.

Each demo's own README is the narrative reference: why each step exists,
what to say while it runs, and which regions to run when. The manifests
themselves live in the script and only there.

**Everything here is Crossplane v2.** Every Managed Resource uses a
namespaced `.m.` API group (`azure.m.upbound.io`,
`storage.azure.m.upbound.io`, `network.azure.m.upbound.io`), the XRD is
`apiextensions.crossplane.io/v2` with `scope: Namespaced`, and there are
no Claims anywhere. A v2 provider still registers the cluster-scoped v1
groups alongside the namespaced ones, so `kubectl` short names like
`account` are ambiguous — every command below qualifies the group in full.

No secrets live in this repo, and none are ever typed in. The run-of-show
mints a short-lived service principal, pipes its secret into the cluster
over stdin (never a command line, never an environment variable, never a
file), clears the session variable, and deletes the service principal at
cleanup. `.gitignore` blocks any credentials/secret file from being
staged; committed manifests only ever reference a Kubernetes Secret by
name.
