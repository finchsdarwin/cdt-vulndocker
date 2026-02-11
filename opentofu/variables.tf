# ==============================================================================
# OPENTOFU VARIABLES — Shared Infrastructure
# ==============================================================================
# This file defines variables shared across multiple .tf files (network,
# security groups, providers, etc.).
#
# VM-specific variables (count, image, hostnames) live in each instance file:
#   instances-blue-windows.tf  <- blue_windows_count, windows_image_name, ...
#   instances-blue-linux.tf    <- blue_linux_count, debian_image_name, ...
#   instances-scoring.tf       <- scoring_count, scoring_image_name
#   instances-red-kali.tf      <- red_kali_count, kali_image_name
#
# DOCUMENTATION:
# - OpenTofu Variables: https://opentofu.org/docs/language/values/variables/
# - Terraform Variables (same syntax): https://developer.hashicorp.com/terraform/language/values/variables
#
# HOW VARIABLES WORK:
# 1. Each variable has a name, type, and default value
# 2. You can override defaults by:
#    - Creating a terraform.tfvars file
#    - Using -var flag: tofu apply -var="windows_count=5"
#    - Setting environment variables: TF_VAR_windows_count=5
#
# ==============================================================================

# ------------------------------------------------------------------------------
# NETWORK CONFIGURATION
# ------------------------------------------------------------------------------
# These variables define your private network settings.
# The network is where your VMs communicate with each other.

variable "network_name" {
  description = "Name for the private network (appears in OpenStack dashboard)"
  type        = string
  default     = "cdt-net"

  # TYPE EXPLANATION:
  # - string: Text value (must be in quotes)
  # - number: Numeric value (no quotes)
  # - bool: true or false
  # - list(string): A list of strings like ["a", "b", "c"]
  # - map(string): Key-value pairs like {key1 = "value1", key2 = "value2"}
}

variable "subnet_cidr" {
  description = "IP address range for the private network in CIDR notation"
  type        = string
  default     = "10.10.10.0/24"

  # CIDR NOTATION EXPLAINED:
  # - "10.10.10.0/24" means:
  #   - Network: 10.10.10.x
  #   - /24 = 256 addresses (10.10.10.0 to 10.10.10.255)
  #   - Usable IPs: 10.10.10.1 to 10.10.10.254 (first/last reserved)
  # - Common CIDR blocks:
  #   - /24 = 256 addresses (most common for small networks)
  #   - /16 = 65,536 addresses
  #   - /8 = 16,777,216 addresses
}

variable "router_name" {
  description = "Name for the router that connects your network to the internet"
  type        = string
  default     = "cdt-router"

  # ROUTER PURPOSE:
  # The router connects your private network (10.10.10.0/24) to the
  # external network (MAIN-NAT) so your VMs can reach the internet
  # and receive floating IPs for external access.
}

variable "external_network" {
  description = "Name of the external/public network in OpenStack (for internet access)"
  type        = string
  default     = "MAIN-NAT"

  # EXTERNAL NETWORK:
  # This is a pre-existing network in OpenStack that provides internet access.
  # At RIT CyberRange, this is "MAIN-NAT" with the 100.65.0.0/16 range.
  # You cannot create this - it's managed by OpenStack administrators.
}

# ------------------------------------------------------------------------------
# VM SIZE CONFIGURATION
# ------------------------------------------------------------------------------

variable "flavor_name" {
  description = "OpenStack flavor (VM size) defining CPU, RAM, and disk"
  type        = string
  default     = "medium"

  # FLAVORS EXPLAINED:
  # A "flavor" defines the virtual hardware for your VM.
  # Common flavors at RIT CyberRange:
  #   - small:  1 vCPU, 2GB RAM
  #   - medium: 2 vCPU, 4GB RAM
  #   - large:  4 vCPU, 8GB RAM
  #
  # Check available flavors:
  # - Dashboard: Compute → Instances → Launch Instance → Flavor
  # - Command: openstack flavor list
  #
  # Windows Server needs at least "medium" (4GB RAM recommended)
}

# ------------------------------------------------------------------------------
# SSH KEY CONFIGURATION
# ------------------------------------------------------------------------------

variable "keypair" {
  description = "Name of the SSH keypair in OpenStack (must be uploaded first)"
  type        = string
  default     = "CHANGEME-YourKeypairName"

  # IMPORTANT: Change this to YOUR keypair name!
  #
  # SSH KEYPAIRS:
  # 1. Your keypair must be uploaded to OpenStack BEFORE running tofu apply
  # 2. Upload location: Dashboard → Compute → Key Pairs → Import Public Key
  # 3. Use the SAME name here that you used when uploading
  #
  # Windows requires RSA keys. If you have ed25519, create an RSA key:
  #   ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa_openstack
  #
  # DOCUMENTATION:
  # https://docs.openstack.org/horizon/latest/user/configure-access-and-security-for-instances.html
}

# ------------------------------------------------------------------------------
# PROJECT CONFIGURATION (Multi-Project Grey Team)
# ------------------------------------------------------------------------------
# These variables specify which OpenStack projects to deploy resources to.
# Requires credentials with access to all three projects.

variable "main_project_id" {
  description = "OpenStack project ID for main/scoring infrastructure (e.g., cdtalpha)"
  type        = string
  default     = "CHANGEME-main-project-id"
  # Find it: openstack project show <project-name> -f value -c id
}

variable "blue_project_id" {
  description = "OpenStack project ID for Blue Team (e.g., cdtalpha-cdtbravo)"
  type        = string
  default     = "CHANGEME-blue-project-id"
}

variable "red_project_id" {
  description = "OpenStack project ID for Red Team (e.g., cdtalpha-cdtcharlie)"
  type        = string
  default     = "CHANGEME-red-project-id"
}

# ------------------------------------------------------------------------------
# SERVICE CONFIGURATION
# ------------------------------------------------------------------------------
# Map services to the hostnames that run them. This flows through to:
# 1. Ansible inventory groups ([web], [ftp], [ssh], etc.)
# 2. Scoring engine box configurations
#
# EMPTY LIST BEHAVIOR:
# - ping  = [] -> All boxes get ping checks
# - ssh   = [] -> All Linux boxes get SSH checks
# - winrm = [] -> All Windows boxes get WinRM/RDP checks
# - rdp   = [] -> All Windows boxes get RDP checks
# - Other services must be explicitly assigned
#
# EXAMPLE: To add a new web server:
# 1. Add hostname to blue_linux_hostnames (in instances-blue-linux.tf)
# 2. Add hostname to the "web" list below
# 3. Run: tofu apply && python3 import-tofu-to-ansible.py

variable "service_hosts" {
  description = "Map of services to the hostnames that run them"
  type        = map(list(string))
  default = {
    # Core services (empty = apply to all applicable hosts)
    ping  = []
    ssh   = []
    winrm = []
    rdp   = []

    # Network services
    dns  = ["dc01"]
    ldap = ["dc01"]

    # File services
    smb = ["dc01", "wks-alpha"]
    ftp = ["webserver"]

    # Application services
    web  = ["webserver"]
    sql  = ["comms"]
    mail = ["comms"]
    irc  = ["comms"]
    vnc  = []
  }
}

# ==============================================================================
# ADDING NEW VARIABLES
# ==============================================================================
# Shared variables (network, flavor, keypair, projects) go in this file.
# VM-specific variables (count, image, hostnames) go in the matching
# instances-*.tf file, so everything for a VM type is in one place.
#
# To add a variable:
#
# 1. Define it:
#    variable "my_variable" {
#      description = "What this variable does"
#      type        = string
#      default     = "default_value"
#    }
#
# 2. Use it in .tf files:
#    name = var.my_variable
#
# 3. Override the default (optional):
#    - In terraform.tfvars: my_variable = "new_value"
#    - On command line: tofu apply -var="my_variable=new_value"
#
# DOCUMENTATION:
# - Variable Types: https://opentofu.org/docs/language/expressions/types/
# - Variable Validation: https://opentofu.org/docs/language/values/variables/#custom-validation-rules
# ==============================================================================
