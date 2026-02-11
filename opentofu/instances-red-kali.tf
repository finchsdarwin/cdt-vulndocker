# ==============================================================================
# RED TEAM KALI VMS
# ==============================================================================
# Kali Linux attack VMs for Red Team. Used to compromise Blue Team infrastructure.
# These live in the RED project.
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

variable "red_kali_count" {
  description = "Number of Red Team Kali attack VMs"
  type        = number
  default     = 10
}

variable "kali_image_name" {
  description = "Name of the Kali Linux image for Red Team"
  type        = string
  default     = "Kali2025"
  # Run 'openstack image list' to see available images
}


# ------------------------------------------------------------------------------
# Configuration — edit these values when copying this file for a new VM type
# ------------------------------------------------------------------------------
locals {
  red_kali = {
    count          = var.red_kali_count
    image_name     = var.kali_image_name
    flavor         = var.flavor_name
    keypair        = var.keypair
    security_group = openstack_networking_secgroup_v2.red_linux_sg.name
    ip_base        = 150 # VMs get 10.10.10.151, .152, .153, ...
    volume_size    = 80
  }
}


# ------------------------------------------------------------------------------
# Image data source
# ------------------------------------------------------------------------------
data "openstack_images_image_v2" "kali" {
  name        = local.red_kali.image_name # "kali-2024"
  most_recent = true
  # Used for Red Team attack VMs
  #
  # KALI LINUX:
  # Pre-loaded with penetration testing tools:
  # - Nmap, Metasploit, Burp Suite, Wireshark
  # - Password crackers, exploit frameworks
  # - Perfect for Red Team operations!
}


# ------------------------------------------------------------------------------
# Compute instance
# ------------------------------------------------------------------------------
resource "openstack_compute_instance_v2" "red_kali" {
  # provider must be static — OpenTofu cannot resolve provider from a local
  provider = openstack.red

  count = local.red_kali.count

  name            = "red-kali-${count.index + 1}"
  image_name      = local.red_kali.image_name
  flavor_name     = local.red_kali.flavor
  key_pair        = local.red_kali.keypair
  security_groups = [local.red_kali.security_group]

  network {
    uuid        = openstack_networking_network_v2.cdt_net.id
    fixed_ip_v4 = format("10.10.10.%d", local.red_kali.ip_base + count.index + 1)
    # Red Team IPs: 10.10.10.151, 10.10.10.152, ...
  }

  block_device {
    uuid                  = data.openstack_images_image_v2.kali.id
    source_type           = "image"
    volume_size           = local.red_kali.volume_size
    destination_type      = "volume"
    delete_on_termination = true
  }

  # user_data varies per VM type — keep inline
  user_data = file("${path.module}/kali-userdata.sh")
  # Kali uses a bash script for more robust package installation
  # Installs xRDP with XFCE desktop for GUI access

  # depends_on must be static — cannot use locals
  depends_on = [
    openstack_networking_rbac_policy_v2.share_with_red
    # Network must be shared with Red project first
  ]

  # RED TEAM ATTACK WORKFLOW:
  # 1. Log into Kali VM via SSH or RDP
  # 2. Scan Blue Team IPs: nmap -sV 10.10.10.21-39
  # 3. Find vulnerable services
  # 4. Exploit and gain access
  # 5. Capture flags, maintain persistence
  #
  # Blue Team should be monitoring for these attacks!
}


# ------------------------------------------------------------------------------
# Floating IP allocation
# ------------------------------------------------------------------------------
resource "openstack_networking_floatingip_v2" "red_fip" {
  provider   = openstack.red
  count      = local.red_kali.count
  pool       = var.external_network
  depends_on = [openstack_compute_instance_v2.red_kali]
}


# ------------------------------------------------------------------------------
# Floating IP association
# ------------------------------------------------------------------------------
resource "openstack_networking_floatingip_associate_v2" "red_fip_assoc" {
  provider    = openstack.red
  count       = local.red_kali.count
  floating_ip = openstack_networking_floatingip_v2.red_fip[count.index].address
  port_id     = openstack_compute_instance_v2.red_kali[count.index].network[0].port
  # Uses the auto-created port from the compute instance (Neutron networking API)
}


# ------------------------------------------------------------------------------
# Outputs
# ------------------------------------------------------------------------------
output "red_kali_names" {
  description = "Hostnames of Red Team Kali VMs"
  value       = openstack_compute_instance_v2.red_kali[*].name
  # Result: ["red-kali-1", "red-kali-2"]
}

output "red_kali_ips" {
  description = "Internal IPs of Red Team Kali VMs"
  value       = openstack_compute_instance_v2.red_kali[*].network[0].fixed_ip_v4
  # Result: ["10.10.10.151", "10.10.10.152"]
  #
  # RED TEAM ATTACK TIPS:
  # From Kali, you can reach all Blue Team VMs:
  #   nmap -sV 10.10.10.21-39    # Scan Blue Team IP range
  #   nmap -sC -sV 10.10.10.21   # Detailed scan of DC
  #
  # Common attack vectors:
  # - SMB vulnerabilities (EternalBlue, PrintNightmare)
  # - Kerberoasting (extract service account hashes)
  # - Web app vulnerabilities (SQLi, RCE)
  # - Weak passwords on SSH/RDP
}

output "red_kali_floating_ips" {
  description = "Floating IPs of Red Team Kali VMs"
  value       = openstack_networking_floatingip_v2.red_fip[*].address
  # Result: ["100.65.x.x", "100.65.x.x"]
  #
  # ACCESS KALI VMs:
  # SSH: ssh -J sshjump@ssh.cyberrange.rit.edu kali@<floating_ip>
  # RDP: Use tunnel for graphical tools (Burp Suite, BloodHound)
}
