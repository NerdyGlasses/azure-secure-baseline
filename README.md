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
| Checkov passed checks | 12 | 27 |
| Checkov failed checks | 19 | 4 |

See the git history for the actual progression — each commit fixes a
specific set of findings and explains the reasoning:

```
a3eb364  Insecure baseline (intentional)
8ed2b4f  Harden NSG, storage account, and Key Vault per checkov findings
edfa073  Split queue logging into its own resource; document CKV_AZURE_33 false positive
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
  (`network_acls`), and public access disabled.

### A documented false positive

`CKV_AZURE_33` (queue logging) initially kept failing even after logging
was enabled, because the AzureRM provider is deprecating the inline
`queue_properties` block inside `azurerm_storage_account` in favor of a
separate `azurerm_storage_account_queue_properties` resource. Checkov
3.3.22's rule for this check doesn't yet recognize the new resource split.
The control is genuinely in place — this is flagged and explained with a
`#checkov:skip` comment rather than silently ignored.

## Remaining findings (next stage)

Four findings remain, all requiring additional infrastructure rather than
single-argument fixes:

- `CKV2_AZURE_32` / `CKV2_AZURE_33` — private endpoints for Key Vault and
  the storage account (needs a dedicated subnet + private DNS zones)
- `CKV2_AZURE_1` — customer-managed key encryption for the storage account
  (needs a Key Vault key + managed identity)
- `CKV2_AZURE_21` — blob read-request logging (needs a Log Analytics
  workspace + diagnostic settings — a natural bridge to a Sentinel
  monitoring setup)

## Structure

```
.
├── main.tf          # Resources: networking, storage, Key Vault
├── variables.tf     # Input variables
├── versions.tf      # Provider requirements
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
