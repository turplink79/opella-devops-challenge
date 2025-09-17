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
  environment = "prod"
  region      = "westus2"
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
  location            = "West US 2"
  vnet_name           = "vnet-${local.resource_prefix}"
  address_space       = ["10.1.0.0/16"]

  subnets = {
    web = {
      address_prefixes = ["10.1.1.0/24"]
    }
    app = {
      address_prefixes = ["10.1.2.0/24"]
    }
    data = {
      address_prefixes = ["10.1.3.0/24"]
    }
  }

  network_security_groups = {
    web-nsg = {
      security_rules = [
        {
          name                   = "AllowHTTPS"
          priority               = 1001
          direction              = "Inbound"
          access                 = "Allow"
          protocol               = "Tcp"
          destination_port_range = "443"
        },
        {
          name                   = "AllowHTTP"
          priority               = 1002
          direction              = "Inbound"
          access                 = "Allow"
          protocol               = "Tcp"
          destination_port_range = "80"
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
          source_address_prefix  = "10.1.1.0/24"
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

# Random password for VMs
resource "random_password" "vm_password" {
  length  = 16
  special = true
}

# Public IP for Load Balancer
resource "azurerm_public_ip" "lb_pip" {
  name                = "pip-lb-${local.resource_prefix}"
  resource_group_name = module.vnet.resource_group_name
  location            = "West US 2"
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

# Load Balancer
resource "azurerm_lb" "main" {
  name                = "lb-${local.resource_prefix}"
  location            = "West US 2"
  resource_group_name = module.vnet.resource_group_name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "primary"
    public_ip_address_id = azurerm_public_ip.lb_pip.id
  }

  tags = local.common_tags
}

# Backend Pool
resource "azurerm_lb_backend_address_pool" "main" {
  loadbalancer_id = azurerm_lb.main.id
  name            = "backend-pool"
}

# Health Probe
resource "azurerm_lb_probe" "main" {
  loadbalancer_id = azurerm_lb.main.id
  name            = "http-probe"
  port            = 80
}

# Load Balancer Rule
resource "azurerm_lb_rule" "main" {
  loadbalancer_id                = azurerm_lb.main.id
  name                           = "http-rule"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "primary"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.main.id]
  probe_id                       = azurerm_lb_probe.main.id
}

# Network Interfaces for VMs
resource "azurerm_network_interface" "vm" {
  count               = 2
  name                = "nic-vm-${count.index + 1}-${local.resource_prefix}"
  location            = "West US 2"
  resource_group_name = module.vnet.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = module.vnet.subnet_ids["web"]
    private_ip_address_allocation = "Dynamic"
  }

  tags = local.common_tags
}

# Associate NICs with Backend Pool
resource "azurerm_network_interface_backend_address_pool_association" "vm" {
  count                   = 2
  network_interface_id    = azurerm_network_interface.vm[count.index].id
  ip_configuration_name   = "internal"
  backend_address_pool_id = azurerm_lb_backend_address_pool.main.id
}

# Virtual Machines
resource "azurerm_linux_virtual_machine" "vm" {
  count               = 2
  name                = "vm-${count.index + 1}-${local.resource_prefix}"
  resource_group_name = module.vnet.resource_group_name
  location            = "West US 2"
  size                = "Standard_B2s"
  admin_username      = "azureuser"
  admin_password      = random_password.vm_password.result

  disable_password_authentication = false

  network_interface_ids = [
    azurerm_network_interface.vm[count.index].id,
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
    echo "<h1>Opella DevOps Challenge - ${local.environment} - VM ${count.index + 1}</h1>" > /var/www/html/index.html
  EOF
  )

  tags = local.common_tags
}

# Storage Account
resource "azurerm_storage_account" "main" {
  name                     = "st${local.project}${local.environment}${replace(local.region, "-", "")}"
  resource_group_name      = module.vnet.resource_group_name
  location                 = "West US 2"
  account_tier             = "Standard"
  account_replication_type = "GRS"

  tags = local.common_tags
}

# Storage Container
resource "azurerm_storage_container" "data" {
  name                  = "data"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}