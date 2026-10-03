# ---------- Customer-managed key (CMK) encryption for the storage account ----------
# Fixes: CKV2_AZURE_1
#
# Azure encrypts storage at rest by default with Microsoft-managed keys. CMK hands control
# of that key to us: we can rotate it, audit its use, and revoke it independently of Azure.
#
# Dependency chain (why there are two role assignments, not one):
#   1. The identity running `terraform apply` needs permission to create a key in the vault.
#   2. Once the key exists, the storage account's own identity needs permission to use
#      (wrap/unwrap) that key.
#   3. Only then can the storage account be pointed at the key.

data "azurerm_client_config" "current" {}

# Step 1: let Terraform's own identity manage keys in this vault
resource "azurerm_role_assignment" "terraform_kv_crypto_officer" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Crypto Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Step 2: create the key itself
resource "azurerm_key_vault_key" "storage_cmk" {
  name         = "${var.prefix}-storage-cmk"
  key_vault_id = azurerm_key_vault.kv.id
  # Fix (CKV_AZURE_112): HSM-backed key rather than software-protected (requires Premium vault SKU)
  key_type = "RSA-HSM"
  key_size = 2048
  key_opts = ["wrapKey", "unwrapKey"]

  # Fix (CKV_AZURE_40): keys should not be valid indefinitely
  expiration_date = var.cmk_expiration_date

  depends_on = [azurerm_role_assignment.terraform_kv_crypto_officer]
}

# Step 3: let the storage account's identity use (not manage) that key
resource "azurerm_role_assignment" "storage_identity_kv" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_storage_account.data.identity[0].principal_id
}

# Step 4: tell the storage account to actually use it.
# A standalone resource (rather than a block inside azurerm_storage_account) is required here -
# it breaks what would otherwise be a circular dependency (the account needs an identity before
# it can be granted key access, but the CMK setting itself depends on that access existing).
resource "azurerm_storage_account_customer_managed_key" "data" {
  storage_account_id = azurerm_storage_account.data.id
  key_vault_id        = azurerm_key_vault.kv.id
  key_name            = azurerm_key_vault_key.storage_cmk.name

  depends_on = [azurerm_role_assignment.storage_identity_kv]
}
