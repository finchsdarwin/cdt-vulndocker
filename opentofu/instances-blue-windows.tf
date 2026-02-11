# ==============================================================================
# BLUE TEAM WINDOWS VMS
# ==============================================================================
# Windows VMs for Blue Team to defend. The FIRST VM becomes the Domain Controller.
# These live in the BLUE project.
#
# HOW TO ADD A NEW VM TYPE:
# 1. Copy this file and rename it (e.g., instances-my-new-type.tf)
# 2. Update the variables and locals block with your VM type's parameters
# 3. Update resource names, data sources, and outputs (search & replace the prefix)
# 4. Adjust user_data, name logic, and depends_on as needed
# 5. Run: tofu plan   (should show only your new resources)
# See docs/adding-vm-types.md for a detailed walkthrough.
#
# DOCUMENTATION:
# - Compute Instance: https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/compute_instance_v2
# - Floating IP: https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_floatingip_v2
# - Images Data Source: https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/data-sources/images_image_v2
#
# ==============================================================================


# ------------------------------------------------------------------------------
# Variables — VM-specific settings for this file
# ------------------------------------------------------------------------------

variable "blue_windows_count" {
  description = "Number of Blue Team Windows VMs (first becomes Domain Controller)"
  type        = number
  default     = 15
}

variable "windows_image_name" {
  description = "Name of the Windows image in OpenStack Glance"
  type        = string
  default     = "WindowsServer2022"

  # VIEW AVAILABLE IMAGES:
  # 1. OpenStack Dashboard: Compute → Images
  # 2. Command line: openstack image list
  #
  # Common images at RIT CyberRange:
  # - WindowsServer2022
  # - WindowsServer2019
  # - Windows10
}

variable "blue_windows_hostnames" {
  description = "Custom hostnames for Blue Team Windows VMs (optional)"
  type        = list(string)
  default     = ["dc01", "wks-alpha", "wks-debbie"]
}


# ------------------------------------------------------------------------------
# Security group
# ------------------------------------------------------------------------------
# Security groups must live in the SAME project as the VMs that use them.

resource "openstack_networking_secgroup_v2" "blue_windows_sg" {
  provider    = openstack.blue
  name        = "blue-windows-sg"
  description = "Security group for Blue Team Windows VMs - WinRM (5985/5986) and RDP (3389)"
}

resource "openstack_networking_secgroup_rule_v2" "blue_windows_winrm_http" {
  provider          = openstack.blue
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 5985
  port_range_max    = 5985
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.blue_windows_sg.id
}

resource "openstack_networking_secgroup_rule_v2" "blue_windows_winrm_https" {
  provider          = openstack.blue
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 5986
  port_range_max    = 5986
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.blue_windows_sg.id
}

resource "openstack_networking_secgroup_rule_v2" "blue_windows_rdp" {
  provider          = openstack.blue
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 3389
  port_range_max    = 3389
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.blue_windows_sg.id
}

resource "openstack_networking_secgroup_rule_v2" "blue_windows_internal" {
  provider          = openstack.blue
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = ""
  remote_ip_prefix  = var.subnet_cidr
  security_group_id = openstack_networking_secgroup_v2.blue_windows_sg.id
}


# ------------------------------------------------------------------------------
# Configuration — edit these values when copying this file for a new VM type
# ------------------------------------------------------------------------------
locals {
  blue_win = {
    count          = var.blue_windows_count
    image_name     = var.windows_image_name
    flavor         = var.flavor_name
    keypair        = var.keypair
    security_group = openstack_networking_secgroup_v2.blue_windows_sg.name
    ip_base        = 20 # VMs get 10.10.10.21, .22, .23, ...
    volume_size    = 80
  }
}


# ------------------------------------------------------------------------------
# Image data source
# ------------------------------------------------------------------------------
data "openstack_images_image_v2" "windows" {
  name        = local.blue_win.image_name # "WindowsServer2022"
  most_recent = true
  # Returns: data.openstack_images_image_v2.windows.id
}


# ------------------------------------------------------------------------------
# Compute instance
# ------------------------------------------------------------------------------
resource "openstack_compute_instance_v2" "blue_windows" {
  # provider must be static — OpenTofu cannot resolve provider from a local
  provider = openstack.blue
  # This VM is created in the Blue Team's OpenStack project.
  # Blue Team members can see and manage it in their dashboard.
  # Red Team CANNOT see this VM in their dashboard - only network traffic!

  count = local.blue_win.count
  # count = 2 creates: blue_windows[0] (DC), blue_windows[1] (member)

  name = length(var.blue_windows_hostnames) > count.index ? var.blue_windows_hostnames[count.index] : "blue-win-${count.index + 1}"
  # CONDITIONAL NAMING:
  # If custom hostname provided, use it; otherwise auto-generate
  # Example: hostnames = ["dc01"] with count = 2
  #   VM 0: "dc01" (custom)
  #   VM 1: "blue-win-2" (auto)

  image_name      = local.blue_win.image_name
  flavor_name     = local.blue_win.flavor
  key_pair        = local.blue_win.keypair
  security_groups = [local.blue_win.security_group]
  # Uses Blue Team Windows security group (WinRM, RDP)

  network {
    uuid        = openstack_networking_network_v2.cdt_net.id
    fixed_ip_v4 = format("10.10.10.%d", local.blue_win.ip_base + count.index + 1)
    # Blue Windows IPs: 10.10.10.21, 10.10.10.22, ...
  }

  block_device {
    uuid                  = data.openstack_images_image_v2.windows.id
    source_type           = "image"
    volume_size           = local.blue_win.volume_size
    destination_type      = "volume"
    delete_on_termination = true
  }

  # user_data varies per VM type — keep inline
  user_data = file("${path.module}/windows-userdata.ps1")
  # PowerShell script that enables WinRM for Ansible management

  # depends_on must be static — cannot use locals
  depends_on = [
    openstack_networking_rbac_policy_v2.share_with_blue
    # The network must be shared with Blue project BEFORE creating VMs
  ]
}


# ------------------------------------------------------------------------------
# Floating IP allocation
# ------------------------------------------------------------------------------
resource "openstack_networking_floatingip_v2" "blue_win_fip" {
  provider   = openstack.blue
  count      = local.blue_win.count
  pool       = var.external_network
  depends_on = [openstack_compute_instance_v2.blue_windows]
}


# ------------------------------------------------------------------------------
# Floating IP association
# ------------------------------------------------------------------------------
resource "openstack_networking_floatingip_associate_v2" "blue_win_fip_assoc" {
  provider    = openstack.blue
  count       = local.blue_win.count
  floating_ip = openstack_networking_floatingip_v2.blue_win_fip[count.index].address
  port_id     = openstack_compute_instance_v2.blue_windows[count.index].network[0].port
  # Uses the auto-created port from the compute instance (Neutron networking API)
}


# ------------------------------------------------------------------------------
# Outputs
# ------------------------------------------------------------------------------
output "blue_windows_names" {
  description = "Hostnames of Blue Team Windows VMs"
  value       = openstack_compute_instance_v2.blue_windows[*].name
  # SPLAT EXPRESSION EXPLAINED:
  # [*] is shorthand for "get this attribute from ALL items in the list"
  #
  # Result: ["dc01", "blue-win-2"] (depends on blue_windows_hostnames variable)
  #
  # FIRST VM IS ALWAYS THE DOMAIN CONTROLLER!
  # Ansible uses this convention to set up Active Directory.
}

output "blue_windows_ips" {
  description = "Internal IPs of Blue Team Windows VMs"
  value       = openstack_compute_instance_v2.blue_windows[*].network[0].fixed_ip_v4
  # Result: ["10.10.10.21", "10.10.10.22"]
  #
  # BLUE TEAM DEFENSE TIPS:
  # - Monitor these IPs for suspicious connections from 10.10.10.4x (Red Team)
  # - Check Windows Event Logs for failed login attempts
  # - Watch for unusual processes or services
}

output "blue_windows_floating_ips" {
  description = "Floating IPs of Blue Team Windows VMs"
  value       = openstack_networking_floatingip_v2.blue_win_fip[*].address
  # Result: ["100.65.x.x", "100.65.x.x"]
  #
  # ACCESS BLUE WINDOWS VMs:
  # RDP: Create SSH tunnel first:
  #   ssh -L 3389:<floating_ip>:3389 sshjump@ssh.cyberrange.rit.edu
  # Then connect RDP to: localhost:3389
}

output "domain_controller_ip" {
  description = "Internal IP of the Domain Controller (first Blue Windows VM)"
  value       = var.blue_windows_count > 0 ? openstack_compute_instance_v2.blue_windows[0].network[0].fixed_ip_v4 : null
  # CONDITIONAL OUTPUT:
  # condition ? value_if_true : value_if_false
  # Returns null if no Windows VMs exist (edge case)
  #
  # Result: "10.10.10.21"
  #
  # IMPORTANT FOR CTF:
  # All domain-joined VMs use this IP for:
  # - DNS resolution (CDT.local domain)
  # - Authentication (Kerberos)
  # - Group Policy
}

output "domain_controller_floating_ip" {
  description = "Floating IP of the Domain Controller"
  value       = var.blue_windows_count > 0 ? openstack_networking_floatingip_v2.blue_win_fip[0].address : null
  # Result: "100.65.x.x"
  #
  # USE THIS TO:
  # - RDP into DC for Active Directory management
  # - Troubleshoot domain issues
  # - Check Event Viewer for attack indicators
}
