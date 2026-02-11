# ==============================================================================
# BLUE TEAM LINUX VMS
# ==============================================================================
# Linux VMs for Blue Team to defend (web servers, databases, etc.)
# These join the Windows domain via Ansible and live in the BLUE project.
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

variable "blue_linux_count" {
  description = "Number of Blue Team Linux VMs"
  type        = number
  default     = 5
}

variable "debian_image_name" {
  description = "Name of the Linux image in OpenStack Glance"
  type        = string
  default     = "Ubuntu2404Desktop"

  # NOTE: Despite the variable name saying "debian", you can use any Linux image.
  # The default uses Ubuntu with LXQT desktop pre-installed.
  #
  # Common Linux images:
  # - Ubuntu2404Desktop (Ubuntu 24.04 with LXQT)
  # - debian-trixie-amd64-cloud
  # - kali-2024 (for Red Team attack machines)
}

variable "blue_linux_hostnames" {
  description = "Custom hostnames for Blue Team Linux VMs (optional)"
  type        = list(string)
  default     = ["webserver", "comms"]
}


# ------------------------------------------------------------------------------
# Configuration — edit these values when copying this file for a new VM type
# ------------------------------------------------------------------------------
locals {
  blue_linux = {
    count          = var.blue_linux_count
    image_name     = var.debian_image_name
    flavor         = var.flavor_name
    keypair        = var.keypair
    security_group = openstack_networking_secgroup_v2.blue_linux_sg.name
    ip_base        = 100 # VMs get 10.10.10.101, .102, .103, ...
    volume_size    = 80
  }
}


# ------------------------------------------------------------------------------
# Image data source
# ------------------------------------------------------------------------------
data "openstack_images_image_v2" "debian" {
  name        = local.blue_linux.image_name # "Ubuntu2404Desktop"
  most_recent = true
  # Used for Blue Team Linux servers
}


# ------------------------------------------------------------------------------
# Compute instance
# ------------------------------------------------------------------------------
resource "openstack_compute_instance_v2" "blue_linux" {
  # provider must be static — OpenTofu cannot resolve provider from a local
  provider = openstack.blue

  count = local.blue_linux.count

  name = length(var.blue_linux_hostnames) > count.index ? var.blue_linux_hostnames[count.index] : "blue-linux-${count.index + 1}"

  image_name      = local.blue_linux.image_name
  flavor_name     = local.blue_linux.flavor
  key_pair        = local.blue_linux.keypair
  security_groups = [local.blue_linux.security_group]
  # Uses Blue Team Linux security group (SSH, RDP)

  network {
    uuid        = openstack_networking_network_v2.cdt_net.id
    fixed_ip_v4 = format("10.10.10.%d", local.blue_linux.ip_base + count.index + 1)
    # Blue Linux IPs: 10.10.10.101, 10.10.10.102, ...
  }

  block_device {
    uuid                  = data.openstack_images_image_v2.debian.id
    source_type           = "image"
    volume_size           = local.blue_linux.volume_size
    destination_type      = "volume"
    delete_on_termination = true
  }

  # user_data varies per VM type — keep inline
  user_data = templatefile("${path.module}/debian-userdata.sh", {
    instance_num = count.index + 1
  })
  # CLOUD-INIT USER DATA:
  # This bash script runs on first boot to configure the VM.
  # It creates the cyberrange user and enables SSH password auth.
  #
  # TEMPLATEFILE EXPLAINED:
  # templatefile() reads a file and replaces variables like ${instance_num}
  # with actual values. Each VM gets its own instance number (1, 2, 3...).
  #
  # The script writes the instance number to /etc/goad/instance_num
  # which Ansible can read later for VM-specific configuration.

  # depends_on must be static — cannot use locals
  depends_on = [
    openstack_networking_rbac_policy_v2.share_with_blue
  ]
}


# ------------------------------------------------------------------------------
# Floating IP allocation
# ------------------------------------------------------------------------------
resource "openstack_networking_floatingip_v2" "blue_linux_fip" {
  provider   = openstack.blue
  count      = local.blue_linux.count
  pool       = var.external_network
  depends_on = [openstack_compute_instance_v2.blue_linux]
}


# ------------------------------------------------------------------------------
# Floating IP association
# ------------------------------------------------------------------------------
resource "openstack_networking_floatingip_associate_v2" "blue_linux_fip_assoc" {
  provider    = openstack.blue
  count       = local.blue_linux.count
  floating_ip = openstack_networking_floatingip_v2.blue_linux_fip[count.index].address
  port_id     = openstack_compute_instance_v2.blue_linux[count.index].network[0].port
  # Uses the auto-created port from the compute instance (Neutron networking API)
}


# ------------------------------------------------------------------------------
# Outputs
# ------------------------------------------------------------------------------
output "blue_linux_names" {
  description = "Hostnames of Blue Team Linux VMs"
  value       = openstack_compute_instance_v2.blue_linux[*].name
  # Result: ["webserver", "blue-linux-2"]
}

output "blue_linux_ips" {
  description = "Internal IPs of Blue Team Linux VMs"
  value       = openstack_compute_instance_v2.blue_linux[*].network[0].fixed_ip_v4
  # Result: ["10.10.10.101", "10.10.10.102"]
  #
  # BLUE TEAM DEFENSE TIPS:
  # - Check /var/log/auth.log for SSH brute force attempts
  # - Monitor web server logs for SQL injection, XSS attempts
  # - Use 'netstat -tulpn' to see what ports are exposed
  # - Run 'ps aux' to check for suspicious processes
}

output "blue_linux_floating_ips" {
  description = "Floating IPs of Blue Team Linux VMs"
  value       = openstack_networking_floatingip_v2.blue_linux_fip[*].address
  # Result: ["100.65.x.x", "100.65.x.x"]
  #
  # ACCESS BLUE LINUX VMs:
  # SSH: ssh -J sshjump@ssh.cyberrange.rit.edu cyberrange@<floating_ip>
  # RDP (xRDP): Same tunnel method as Windows
}
