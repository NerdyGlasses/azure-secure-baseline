# VERSION 1: INTENTIONALLY INSECURE (for the before/after demo).
# Do not deploy. Scan with: checkov -d .

resource "azurerm_resource_group" "rg" {
  name     = "${var.prefix}-rg"
  location = var.location
}

# ---------- Networking ----------
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.prefix}-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "app" {
  name                 = "app-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_network_security_group" "app" {
  name                = "${var.prefix}-app-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  # Problem: SSH open to the entire internet
  security_rule {
    name                       = "allow-ssh-any"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "app" {
  subnet_id                 = azurerm_subnet.app.id
  network_security_group_id = azurerm_network_security_group.app.id
}

# ---------- Storage ----------
resource "azurerm_storage_account" "data" {
  name                     = "${var.prefix}data001"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  # Problems: weak TLS, HTTP allowed, public exposure, shared keys on
  min_tls_version                 = "TLS1_0"
  https_traffic_only_enabled      = false
  allow_nested_items_to_be_public = true
  public_network_access_enabled   = true
  shared_access_key_enabled       = true
}

resource "azurerm_storage_container" "files" {
  name                  = "files"
  storage_account_id    = azurerm_storage_account.data.id
  container_access_type = "blob" # Problem: anonymous read access
}

# ---------- Key Vault ----------
resource "azurerm_key_vault" "kv" {
  name                = "${var.prefix}-kv-001"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tenant_id           = var.tenant_id
  sku_name            = "standard"

  # Problems: no purge protection, reachable from the public internet
  purge_protection_enabled      = false
  public_network_access_enabled = true
}
