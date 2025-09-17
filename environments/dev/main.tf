terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~>3.1"
    }
  }
}

provider "azurerm" {
  features {}
}

locals {
  environment = "dev"
  region      = "eastus"
  project     = "opella"

  common_tags = {
    Environment = local.environment
    Project     = local.project
    Region      = local.region
    ManagedBy   = "terraform"
  }

  resource_prefix = "${local.project}-${local.environment}-${local.region}"
}

# Virtual Network Module
module "vnet" {
  source = "../../modules/azure-vnet"

  resource_group_name = "rg-${local.resource_prefix}"
  location            = "East US"
  vnet_name           = "vnet-${local.resource_prefix}"
  address_space       = ["10.0.0.0/16"]

  subnets = {
    web = {
      address_prefixes = ["10.0.1.0/24"]
    }
    app = {
      address_prefixes = ["10.0.2.0/24"]
    }
    data = {
      address_prefixes = ["10.0.3.0/24"]
    }
  }

  network_security_groups = {
    web-nsg = {
      security_rules = [
        {
          name                   = "AllowHTTP"
          priority               = 1001
          direction              = "Inbound"
          access                 = "Allow"
          protocol               = "Tcp"
          destination_port_range = "80"
        },
        {
          name                   = "AllowHTTPS"
          priority               = 1002
          direction              = "Inbound"
          access                 = "Allow"
          protocol               = "Tcp"
          destination_port_range = "443"
        },
        {
          name                   = "AllowSSH"
          priority               = 1003
          direction              = "Inbound"
          access                 = "Allow"
          protocol               = "Tcp"
          destination_port_range = "22"
        }
      ]
    }
    app-nsg = {
      security_rules = [
        {
          name                   = "AllowWebToApp"
          priority               = 1001
          direction              = "Inbound"
          access                 = "Allow"
          protocol               = "Tcp"
          destination_port_range = "8080"
          source_address_prefix  = "10.0.1.0/24"
        }
      ]
    }
  }

  subnet_nsg_associations = {
    web = "web-nsg"
    app = "app-nsg"
  }

  tags = local.common_tags
}

# Random password for VM
resource "random_password" "vm_password" {
  length  = 16
  special = true
}

# Public IP for VM
resource "azurerm_public_ip" "vm_pip" {
  name                = "pip-vm-${local.resource_prefix}"
  resource_group_name = module.vnet.resource_group_name
  location            = "East US"
  allocation_method   = "Static"
  tags                = local.common_tags
}

# Network Interface for VM
resource "azurerm_network_interface" "vm_nic" {
  name                = "nic-vm-${local.resource_prefix}"
  location            = "East US"
  resource_group_name = module.vnet.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = module.vnet.subnet_ids["web"]
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm_pip.id
  }

  tags = local.common_tags
}

# Virtual Machine
resource "azurerm_linux_virtual_machine" "vm" {
  name                = "vm-${local.resource_prefix}"
  resource_group_name = module.vnet.resource_group_name
  location            = "East US"
  size                = "Standard_B1s"
  admin_username      = "azureuser"
  admin_password      = random_password.vm_password.result

  disable_password_authentication = false

  network_interface_ids = [
    azurerm_network_interface.vm_nic.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }

  custom_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y nginx
    systemctl start nginx
    systemctl enable nginx
    echo "<h1>Opella DevOps Challenge - ${local.environment}</h1>" > /var/www/html/index.html
  EOF
  )

  tags = local.common_tags
}

# Storage Account
resource "azurerm_storage_account" "main" {
  name                     = "st${local.project}${local.environment}${local.region}"
  resource_group_name      = module.vnet.resource_group_name
  location                 = "East US"
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = local.common_tags
}

# Storage Container
resource "azurerm_storage_container" "data" {
  name                  = "data"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}