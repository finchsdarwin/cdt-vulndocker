# ==============================================================================
# OUTPUTS - Network & Shared Infrastructure
# ==============================================================================
# Outputs display useful information after 'tofu apply' completes.
# They also make values available to other tools (like our Python script).
#
# HOW OUTPUTS WORK:
# - Defined here, displayed after apply
# - View anytime with: tofu output
# - Get JSON format with: tofu output -json
# - Access specific output: tofu output blue_windows_names
#
# WHY OUTPUTS MATTER FOR CTF:
# - See all VM IPs without opening OpenStack dashboard
# - Pass information to Ansible for automated configuration
# - Quick reference during competition for scoring checks
# - Essential for the inventory generator script
#
# OUTPUT ORGANIZATION:
# VM-type outputs live in their respective instance files:
#   instances-scoring.tf        <- Scoring (Grey Team) outputs
#   instances-blue-windows.tf   <- Blue Team Windows outputs + DC outputs
#   instances-blue-linux.tf     <- Blue Team Linux outputs
#   instances-red-kali.tf       <- Red Team Kali outputs
#
# This file contains shared infrastructure outputs only.
#
# DOCUMENTATION:
# - OpenTofu Outputs: https://opentofu.org/docs/language/values/outputs/
# - Terraform Outputs: https://developer.hashicorp.com/terraform/language/values/outputs
#
# ==============================================================================


# ##############################################################################
#                         NETWORK OUTPUTS
# ##############################################################################
# Information about the shared network infrastructure.

output "network_id" {
  description = "ID of the shared network"
  value       = openstack_networking_network_v2.cdt_net.id
  # Used internally by OpenStack to identify the network
  # Useful for debugging or adding more VMs manually
}

output "subnet_id" {
  description = "ID of the subnet"
  value       = openstack_networking_subnet_v2.cdt_subnet.id
}

output "subnet_cidr" {
  description = "CIDR block of the subnet"
  value       = openstack_networking_subnet_v2.cdt_subnet.cidr
  # Result: "10.10.10.0/24"
  #
  # This is the IP range all VMs share. Since Red Team is on the same
  # network as Blue Team, they can directly attack each other!
}


# ==============================================================================
# EXAMPLE OUTPUT AFTER 'tofu apply'
# ==============================================================================
#
# After running 'tofu apply', you'll see something like:
#
#   Apply complete! Resources: 15 added, 0 changed, 0 destroyed.
#
#   Outputs:
#
#   blue_linux_floating_ips = [
#     "100.65.4.61",
#     "100.65.4.62",
#   ]
#   blue_linux_ips = [
#     "10.10.10.101",
#     "10.10.10.102",
#   ]
#   blue_linux_names = [
#     "webserver",
#     "blue-linux-2",
#   ]
#   blue_windows_floating_ips = [
#     "100.65.4.51",
#     "100.65.4.52",
#   ]
#   blue_windows_ips = [
#     "10.10.10.21",
#     "10.10.10.22",
#   ]
#   blue_windows_names = [
#     "dc01",
#     "blue-win-2",
#   ]
#   domain_controller_floating_ip = "100.65.4.51"
#   domain_controller_ip = "10.10.10.21"
#   red_kali_floating_ips = [
#     "100.65.4.71",
#     "100.65.4.72",
#   ]
#   red_kali_ips = [
#     "10.10.10.151",
#     "10.10.10.152",
#   ]
#   red_kali_names = [
#     "red-kali-1",
#     "red-kali-2",
#   ]
#   scoring_floating_ips = [
#     "100.65.4.11",
#   ]
#   scoring_ips = [
#     "10.10.10.11",
#   ]
#   scoring_names = [
#     "scoring-1",
#   ]
#
# ==============================================================================
# HOW THE INVENTORY SCRIPT USES THESE OUTPUTS
# ==============================================================================
#
# The import-tofu-to-ansible.py script runs 'tofu output -json' and parses
# this data to create the Ansible inventory. It maps:
#
#   OpenTofu Output          ->  Ansible Inventory Group
#   ----------------             ----------------------
#   scoring_*                ->  [scoring]
#   blue_windows_* (first)   ->  [windows_dc]
#   blue_windows_* (rest)    ->  [blue_windows_members]
#   blue_linux_*             ->  [blue_linux_members]
#   red_kali_*               ->  [red_team]
#
# This allows Ansible to run different playbooks for different teams!
#
# ==============================================================================


# ------------------------------------------------------------------------------
# SERVICE CONFIGURATION OUTPUT
# ------------------------------------------------------------------------------
# Exports service mappings for the inventory generation script.
# The script reads this to create Ansible service groups.

output "service_hosts" {
  description = "Service to hostname mappings for Ansible inventory generation"
  value       = var.service_hosts
}
