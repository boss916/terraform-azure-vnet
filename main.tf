

module "os" {
  source       = "./os"
  vm_os_simple = var.vm_os_simple
}

data "azurerm_resource_group" "vm" {
  name = var.resource_group_name
}

locals {
  ssh_keys = compact(concat([var.ssh_key], var.extra_ssh_keys))
}

resource "random_id" "vm-sa" {
  keepers = {
    vm_hostname = var.vm_name
  }

  byte_length = 6
}

/*resource "azurerm_storage_account" "vm-sa" {
  count                    = var.boot_diagnostics ? 1 : 0
  name                     = "bootdiag${lower(random_id.vm-sa.hex)}"
  resource_group_name      = data.azurerm_resource_group.vm.name
  location                 = coalesce(var.location, data.azurerm_resource_group.vm.location)
  account_tier             = element(split("_", var.boot_diagnostics_sa_type), 0)
  account_replication_type = element(split("_", var.boot_diagnostics_sa_type), 1)
  tags                     = var.tags
}*/

resource "azurerm_virtual_machine" "vm-linux" {
  count                            = !contains(tolist([var.vm_os_simple, var.vm_os_offer]), "WindowsServer") && !var.is_windows_image ? var.nb_instances : 0
  name                             = var.vm_name
  resource_group_name              = data.azurerm_resource_group.vm.name
  location                         = coalesce(var.location, data.azurerm_resource_group.vm.location)
  availability_set_id              = azurerm_availability_set.vm.id
  vm_size                          = var.vm_size
  network_interface_ids            = [element(azurerm_network_interface.vm.*.id, count.index)]
  delete_os_disk_on_termination    = var.delete_os_disk_on_termination
  delete_data_disks_on_termination = var.delete_data_disks_on_termination

  /*plan {
    name =var.plan_name
    product=var.plan_product
    publisher=var.plan_publisher
  }*/
  dynamic "identity" {
    for_each = length(var.identity_ids) == 0 && var.identity_type == "SystemAssigned" ? [var.identity_type] : []
    content {
      type = var.identity_type
    }
  }

  dynamic "identity" {
    for_each = length(var.identity_ids) > 0 || var.identity_type == "UserAssigned" ? [var.identity_type] : []
    content {
      type         = var.identity_type
      identity_ids = length(var.identity_ids) > 0 ? var.identity_ids : []
    }
  }

  storage_image_reference {
    id        = var.vm_os_id
    publisher = var.vm_os_id == "" ? coalesce(var.vm_os_publisher, module.os.calculated_value_os_publisher) : ""
    offer     = var.vm_os_id == "" ? coalesce(var.vm_os_offer, module.os.calculated_value_os_offer) : ""
    sku       = var.vm_os_id == "" ? coalesce(var.vm_os_sku, module.os.calculated_value_os_sku) : ""
    version   = var.vm_os_id == "" ? var.vm_os_version : ""
  }

  storage_os_disk {
    name              = "osdisk-${var.vm_name}-${count.index}"
    create_option     = "FromImage"
    caching           = "ReadWrite"
    managed_disk_type = var.storage_account_type
  }

  dynamic "storage_data_disk" {
    for_each = range(var.nb_data_disk)
    content {
      name              = "${var.vm_name}-datadisk-${count.index}-${storage_data_disk.value}"
      create_option     = "Empty"
      lun               = storage_data_disk.value
      disk_size_gb      = var.data_disk_size_gb
      managed_disk_type = var.data_sa_type
    }
  }

  dynamic "storage_data_disk" {
    for_each = var.extra_disks
    content {
      name              = "${var.vm_name}-extradisk-${count.index}-${storage_data_disk.value.name}"
      create_option     = "Empty"
      lun               = storage_data_disk.key + var.nb_data_disk
      disk_size_gb      = storage_data_disk.value.size
      managed_disk_type = var.data_sa_type
    }
  }

  os_profile {
    computer_name  = var.vm_name
    admin_username = var.admin_username
    admin_password = var.admin_password
    custom_data    = var.custom_data
  }

  os_profile_linux_config {
    disable_password_authentication = var.enable_ssh_key

    dynamic "ssh_keys" {
      for_each = var.enable_ssh_key ? local.ssh_keys : []
      content {
        path     = "/home/${var.admin_username}/.ssh/authorized_keys"
        key_data = file(ssh_keys.value)
      }
    }

    dynamic "ssh_keys" {
      for_each = var.enable_ssh_key ? var.ssh_key_values : []
      content {
        path     = "/home/${var.admin_username}/.ssh/authorized_keys"
        key_data = ssh_keys.value
      }
    }

  }

  dynamic "os_profile_secrets" {
    for_each = var.os_profile_secrets
    content {
      source_vault_id = os_profile_secrets.value["source_vault_id"]

      vault_certificates {
        certificate_url = os_profile_secrets.value["certificate_url"]
      }
    }
  }
  
  tags = var.tags

  boot_diagnostics {
    enabled     = var.boot_diagnostics
    storage_uri  = "${var.storage_uri}"
    #storage_uri = var.boot_diagnostics ? join(",", azurerm_storage_account.vm-sa.*.primary_blob_endpoint) : ""
  }
  
  lifecycle {
prevent_destroy  = false
ignore_changes = [

 location,
 
 availability_set_id,

tags

]
}
}

resource "azurerm_virtual_machine" "vm-windows" {
  count = (var.is_windows_image || contains(tolist([var.vm_os_simple, var.vm_os_offer]), "WindowsServer")) ? var.nb_instances : 0
  name  = var.vm_name
  #computer_name                 ="${var.vm_computer_name}"
  resource_group_name           = data.azurerm_resource_group.vm.name
  location                      = coalesce(var.location, data.azurerm_resource_group.vm.location)
  availability_set_id           = azurerm_availability_set.vm.id
  vm_size                       = var.vm_size
  network_interface_ids         = [element(azurerm_network_interface.vm.*.id, count.index)]
  delete_os_disk_on_termination = var.delete_os_disk_on_termination
  license_type                  = var.license_type

  dynamic "identity" {
    for_each = length(var.identity_ids) == 0 && var.identity_type == "SystemAssigned" ? [var.identity_type] : []
    content {
      type = var.identity_type
    }
  }

  dynamic "identity" {
    for_each = length(var.identity_ids) > 0 || var.identity_type == "UserAssigned" ? [var.identity_type] : []
    content {
      type         = var.identity_type
      identity_ids = length(var.identity_ids) > 0 ? var.identity_ids : []
    }
  }

  storage_image_reference {
    id        = var.vm_os_id
    publisher = var.vm_os_id == "" ? coalesce(var.vm_os_publisher, module.os.calculated_value_os_publisher) : ""
    offer     = var.vm_os_id == "" ? coalesce(var.vm_os_offer, module.os.calculated_value_os_offer) : ""
    sku       = var.vm_os_id == "" ? coalesce(var.vm_os_sku, module.os.calculated_value_os_sku) : ""
    version   = var.vm_os_id == "" ? var.vm_os_version : ""
  }

  storage_os_disk {
    name              = "${var.vm_name}-osdisk-${count.index}"
    create_option     = "FromImage"
    caching           = "ReadWrite"
    managed_disk_type = var.storage_account_type
  }

  dynamic "storage_data_disk" {
    for_each = range(var.nb_data_disk)
    content {
      name              = "${var.vm_name}-datadisk-${count.index}-${storage_data_disk.value}"
      create_option     = "Empty"
      lun               = storage_data_disk.value
      disk_size_gb      = var.data_disk_size_gb
      managed_disk_type = var.data_sa_type
    }
  }

  dynamic "storage_data_disk" {
    for_each = var.extra_disks
    content {
      name              = "${var.vm_name}-extradisk-${count.index}-${storage_data_disk.value.name}"
      create_option     = "Empty"
      lun               = storage_data_disk.key + var.nb_data_disk
      disk_size_gb      = storage_data_disk.value.size
      managed_disk_type = var.data_sa_type
    }
  }

  os_profile {
    computer_name  = var.vm_computer_name
    admin_username = var.admin_username
    admin_password = var.admin_password
  }

  tags = var.tags

  os_profile_windows_config {
    provision_vm_agent = true
  }

  dynamic "os_profile_secrets" {
    for_each = var.os_profile_secrets
    content {
      source_vault_id = os_profile_secrets.value["source_vault_id"]

      vault_certificates {
        certificate_url   = os_profile_secrets.value["certificate_url"]
        certificate_store = os_profile_secrets.value["certificate_store"]
      }
    }
  }

  boot_diagnostics {
    enabled     = var.boot_diagnostics
    storage_uri  = "${var.storage_uri}"
   # storage_uri = var.boot_diagnostics ? join(",", azurerm_storage_account.vm-sa.*.primary_blob_endpoint) : ""
  }
  
    lifecycle {
prevent_destroy  = false
ignore_changes = [

 location,
 
 availability_set_id,

tags

]
}
}

resource "azurerm_availability_set" "vm" {
  name                         = "${var.vm_name}-avset"
  resource_group_name          = data.azurerm_resource_group.vm.name
  location                     = coalesce(var.location, data.azurerm_resource_group.vm.location)
  platform_fault_domain_count  = 2
  platform_update_domain_count = 2
  managed                      = true
  tags                         = var.tags
  lifecycle {
prevent_destroy  = false
ignore_changes = [

 location
 ]
 }
}

resource "azurerm_public_ip" "vm" {
  count               = var.nb_public_ip
  name                = "${var.vm_name}-pip-${count.index}"
  resource_group_name = data.azurerm_resource_group.vm.name
  location            = coalesce(var.location, data.azurerm_resource_group.vm.location)
  allocation_method   = var.allocation_method
  sku                 = var.public_ip_sku
  domain_name_label   = element(var.public_ip_dns, count.index)
  tags                = var.tags
}

// Dynamic public ip address will be got after it's assigned to a vm
data "azurerm_public_ip" "vm" {

  count               = var.nb_public_ip
  name                = azurerm_public_ip.vm[count.index].name
  resource_group_name = data.azurerm_resource_group.vm.name
  depends_on          = [azurerm_virtual_machine.vm-linux, azurerm_virtual_machine.vm-windows]
}

/*resource "azurerm_network_security_group" "vm" {
  name                = "${var.vm_name}-nsg"
  resource_group_name = data.azurerm_resource_group.vm.name
  location            = coalesce(var.location, data.azurerm_resource_group.vm.location)

  tags = var.tags
}*/
/*
resource "azurerm_network_security_rule" "vm" {
  count                       = var.remote_port != "" ? 1 : 0
  name                        = "allow_remote_${coalesce(var.remote_port, module.os.calculated_remote_port)}_in_all"
  resource_group_name         = data.azurerm_resource_group.vm.name
  description                 = "Allow remote protocol in from all locations"
  priority                    = 101
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = coalesce(var.remote_port, module.os.calculated_remote_port)
  source_address_prefixes     = var.source_address_prefixes
  destination_address_prefix  = "*"
  network_security_group_name = azurerm_network_security_group.vm.name
}*/

resource "azurerm_network_interface" "vm" {
  count                         = var.nb_instances
  name                          = "${var.vm_name}-nic-${count.index}"
  resource_group_name           = data.azurerm_resource_group.vm.name
  location                      = coalesce(var.location, data.azurerm_resource_group.vm.location)
  enable_accelerated_networking = var.enable_accelerated_networking

  ip_configuration {
    name                          = "${var.vm_name}-ip-${count.index}"
    subnet_id                     = var.vnet_subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = length(azurerm_public_ip.vm.*.id) > 0 ? element(concat(azurerm_public_ip.vm.*.id, tolist([""])), count.index) : ""
  }
lifecycle {
prevent_destroy  = false
ignore_changes = [

 location
 ]
 }
  tags = var.tags
}

/*resource "azurerm_network_interface_security_group_association" "test" {
  count                     = var.nb_instances
  network_interface_id      = azurerm_network_interface.vm[count.index].id
  network_security_group_id = azurerm_network_security_group.vm.id
}*/


resource "azurerm_dev_test_global_vm_shutdown_schedule" "example" {
count                     = var.nb_instances 
  virtual_machine_id = data.azurerm_virtual_machine.example.id
  location           = coalesce(var.location, data.azurerm_resource_group.vm.location)
  enabled            = var.shutdown_schedule_enabled 
  daily_recurrence_time = var.daily_recurrence_time  
  timezone              = var.timezone

  notification_settings {
    enabled         = var.auto_shutdown_enabled
    time_in_minutes = var.time
    email = var.email
  }
   lifecycle {
prevent_destroy  = false
ignore_changes = [

 location
 ]
 }
}

/*variable "shutdown_schedule_enabled" {
type = bool
  default = null
}


variable "daily_recurrence_time" {
  default = "2200"
}

variable "timezone" {
  default = "India Standard Time"
}

variable "email" {
  default = "muhammad.fasil-e@capgemini.com"
}*/




data "azurerm_virtual_machine" "example"{
#count                = length(var.vm_name)
name                 =var.vm_name
resource_group_name = data.azurerm_resource_group.vm.name
depends_on  = [azurerm_virtual_machine.vm-linux,azurerm_virtual_machine.vm-windows ]
}




/*
resource "azurerm_dev_test_lab" "example" {
 count = var.nb_instances
  name                          = "${var.vm_name}-dfgfg-${count.index}"
  location            = coalesce(var.location, data.azurerm_resource_group.vm.location)
  resource_group_name = data.azurerm_resource_group.vm.name
}

resource "azurerm_dev_test_schedule" "example" {
 count = var.nb_instances
  name                          = "${var.vm_name}-autostart-${count.index}"
  location            = coalesce(var.location, data.azurerm_resource_group.vm.location)
  resource_group_name = data.azurerm_resource_group.vm.name
  
          lab_name =                 length(azurerm_dev_test_lab.example.*.name) > 0 ? element(concat(azurerm_dev_test_lab.example.*.name, tolist([""])), count.index) : ""
  
            

  weekly_recurrence {
    time      = "1100"
    week_days = ["Monday", "Tuesday"]
  }

  time_zone_id = "Pacific Standard Time"
  task_type    = "LabVmsStartupTask"

  notification_settings {
  }

  tags = {
    environment = "Production"
  }
}*/