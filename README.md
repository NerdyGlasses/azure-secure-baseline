# Azure Secure Baseline (Terraform)

A small Terraform project demonstrating how to find and fix common Azure
security misconfigurations using static analysis, before any infrastructure
is deployed.

## What this is

A minimal Azure environment — a VNet/subnet with an NSG, a storage account
and container, and a Key Vault — built in two stages:

1. **An intentionally insecure baseline** (open SSH, weak TLS, public storage
   access, no Key Vault protections, etc.)
2. **A hardened version**, fixed issue by issue based on real `checkov`
   findings, with each fix committed separately and documented inline.

The goal was to practice the actual workflow a cloud security engineer uses:
write infrastructure as code, scan it, understand *why* each finding matters,
fix it, and know when a finding is a false positive versus a real gap.

## Scope and honesty about what was tested

This was built and validated **without an active Azure subscription**
(no credit card available for account verification). Everything here was:

- Checked for correctness with `terraform validate` (no cloud calls)
- Scanned for misconfigurations with `checkov` (static analysis of the
  `.tf` files, no cloud calls)

**Nothing in this repo was deployed to a live Azure environment.**
`terraform plan`/`apply` were not run, since those require an authenticated
Azure session. If given access to a subscription, the logical next step
would be running `terraform plan`/`apply` against it and confirming the
Azure Portal reflects these settings.

## Before / after

| | Before | After |
|---|---|---|
| Checkov passed checks | 12 | 36 |
| Checkov failed checks | 19 | 0 |
| Checkov skipped checks | 0 | 2 (documented false positives, see below) |

See the git history for the actual progression — each commit fixes a
specific set of findings and explains the reasoning:

```
a3eb364  Insecure baseline (intentional)
8ed2b4f  Harden NSG, storage account, and Key Vault per checkov findings
edfa073  Split queue logging into its own resource; document CKV_AZURE_33 false positive
...      Add private endpoints, CMK encryption, and centralized logging
```

### Example fixes

- **SSH access**: NSG allowed inbound SSH (port 22) from `0.0.0.0/0`.
  Restricted to a configurable trusted CIDR (`var.trusted_admin_cidr`).
- **Storage account**: weak TLS (1.0), HTTP allowed, public blob access
  enabled, shared key auth enabled, single-region replication, no soft
  delete, no SAS expiry. Fixed to enforce TLS 1.2, HTTPS-only, private
  access, Entra ID/RBAC auth only, GRS replication, 7-day soft delete,
  and a 24-hour SAS expiry policy.
- **Key Vault**: public network access enabled, no purge protection, no
  firewall rules. Fixed with purge protection, a deny-by-default firewall
  (`network_acls`), RBAC authorization, and public access disabled.
- **Private connectivity**: both the storage account and Key Vault had public
  network access disabled, but nothing replaced it. Added a dedicated
  private endpoint subnet, private DNS zones, and private endpoints for
  both resources, so they're reachable only from inside the VNet.
- **Encryption at rest**: storage used Microsoft-managed keys by default.
  Switched to a customer-managed, HSM-backed key with an expiration date,
  using a system-assigned identity on the storage account and scoped RBAC
  role assignments (one for Terraform to create the key, one for the
  storage account to use it).
- **Logging**: added a Log Analytics workspace and a diagnostic setting
  sending blob read/write/delete logs and transaction metrics to it — the
  same workspace type Sentinel is built on top of.

## Lessons learned

**Two documented false positives, not silently ignored findings.**
Two checks are suppressed with `#checkov:skip` comments rather than fixed,
because the underlying control is genuinely in place and the check itself
is outdated:

- `CKV_AZURE_33` (queue logging): the AzureRM provider is deprecating the
  inline `queue_properties` block inside `azurerm_storage_account` in
  favor of a separate `azurerm_storage_account_queue_properties` resource.
  Logging is enabled via that separate resource, but Checkov 3.3.22's rule
  for this check doesn't yet recognize the split-resource pattern.
- `CKV2_AZURE_21` (blob read logging): this check predates diagnostic
  settings and originally targeted a now-deprecated "classic" Storage
  Analytics logging property the provider no longer exposes. Blob read
  logging is implemented here via a diagnostic setting sending logs to
  Log Analytics instead - the modern equivalent the check doesn't look for.

Telling a real gap apart from a scanner limitation, and documenting the
difference instead of just suppressing the noise, is itself part of the
job this project was meant to practice.

**Scanning tools lag behind provider schema changes.** Several fixes
along the way existed only because the AzureRM provider renamed or split
arguments between versions (`enable_https_traffic_only` →
`https_traffic_only_enabled`, inline `queue_properties` → a standalone
resource, `enable_rbac_authorization` → `rbac_authorization_enabled`).
None of these were security issues on their own, but they're the kind of
small frictions that show up constantly in real infrastructure work.

**A circular dependency, solved the standard way.** Customer-managed key
encryption needs the storage account to have an identity before that
identity can be granted permission to use a key - but the encryption
setting itself depends on that permission already existing. This is why
`azurerm_storage_account_customer_managed_key` exists as its own resource
rather than a block inside `azurerm_storage_account`: it lets Terraform's
dependency graph resolve the order correctly (identity → role assignment →
CMK setting) instead of trying to set everything at once.

## Structure

```
.
├── main.tf               # Core resources: networking, storage, Key Vault
├── private-endpoints.tf  # Private subnet, DNS zones, and endpoints for storage + Key Vault
├── encryption.tf         # Customer-managed, HSM-backed key encryption for storage
├── monitoring.tf         # Log Analytics workspace + blob diagnostic logging
├── variables.tf          # Input variables
├── versions.tf           # Provider requirements
└── README.md
```

## Running the checks yourself

```bash
terraform init
terraform validate
pip install checkov
checkov -d .
```

No Azure credentials are required for either command.
