<#
    Crossplane live demo - run-of-show

    Runnable companion to Crossplane_Enterprise_IaC.pptx, covering the demo section:
    slides 11-14 (demo 1) and slide 14 with slide 5 as its rationale (demo 2).

    THIS FILE IS THE DEMO, AND IT IS SELF-CONTAINED. Every manifest it applies is
    written inline as a here-string and piped to `kubectl apply -f -`. It reads no
    external file and writes none, so there is nothing to clone alongside it, no
    path variable to fix up, and no second copy of the YAML that can drift out of
    sync with what you present. Copy this one file anywhere and it runs.

    Collapse/expand each #region in the VS Code editor gutter and step through it one
    block at a time: select the lines you want to run and press F8 (PowerShell: Run
    Selection). Each #region's name labels which step produced the output below it.

    Each demo's README is the narrative companion - why each step exists and what to
    say while it runs. The manifests themselves live here and only here.

    Section labels:
      [PRIVATE]     Run before you go on stage. Not for a shared screen or recording.
      [LIVE]        Safe to run in front of the audience.
      [DESTRUCTIVE] Deletes cluster or cloud resources.

    Requirements:
      - pwsh, kubectl, helm, az on PATH; kubectl pointed at the demo cluster
      - Rights to create Azure AD app registrations/service principals (e.g. Application
        Administrator) and to assign the Contributor role at the subscription scope (e.g.
        Owner or User Access Administrator) - this script creates its own short-lived
        service principal, it does not require one to already exist

    IMPORTANT: `-w` does not work well in a stepped-through script - `kubectl get ... -w`
    never returns. Every watch below is replaced with `kubectl wait` or the Wait-ForReady
    polling helper defined below, both of which time out and return.

    Credentials: the "Credentials" step below creates a brand-new Azure AD app
    registration + service principal, scoped to this subscription, just for this demo -
    never a pasted long-lived secret and never a placeholder/reused clientId. It uses the
    secret once to create the azure-creds Secret, clears it from this session immediately,
    and Cleanup deletes the whole service principal outright, so it never outlives the demo.
#>

$ErrorActionPreference = 'Stop'

#region 0. Session setup
#region Step: Demo-wide settings
# Every manifest in this file is inline, so there is no repo path to configure. These
# are the only values worth changing before a run.

# One tag for the whole Azure provider family. provider-azure-storage and
# provider-azure-network are in-family packages sharing provider-family-azure, so
# pinning them apart risks a family/runtime mismatch - hence a single variable.
$ProviderVersion = 'v2.7.1'

# Storage account names must be globally unique across all of Azure. Change them here
# if they are already taken; nothing else in this file hardcodes them.
$Demo1StorageAccount      = "demosa$(Get-Date -Format 'yyyyMMdd')"   # demo 1, applied directly
$Demo2StorageAccount      = 'demosa2001'  # demo 2, composed by team-a's XR
$Demo2StorageAccountTeamB = 'demosb2001'  # demo 2, composed by team-b's XR (optional)

"Provider family:        $ProviderVersion"
"Demo 1 storage acct:    $Demo1StorageAccount"
"Demo 2 storage acct:    $Demo2StorageAccount"
"Demo 2 team-b acct:     $Demo2StorageAccountTeamB"
#endregion

#region Step: Preflight tools + cluster context
# Preflight: tools on PATH, and which cluster we are about to change.
foreach ($tool in 'kubectl','helm','az') {
    $found = Get-Command $tool -ErrorAction SilentlyContinue
    if ($found) { "OK      $tool -> $($found.Source)" }
    else        { "MISSING $tool" }
}
""
'Current kubectl context:'
kubectl config current-context
#endregion
#endregion


#region Demo 1 - [PRIVATE] Slide 11 - Installing Crossplane
#region Step: Install Crossplane core via Helm
# One Helm install brings up the control plane. Do this before the talk: the pull and
# rollout take longer than an audience will sit through.
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm repo update

helm upgrade --install crossplane crossplane-stable/crossplane `
  --namespace crossplane-system `
  --create-namespace `
  --wait

kubectl get pods -n crossplane-system
#endregion

#region Step: Verify Crossplane pods
# Verify - this is the output the slide's right-hand panel shows.
kubectl get pods -n crossplane-system
#endregion
#endregion

#region Demo 1 - [PRIVATE] Slide 12 - Onboarding the Azure Provider
# Azure support ships as per-service provider packages. Demo 1 needs only
# provider-azure-storage; demo 2 adds provider-azure-network later.
@"
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-azure-storage
spec:
  package: xpkg.upbound.io/upbound/provider-azure-storage:v2.7.1
"@ | kubectl apply -f -
kubectl wait --for=condition=Healthy provider/provider-azure-storage --timeout=180s
kubectl get providers
#endregion

#region Demo 1 - [PRIVATE] Credentials - short-lived, safe to run interactively
# Creates a brand-new Azure AD app registration + service principal scoped to this
# subscription, purely for this demo - it never reuses or assumes an existing SP, so
# there's no placeholder clientId to fill in first. Cleanup deletes the whole service
# principal outright, so it doesn't just expire - it's actively gone.

#region Step: Create a service principal scoped to this subscription
$DemoAdSubscriptionId = az account show --query id -o tsv
$DemoAdTenantId        = az account show --query tenantId -o tsv
$DemoAdSpName          = "crossplane-demo-$(Get-Date -Format yyyyMMddHHmmss)"
$DemoAdExpiry          = (Get-Date).ToUniversalTime().AddHours(24)

# --create-password false defers secret creation to the credential reset below, so the
# secret itself can get a 4-hour --end-date instead of az's default 1-year validity.
$DemoAdAppId = az ad sp create-for-rbac `
    --name $DemoAdSpName `
    --role Contributor `
    --scopes "/subscriptions/$DemoAdSubscriptionId" `
    --create-password false `
    --query appId -o tsv

$DemoAdClientSecret = az ad app credential reset `
    --id $DemoAdAppId `
    --end-date $DemoAdExpiry.ToString('yyyy-MM-ddTHH:mm:ssZ') `
    --query password -o tsv

"Service principal '$DemoAdSpName' created (appId $DemoAdAppId), secret expires $($DemoAdExpiry.ToString('u')). Secret not printed."
#endregion

#region Step: Build the credential JSON and create the Secret
# Loads the Azure service principal credentials into the cluster as a Secret, for the
# Azure ClusterProviderConfig to reference. Only the client secret comes from
# $DemoAdClientSecret (set above); the rest are non-secret identifiers (clientId,
# tenantId, subscriptionId, endpoint URLs).
#
# Nothing here is written to disk. The whole credential document is assembled in memory
# and handed to kubectl over stdin, so there is no config file to gitignore, no leftover
# artifact after the talk, and nothing on disk to forget about.
$secretConfig = [ordered]@{
    clientId                       = $DemoAdAppId
    subscriptionId                 = $DemoAdSubscriptionId
    tenantId                       = $DemoAdTenantId
    activeDirectoryEndpointUrl     = 'https://login.microsoftonline.com'
    resourceManagerEndpointUrl     = 'https://management.azure.com/'
    activeDirectoryGraphResourceId = 'https://graph.windows.net/'
    sqlManagementEndpointUrl       = 'https://management.core.windows.net:8443/'
    galleryEndpointUrl             = 'https://gallery.azure.com/'
    managementEndpointUrl          = 'https://management.core.windows.net/'
}
# Safe to show on screen - these are identifiers, not credentials. The client secret is
# added below and is never printed.
$secretConfig | ConvertTo-Json

if (-not $DemoAdClientSecret) {
    throw '$DemoAdClientSecret is not set - the service principal creation step above must have failed'
}

$secretConfig.clientSecret = $DemoAdClientSecret
$credsJson = $secretConfig | ConvertTo-Json -Compress


# Piped directly to kubectl via stdin as a Secret manifest - data values must be
# base64, and stdin (unlike --from-literal) never puts the secret in the command line.
$credsB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($credsJson))
@"
apiVersion: v1
kind: Secret
metadata:
  name: azure-creds
  namespace: crossplane-system
type: Opaque
data:
  creds: $credsB64
"@ | kubectl apply -f -
"Secret 'azure-creds' created in namespace crossplane-system."

# Clear it from this session now - it's already in the cluster Secret.
Remove-Variable -Name DemoAdClientSecret -ErrorAction SilentlyContinue
'$DemoAdClientSecret cleared from this session.'
#endregion

#region Step: Verify the Secret exists
kubectl get secret azure-creds -n crossplane-system
#endregion

#region Step: Apply the ClusterProviderConfig
# Crossplane v2 splits provider credentials in two, both in the namespaced ".m." group:
# ClusterProviderConfig (cluster-scoped, usable from any namespace - used here) and
# ProviderConfig (namespaced, usable only by MRs in its own namespace, Secret included).
# A Managed Resource with no providerConfigRef defaults to
# { name: default, kind: ClusterProviderConfig } - exactly this object - so none of the
# MRs below need a providerConfigRef.
@'
apiVersion: azure.m.upbound.io/v1beta1
kind: ClusterProviderConfig
metadata:
  name: default
spec:
  credentials:
    source: Secret
    secretRef:
      namespace: crossplane-system
      name: azure-creds
      key: creds
'@ | kubectl apply -f -
kubectl get clusterproviderconfig
#endregion
#endregion

#region Demo 1 - [PRIVATE] Preflight check worth doing before you present
# The Account below wires to the ResourceGroup with
# resourceGroupNameSelector.matchControllerRef: true. That selector matches resources
# sharing a controller reference - and here the two objects are applied directly, with no
# XR owning either. Confirm it resolves on your provider version before you are on stage.
# If it does not, fall back to an explicit resourceGroupNameRef: { name: demo-rg }.

# This is slide 13, verbatim. Demo 2 used to select this ResourceGroup by label; it now
# composes its own, so the labels that existed only for that are gone and this matches
# the slide exactly. The Account's name comes from $Demo1StorageAccount (session setup)
# because it must be globally unique across all of Azure.
$DemoResourcesYaml = @"
apiVersion: azure.m.upbound.io/v1beta1
kind: ResourceGroup
metadata:
  name: demo-rg
  namespace: team-a
spec:
  forProvider:
    location: westeurope
---
apiVersion: storage.azure.m.upbound.io/v1beta1
kind: Account
metadata:
  name: $Demo1StorageAccount
  namespace: team-a
spec:
  forProvider:
    location: westeurope
    accountTier: Standard
    accountReplicationType: LRS
    accessTier: Hot
    resourceGroupNameRef:
      name: demo-rg
"@

# Server-side dry run: validates schema and admission without creating anything.
kubectl create namespace team-a --dry-run=client -o yaml | kubectl apply -f -
$DemoResourcesYaml | kubectl apply -f - --dry-run=server
#endregion

#region Demo 1 - [LIVE] Slide 13 - Your First Resources
#region Step: Apply the two Managed Resources
# The live moment. Two namespaced Managed Resources, applied directly - no Claim, no XR,
# no Composition. The ".m." in each API group is what makes them namespaced.
# A ResourceGroup (demo-rg) and, beneath it, an Account ($Demo1StorageAccount), both
# in namespace team-a, each reflected as a real Azure object.
$DemoResourcesYaml | kubectl apply -f - -n team-a
#endregion

#region Step: What exists in the namespace right now
# Fully qualified on purpose. A v2 provider registers every kind twice -
# resourcegroups.azure.upbound.io (cluster-scoped, the v1 shape) and
# resourcegroups.azure.m.upbound.io (namespaced, the v2 shape) - so the bare short name
# "resourcegroup" is ambiguous and kubectl may resolve it to the cluster-scoped CRD,
# which will show nothing.
kubectl get resourcegroups.azure.m.upbound.io,accounts.storage.azure.m.upbound.io -n team-a
#endregion


#region Step: View the same two objects in Azure
az group show --name demo-rg --output table
az storage account show --name $Demo1StorageAccount --resource-group demo-rg --query "{name:name,location:location,sku:sku.name,accessTier:accessTier}" --output table
#endregion
#endregion

#region Demo 1 - [LIVE] Live change - default access tier Hot -> Cold
# Only the Account is rewritten and re-applied - the ResourceGroup is unchanged, so it
# is left out of this manifest. Crossplane diffs the desired state (Cold) against what
# is in Azure (Hot) and reconciles the difference - no redeploy, no new resource.
$DemoResourcesYaml = @"
apiVersion: storage.azure.m.upbound.io/v1beta1
kind: Account
metadata:
  name: $Demo1StorageAccount
  namespace: team-a
  labels:
    mycompany.com/stack: team-a
    mycompany.com/role: storage-account
spec:
  forProvider:
    location: westeurope
    accountTier: Standard
    accountReplicationType: LRS
    accessTier: Cold
    resourceGroupNameRef:
      name: demo-rg
"@
$DemoResourcesYaml | kubectl apply -f - -n team-a


# Verify in Azure - accessTier now reads Cold.
az storage account show --name $Demo1StorageAccount --resource-group demo-rg --query "{name:name,accessTier:accessTier}" --output table
#endregion

#region Demo 2 - [PRIVATE] Setup (before you go on stage)
# Slide 5 (Why XRs & XRDs?) is the rationale; slide 14 is the payoff. A private-by-default
# storage account behind a VNet -> Subnet -> Private Endpoint, resolved through a linked
# Private DNS Zone - all from one namespaced XR.
#
#   Virtual Network -> Subnet -> Private Endpoint -> Storage Account
#                                     |
#                                     v
#                           Private DNS Zone + Zone Group
#
# Prerequisite: demo 1 has run - Crossplane installed, plus azure-creds and the default
# ClusterProviderConfig. That is all demo 2 needs from it. It shares no Azure resource
# with demo 1: each XR composes its own resource group, so demo-rg and $Demo1StorageAccount
# are untouched.
#
# Three scripts: the extra provider plus the two Composition Functions, then the platform
# team's XRD + Composition, then team-a's XR instance. The first is slow (image pulls) and
# the third takes minutes to converge - neither belongs in front of an audience.

#region Step: Install network provider + functions
# provider-azure-network + function-patch-and-transform + function-auto-ready.
# Same family/version as the storage provider from demo 1 - both are in-family
# packages on top of provider-family-azure.
@"
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-azure-network
spec:
  package: xpkg.upbound.io/upbound/provider-azure-network:v2.7.1
"@ | kubectl apply -f -

# Crossplane v2 has no built-in patch-and-transform - composition is functions only, so
# these two are a hard requirement, not an optional extra. Both are crossplane-contrib
# packages on Crossplane's own registry. Check for newer tags before a talk:
#   github.com/crossplane-contrib/function-patch-and-transform/releases
#   github.com/crossplane-contrib/function-auto-ready/releases
@'
apiVersion: pkg.crossplane.io/v1
kind: Function
metadata:
  name: function-patch-and-transform
spec:
  package: xpkg.crossplane.io/crossplane-contrib/function-patch-and-transform:v0.10.9
---
apiVersion: pkg.crossplane.io/v1
kind: Function
metadata:
  name: function-auto-ready
spec:
  package: xpkg.crossplane.io/crossplane-contrib/function-auto-ready:v0.7.0
'@ | kubectl apply -f -

kubectl wait --for=condition=Healthy provider/provider-azure-network --timeout=180s
kubectl wait --for=condition=Healthy function/function-patch-and-transform --timeout=180s
kubectl wait --for=condition=Healthy function/function-auto-ready --timeout=180s
#endregion

#region Step: Apply the platform team's XRD - the API definition
# The platform team's half, part 1. The CompositeResourceDefinition declares the
# XPrivateStorage kind and its schema. apiextensions.crossplane.io/v2 plus
# scope: Namespaced is what makes instances of it namespaced objects - the v2 model that
# replaces v1's cluster-scoped XR + Claim pair. Creates no infrastructure.
#
# THIS SCHEMA IS THE CONTRACT, AND IT IS THE WHOLE CONTRACT. Three fields: a region, a
# name, and an environment picked off a list. Nothing else is settable, because nothing
# else is declared - a consumer cannot ask for accountTier, a replication type, a public
# endpoint, or a different address space, since there is no field to put them in. The
# API server rejects unknown fields outright rather than ignoring them, so an XR that
# tries is refused, not silently trimmed. That is the platform boundary: not a policy
# engine bolted on afterwards, just the shape of the API.
$Demo2XrdYaml = @'
apiVersion: apiextensions.crossplane.io/v2
kind: CompositeResourceDefinition
metadata:
  name: xprivatestorages.mycompany.com
spec:
  scope: Namespaced
  group: mycompany.com
  names:
    kind: XPrivateStorage
    plural: xprivatestorages
  versions:
    - name: v1
      served: true
      referenceable: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                location:
                  type: string
                  description: Azure region for every resource in this stack.
                storageAccountName:
                  type: string
                  description: >-
                    Globally-unique Azure storage account name for this
                    instance. Also derives the resource group, private
                    endpoint and private service connection names, so two
                    teams' instances never collide on any of them.
                environment:
                  type: string
                  enum:
                    - Production
                    - Development
                  description: >-
                    Pick one. The platform team decides what each value
                    means - today, Production gets 30-day blob soft-delete
                    retention and Development gets the 1-day floor. Consumers
                    choose the intent; they never choose the number, and they
                    cannot request a value that is not on this list.
              required:
                - location
                - storageAccountName
                - environment
            status:
              type: object
              properties:
                storageAccountId:
                  type: string
                  description: >-
                    Full Azure resource ID of the composed storage account,
                    mirrored here from that resource's own status once Azure
                    reports it. No subscription ID is ever typed into this
                    file - the private endpoint below reads it back off this
                    field instead.
'@

$Demo2XrdYaml | kubectl apply -f -
#endregion

#region Step: Apply the platform team's Composition - the implementation
# Part 2, and the heart of demo 2. One function-patch-and-transform step composes seven
# Managed Resources from a three-field XR; function-auto-ready then reports the XR Ready
# once they all are. Order matters - the XRD above defines the kind this implements.
#
# This is the file to have on screen when you make the platform-vs-consumer point. Read
# it as two columns: fields written in a base are the platform team's, fields with a
# patch pointing at them came from the consumer's three-line spec. There are only three
# of the latter.
#
# Every base is a ".m." (namespaced) group, so all seven land in the XR's own namespace,
# and every cross-resource reference is matchControllerRef - matching only what this
# same XR composed. No matchLabels, no shared object, nothing reaching into another
# team's namespace. Two teams' stacks are completely disjoint.
$Demo2CompositionYaml = @'
apiVersion: apiextensions.crossplane.io/v1
kind: Composition
metadata:
  name: private-storage-azure
spec:
  compositeTypeRef:
    apiVersion: mycompany.com/v1
    kind: XPrivateStorage
  mode: Pipeline
  pipeline:
    - step: compose-resources
      functionRef:
        name: function-patch-and-transform
      input:
        apiVersion: pt.fn.crossplane.io/v1beta1
        kind: Resources
        resources:
          # Every resource below carries two kinds of field:
          #
          #   PLATFORM-OWNED - written here in the base, with no patch pointing at it.
          #     The consumer has no way to reach these. They are not in the XRD schema,
          #     so there is no field to set, and the API server refuses unknown fields.
          #     This is where the platform team's opinions live: private by default,
          #     Standard/LRS, this address space, this DNS zone, this wiring.
          #
          #   FROM THE CONSUMER - filled by a patch reading the XR's spec. Exactly three
          #     values reach in: location, storageAccountName, environment. Everything
          #     else about the stack is decided here, once, for every team.
          #
          # Nothing is hardcoded per-team. The stack label comes from the XR's own
          # namespace, and every cross-resource reference uses matchControllerRef, which
          # matches only resources composed by this same XR. Two teams' instances are
          # therefore completely disjoint, with no shared object between them.

          - name: resource-group
            base:
              apiVersion: azure.m.upbound.io/v1beta1
              kind: ResourceGroup
              metadata:
                labels:
                  mycompany.com/role: resource-group
              spec:
                forProvider: {}
            patches:
              - type: FromCompositeFieldPath
                fromFieldPath: spec.location
                toFieldPath: spec.forProvider.location
              - type: FromCompositeFieldPath
                fromFieldPath: metadata.namespace
                toFieldPath: metadata.labels[mycompany.com/stack]
              - type: CombineFromComposite
                # The Azure resource group name must be unique within the
                # subscription, so it is derived from the globally-unique
                # storage account name rather than fixed.
                combine:
                  variables:
                    - fromFieldPath: spec.storageAccountName
                  strategy: string
                  string:
                    fmt: "rg-%s"
                toFieldPath: metadata.name

          - name: vnet
            base:
              apiVersion: network.azure.m.upbound.io/v1beta1
              kind: VirtualNetwork
              metadata:
                labels:
                  mycompany.com/role: virtual-network
              spec:
                forProvider:
                  # PLATFORM-OWNED: the consumer does not pick address space.
                  addressSpace: ["10.0.0.0/16"]
                  resourceGroupNameSelector:
                    matchControllerRef: true
            patches:
              - type: FromCompositeFieldPath
                fromFieldPath: spec.location
                toFieldPath: spec.forProvider.location
              - type: FromCompositeFieldPath
                fromFieldPath: metadata.namespace
                toFieldPath: metadata.labels[mycompany.com/stack]

          - name: subnet
            base:
              apiVersion: network.azure.m.upbound.io/v1beta1
              kind: Subnet
              metadata:
                labels:
                  mycompany.com/role: subnet
              spec:
                forProvider:
                  # PLATFORM-OWNED: prefix, and the policy that lets a private
                  # endpoint live in this subnet at all.
                  addressPrefixes: ["10.0.1.0/24"]
                  privateEndpointNetworkPolicies: Disabled
                  resourceGroupNameSelector:
                    matchControllerRef: true
                  virtualNetworkNameSelector:
                    matchControllerRef: true
            patches:
              - type: FromCompositeFieldPath
                fromFieldPath: metadata.namespace
                toFieldPath: metadata.labels[mycompany.com/stack]

          - name: storage-account
            base:
              apiVersion: storage.azure.m.upbound.io/v1beta1
              kind: Account
              metadata:
                labels:
                  mycompany.com/role: storage-account
              spec:
                forProvider:
                  # PLATFORM-OWNED, all three. This is the clearest place to make
                  # the point live: there is no XRD field for any of them, so a
                  # consumer cannot ask for Premium, cannot ask for GRS, and above
                  # all cannot turn the public endpoint back on.
                  accountTier: Standard
                  accountReplicationType: LRS
                  publicNetworkAccessEnabled: false
                  resourceGroupNameSelector:
                    matchControllerRef: true
            patches:
              - type: FromCompositeFieldPath
                fromFieldPath: spec.location
                toFieldPath: spec.forProvider.location
              - type: FromCompositeFieldPath
                fromFieldPath: metadata.namespace
                toFieldPath: metadata.labels[mycompany.com/stack]
              - type: FromCompositeFieldPath
                # metadata.name is the actual Azure storage account name, which
                # must be globally unique across all of Azure - hence a consumer
                # field rather than something decided here.
                fromFieldPath: spec.storageAccountName
                toFieldPath: metadata.name
              - type: ToCompositeFieldPath
                # Mirrors Azure's own resource ID (subscription included) onto the XR,
                # once this resource exists - no subscription ID is ever supplied here.
                fromFieldPath: status.atProvider.id
                toFieldPath: status.storageAccountId

              # FROM THE CONSUMER, but only as an intent. The consumer says
              # "Production" or "Development"; the platform team decides here what
              # that buys them. Change these numbers once and every team's stack
              # moves - no consumer YAML changes.
              - type: FromCompositeFieldPath
                fromFieldPath: spec.environment
                # v2 provider schemas model these as single objects, not list blocks - no [0].
                toFieldPath: spec.forProvider.blobProperties.deleteRetentionPolicy.days
                transforms:
                  - type: map
                    map:
                      Production: 30
                      Development: 1
              - type: FromCompositeFieldPath
                fromFieldPath: spec.environment
                toFieldPath: spec.forProvider.blobProperties.containerDeleteRetentionPolicy.days
                transforms:
                  - type: map
                    map:
                      Production: 30
                      Development: 1

          - name: private-dns-zone
            base:
              apiVersion: network.azure.m.upbound.io/v1beta1
              kind: PrivateDNSZone
              metadata:
                # Not a placeholder - Azure's private-link DNS integration for Blob
                # Storage resolves through this exact zone name, so it is fixed and
                # cannot be parameterized. That used to mean two teams could not run
                # at once. It no longer does: each XR composes its own resource group
                # above, and a private DNS zone name only has to be unique within its
                # resource group, so team-a's zone and team-b's zone coexist happily.
                name: privatelink.blob.core.windows.net
                labels:
                  mycompany.com/role: private-dns-zone
              spec:
                forProvider:
                  resourceGroupNameSelector:
                    matchControllerRef: true
            patches:
              - type: FromCompositeFieldPath
                fromFieldPath: metadata.namespace
                toFieldPath: metadata.labels[mycompany.com/stack]

          - name: private-dns-zone-vnet-link
            base:
              apiVersion: network.azure.m.upbound.io/v1beta1
              kind: PrivateDNSZoneVirtualNetworkLink
              metadata:
                labels:
                  mycompany.com/role: private-dns-zone-vnet-link
              spec:
                forProvider:
                  registrationEnabled: false
                  resourceGroupNameSelector:
                    matchControllerRef: true
                  privateDnsZoneNameSelector:
                    matchControllerRef: true
                  virtualNetworkIdSelector:
                    matchControllerRef: true
            patches:
              - type: FromCompositeFieldPath
                fromFieldPath: metadata.namespace
                toFieldPath: metadata.labels[mycompany.com/stack]

          - name: private-endpoint
            base:
              apiVersion: network.azure.m.upbound.io/v1beta1
              kind: PrivateEndpoint
              metadata:
                labels:
                  mycompany.com/role: private-endpoint
              spec:
                forProvider:
                  resourceGroupNameSelector:
                    matchControllerRef: true
                  subnetIdSelector:
                    matchControllerRef: true
                  # PLATFORM-OWNED: the entire private-link wiring. The consumer
                  # never sees a subresource name or a connection mode.
                  # v2 provider schemas model these as single objects, not list blocks.
                  privateServiceConnection:
                    isManualConnection: false
                    subresourceNames: ["blob"]
                  privateDnsZoneGroup:
                    name: default
                    privateDnsZoneIdsSelector:
                      matchControllerRef: true
            patches:
              - type: FromCompositeFieldPath
                fromFieldPath: spec.location
                toFieldPath: spec.forProvider.location
              - type: FromCompositeFieldPath
                fromFieldPath: metadata.namespace
                toFieldPath: metadata.labels[mycompany.com/stack]
              - type: CombineFromComposite
                combine:
                  variables:
                    - fromFieldPath: spec.storageAccountName
                  strategy: string
                  string:
                    fmt: "pe-%s"
                toFieldPath: metadata.name
              - type: CombineFromComposite
                combine:
                  variables:
                    - fromFieldPath: spec.storageAccountName
                  strategy: string
                  string:
                    fmt: "psc-%s"
                toFieldPath: spec.forProvider.privateServiceConnection.name
              - type: FromCompositeFieldPath
                # No *Selector field exists for privateConnectionResourceId in this
                # provider's schema, so the Azure resource ID is needed as a literal
                # string. It's read straight off status.storageAccountId - the storage
                # account's own reported resource ID, subscription included - rather
                # than reconstructed from a subscription ID supplied anywhere in this file.
                fromFieldPath: status.storageAccountId
                toFieldPath: spec.forProvider.privateServiceConnection.privateConnectionResourceId
                policy:
                  fromFieldPath: Required

    - step: auto-ready
      functionRef:
        name: function-auto-ready
      input:
        apiVersion: autoready.fn.crossplane.io/v1beta1
        kind: Input
'@

$Demo2CompositionYaml | kubectl apply -f -
kubectl get xrd,composition
#endregion

#region Step: Apply team-a's XR instance
# The consumer's half, and the whole of what team-a writes: three fields. Composes seven
# resources; allow several minutes.
$TeamAXrYaml = @"
apiVersion: mycompany.com/v1
kind: XPrivateStorage
metadata:
  name: team-a-storage
  namespace: team-a
spec:
  location: westeurope
  storageAccountName: $Demo2StorageAccount
  environment: Production
"@

kubectl create namespace team-a --dry-run=client -o yaml | kubectl apply -f -
$TeamAXrYaml | kubectl apply -f -
kubectl wait --for=condition=Ready xprivatestorage/team-a-storage -n team-a --timeout=300s
#endregion
#endregion

#region Demo 2 - [LIVE] Slide 14 - A More Involved Deployment
# Show the consumer's side first - the entire thing team-a wrote - then everything that
# one object produced.

#region Step: Show what the developer authored
# All the developer authored. Location and a storage account name.
$TeamAXrYaml
#endregion

#region Step: Show the one object they applied
kubectl get xprivatestorage -n team-a
#endregion

#region Step: Show the seven resources it produced
kubectl get resourcegroups.azure.m.upbound.io,virtualnetworks.network.azure.m.upbound.io,subnets.network.azure.m.upbound.io,privatednszones.network.azure.m.upbound.io,privatednszonevirtualnetworklinks.network.azure.m.upbound.io,privateendpoints.network.azure.m.upbound.io,accounts.storage.azure.m.upbound.io -n team-a
#endregion

#region Step: Wait for the XR to go Ready
# Poll the XR itself; it goes Ready only once everything beneath it is.
kubectl wait --for=condition=Ready xprivatestorage/team-a-storage -n team-a --timeout=600s
#endregion
#endregion

#region Demo 2 - [LIVE] The point worth narrating
# The storage account was created with publicNetworkAccessEnabled: false from the start -
# not opened and then locked down. It is reachable only through the private endpoint, over
# the VNet, resolved by the linked private DNS zone. The Function pipeline decided *what* to
# create; the resources still resolve *how* they connect through matchControllerRef -
# everything here shares this XR as its controller.
S

#region Demo 2 - [LIVE] Who decided what - the platform boundary
# The whole platform-engineering argument, in three commands.
#
# Team-a wrote three lines. Everything else on the object below - the tier, the
# replication type, the closed public endpoint, the address space, the retention numbers -
# was decided by the platform team in the Composition, and there is no field in the XRD
# through which a consumer could have asked for anything different.

# 1. What the consumer wrote. Three fields.
$TeamAXrYaml

# 2. What the platform decided, on the resource that came out of it.
kubectl get accounts.storage.azure.m.upbound.io $Demo2StorageAccount -n team-a `
  -o jsonpath='{"tier:            "}{.spec.forProvider.accountTier}{"\nreplication:     "}{.spec.forProvider.accountReplicationType}{"\npublic access:   "}{.spec.forProvider.publicNetworkAccessEnabled}{"\nblob retention:  "}{.spec.forProvider.blobProperties[0].deleteRetentionPolicy[0].days}{" days\n"}'

# 3. The consumer asked for "Production", not for "30 days". The platform team owns that
# mapping and can change it for every team at once by editing the Composition - no
# consumer YAML changes. Team-b's Development instance gets the 1-day floor from the
# very same Composition.
'environment -> retention is the platform team''s call, not the consumer''s.'
#endregion

#region Demo 2 - [PRIVATE] Optional - a second team, same type, side by side
# XPrivateStorage is reusable across namespaces, and team-b's instance can run *alongside*
# team-a's - no teardown needed. Each XR composes its own resource group, and a private
# DNS zone name only has to be unique within its resource group, so both stacks get their
# own privatelink.blob.core.windows.net without colliding.
#
# This is the strongest version of the platform story: same Composition, two namespaces,
# two fully disjoint stacks, and the only difference in what the teams wrote is
# environment: Production vs Development - which the platform team turns into 30-day
# versus 1-day blob retention.

# Same Composition, own namespace, own resources - only the three spec fields differ.
$TeamBXrYaml = @"
apiVersion: mycompany.com/v1
kind: XPrivateStorage
metadata:
  name: team-b-storage
  namespace: team-b
spec:
  location: westeurope
  storageAccountName: $Demo2StorageAccountTeamB
  environment: Development
"@

kubectl create namespace team-b --dry-run=client -o yaml | kubectl apply -f -
$TeamBXrYaml | kubectl apply -f -
kubectl wait --for=condition=Ready xprivatestorage/team-b-storage -n team-b --timeout=300s
kubectl get xprivatestorage -n team-b
#endregion

#region [DESTRUCTIVE] Cleanup
# Run in this order - the XR first so Crossplane deletes what it composed, then the type
# definition, then demo 1's own objects.

#region Step: Delete demo 2 - XR, composed resources, and the type
$TeamAXrYaml          | kubectl delete -f - --ignore-not-found
$TeamBXrYaml          | kubectl delete -f - --ignore-not-found
$Demo2CompositionYaml | kubectl delete -f - --ignore-not-found
$Demo2XrdYaml         | kubectl delete -f - --ignore-not-found
#endregion

#region Step: Delete demo 1 - Managed Resources and the Secret
$DemoResourcesYaml | kubectl delete -f - --ignore-not-found
kubectl delete secret azure-creds -n crossplane-system --ignore-not-found
#endregion

#region Step: Delete the short-lived Azure AD service principal
if ($DemoAdAppId) {
    az ad sp delete --id $DemoAdAppId
    "Deleted service principal '$DemoAdSpName' (appId not printed)."
} else {
    'No demo service principal recorded in this session - nothing to delete.'
}
Remove-Variable -Name DemoAdClientSecret -ErrorAction SilentlyContinue
'$DemoAdClientSecret cleared from this session (if still set).'
#endregion
#endregion

#region Troubleshooting (reference only - not meant to be run top to bottom)
<#
    Symptom                                  | Where to look
    ------------------------------------------|---------------------------------------------------------------
    Short kind name returns nothing           | v2 registers every kind twice - <kind>.azure.upbound.io (cluster-scoped) and <kind>.azure.m.upbound.io (namespaced). Always qualify the group.
    A resource sits Ready=False               | kubectl describe <kind>.<group>/<name> -n team-a - the Synced condition carries the Azure API error
    Provider never goes Healthy               | kubectl describe provider/provider-azure-storage, then the pod logs in crossplane-system
    Account cannot find its resource group    | The matchControllerRef caveat above - swap in resourceGroupNameRef: { name: demo-rg }
    Storage account name rejected             | Must be globally unique across Azure - change $Demo1StorageAccount / $Demo2StorageAccount in the Session setup region
    Field names look wrong                    | v1beta1 schemas are deprecated as of provider v2.6.0. Run kubectl explain privateendpoints.network.azure.m.upbound.io.spec.forProvider
    A command hangs forever                   | Something still uses -w. Use kubectl wait or Wait-ForReady instead.
    A .ps1 script is blocked                  | Execution policy. Run Set-ExecutionPolicy -Scope Process Bypass first, or invoke with powershell -ExecutionPolicy Bypass -File <path>
#>
#endregion

#region Diagnostics
# Run this when something is stuck and paste the output where you need help.
'--- providers ---';  kubectl get providers
'--- functions ---';  kubectl get functions
'--- managed  ---';   kubectl get managed
'--- team-a   ---';   kubectl get all,xprivatestorage -n team-a
'--- events   ---';   kubectl get events -n team-a --sort-by='.lastTimestamp' | Select-Object -Last 20
#endregion
