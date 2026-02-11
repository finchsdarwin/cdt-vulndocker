# ==============================================================================
# SCORING VMS (Grey Team)
# ==============================================================================
# Scoring servers that monitor Blue Team services and calculate scores.
# These live in the MAIN project and are managed by Grey Team.
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

variable "scoring_count" {
  description = "Number of scoring servers to create in main project"
  type        = number
  default     = 1
}

variable "scoring_image_name" {
  description = "Name of the image for scoring servers"
  type        = string
  default     = "Ubuntu2404Desktop"
}


# ------------------------------------------------------------------------------
# Configuration — edit these values when copying this file for a new VM type
# ------------------------------------------------------------------------------
locals {
  scoring = {
    count          = var.scoring_count
    image_name     = var.scoring_image_name
    flavor         = var.flavor_name
    keypair        = var.keypair
    security_group = openstack_networking_secgroup_v2.scoring_sg.name
    ip_base        = 10 # VMs get 10.10.10.11, .12, .13, ...
    volume_size    = 80
  }
}


# ------------------------------------------------------------------------------
# Image data source
# ------------------------------------------------------------------------------
data "openstack_images_image_v2" "scoring" {
  name        = local.scoring.image_name # "Ubuntu2404Desktop"
  most_recent = true
  # Used for scoring/Grey Team servers
}


# ------------------------------------------------------------------------------
# Compute instance
# ------------------------------------------------------------------------------
resource "openstack_compute_instance_v2" "scoring" {
  # provider must be static — OpenTofu cannot resolve provider from a local
  provider = openstack.main

  count = local.scoring.count

  name            = "scoring-${count.index + 1}"
  image_name      = local.scoring.image_name
  flavor_name     = local.scoring.flavor
  key_pair        = local.scoring.keypair
  security_groups = [local.scoring.security_group]

  network {
    uuid        = openstack_networking_network_v2.cdt_net.id
    fixed_ip_v4 = format("10.10.10.%d", local.scoring.ip_base + count.index + 1)
    # Scoring IPs: 10.10.10.11, 10.10.10.12, ...
  }

  block_device {
    uuid                  = data.openstack_images_image_v2.scoring.id
    source_type           = "image"
    volume_size           = local.scoring.volume_size
    destination_type      = "volume"
    delete_on_termination = true
  }

  # user_data varies per VM type — keep inline
  user_data = templatefile("${path.module}/debian-userdata.sh", {
    instance_num = count.index + 1
  })
  # Same cloud-init script as Blue Linux VMs.
  # Scoring servers need the cyberrange user for Ansible access.

  # SCORING ENGINE:
  # This VM runs the scoring software that:
  # 1. Periodically checks if Blue Team services are up (HTTP, SSH, etc.)
  # 2. Awards points for uptime
  # 3. Displays scoreboard for all teams
  #
  # Popular scoring engines:
  # - ScoringEngine (https://github.com/scoringengine/scoringengine)
  # - Aeolus (used by National CCDC)
  # - Custom solutions

  # depends_on must be static — cannot use locals
  depends_on = []
}


# ------------------------------------------------------------------------------
# Floating IP allocation
# ------------------------------------------------------------------------------
resource "openstack_networking_floatingip_v2" "scoring_fip" {
  provider   = openstack.main
  count      = local.scoring.count
  pool       = var.external_network
  depends_on = [openstack_compute_instance_v2.scoring]
}


# ------------------------------------------------------------------------------
# Floating IP association
# ------------------------------------------------------------------------------
resource "openstack_networking_floatingip_associate_v2" "scoring_fip_assoc" {
  provider    = openstack.main
  count       = local.scoring.count
  floating_ip = openstack_networking_floatingip_v2.scoring_fip[count.index].address
  port_id     = openstack_compute_instance_v2.scoring[count.index].network[0].port
  # Uses the auto-created port from the compute instance (Neutron networking API)
}


# ------------------------------------------------------------------------------
# Outputs
# ------------------------------------------------------------------------------
output "scoring_names" {
  description = "Hostnames of scoring servers"
  value       = openstack_compute_instance_v2.scoring[*].name
  # SPLAT EXPRESSION EXPLAINED:
  # [*] is shorthand for "get this attribute from ALL items in the list"
  # Equivalent to: [for vm in openstack_compute_instance_v2.scoring : vm.name]
  #
  # Result: ["scoring-1"]
}

output "scoring_ips" {
  description = "Internal IPs of scoring servers"
  value       = openstack_compute_instance_v2.scoring[*].network[0].fixed_ip_v4
  # Gets the fixed IP from the first (index 0) network of each VM
  #
  # Result: ["10.10.10.11"]
  #
  # GREY TEAM TIP:
  # The scoring server needs to reach all Blue Team services to check uptime.
  # It will ping, HTTP, SSH, etc. to verify services are running.
}

output "scoring_floating_ips" {
  description = "Floating IPs of scoring servers"
  value       = openstack_networking_floatingip_v2.scoring_fip[*].address
  # Result: ["100.65.x.x"]
  #
  # ACCESS SCORING SERVER:
  # ssh -J sshjump@ssh.cyberrange.rit.edu cyberrange@<floating_ip>
}


# ==============================================================================
# IP ADDRESS SUMMARY
# ==============================================================================
#
#   10.10.10.11-20    =  Scoring/Grey Team (main project)   [base 10, max 10 VMs]
#   10.10.10.21-99    =  Blue Team Windows (blue project)   [base 20, max 79 VMs]
#   10.10.10.101-149  =  Blue Team Linux (blue project)     [base 100, max 49 VMs]
#   10.10.10.151-249  =  Red Team Kali (red project)        [base 150, max 99 VMs]
#
# Uses format() with arithmetic to support large VM counts without overlap.
#
# All VMs share the same 10.10.10.0/24 network via RBAC sharing.
# Each VM also gets a floating IP (100.65.x.x) for external access.
#
# ==============================================================================
# CTF ATTACK SCENARIO
# ==============================================================================
#
#   +-----------------+     Network Traffic     +-----------------+
#   |   RED TEAM      |  ===================>   |   BLUE TEAM     |
#   |   10.10.10.15x  |                         |   10.10.10.2x   |
#   |   (Kali VMs)    |                         |   10.10.10.10x  |
#   +-----------------+                         +-----------------+
#           ^                                           |
#           |              +-----------------+          |
#           +--------------+   SCORING       +----------+
#                          |   10.10.10.1x   |
#                          |   (monitors)    |
#                          +-----------------+
#
# Red attacks Blue. Scoring monitors. Blue defends and keeps services up!
#
# ==============================================================================
