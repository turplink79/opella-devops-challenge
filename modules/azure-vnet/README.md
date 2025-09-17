# Azure Virtual Network Module

A reusable Terraform module for creating Azure Virtual Networks with subnets and network security groups.

## Usage

```hcl
module "vnet" {
  source = "./modules/azure-vnet"

  resource_group_name = "rg-myapp-dev"
  location           = "East US"
  vnet_name          = "vnet-myapp-dev"
  address_space      = ["10.0.0.0/16"]

  subnets = {
    web = {
      address_prefixes = ["10.0.1.0/24"]
    }
    app = {
      address_prefixes = ["10.0.2.0/24"]
    }
  }

  network_security_groups = {
    web-nsg = {
      security_rules = [
        {
          name                   = "AllowHTTP"
          priority               = 100
          direction              = "Inbound"
          access                 = "Allow"
          protocol               = "Tcp"
          destination_port_range = "80"
        }
      ]
    }
  }

  subnet_nsg_associations = {
    web = "web-nsg"
  }

  tags = {
    Environment = "dev"
    Project     = "myapp"
  }
}
```

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| resource_group_name | Name of the resource group | string | n/a | yes |
| location | Azure region | string | n/a | yes |
| vnet_name | Name of the virtual network | string | n/a | yes |
| address_space | Address space for the VNet | list(string) | ["10.0.0.0/16"] | no |
| subnets | Map of subnet configurations | map(object) | default subnet | no |
| network_security_groups | Map of NSGs with rules | map(object) | {} | no |
| subnet_nsg_associations | Subnet to NSG mappings | map(string) | {} | no |
| tags | Tags for resources | map(string) | {} | no |

## Outputs

| Name | Description |
|------|-------------|
| resource_group_id | Resource group ID |
| resource_group_name | Resource group name |
| vnet_id | Virtual network ID |
| vnet_name | Virtual network name |
| subnet_ids | Map of subnet IDs |
| network_security_group_ids | Map of NSG IDs |