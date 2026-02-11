# OpenTofu Infrastructure

This directory contains all OpenTofu (Terraform-compatible) configuration files that define the competition infrastructure on OpenStack.

## Directory Structure

```
opentofu/
  main.tf                    - Provider configuration (OpenStack connection, project aliases)
  variables.tf               - Shared variables (network, flavor, keypair, projects, services)
  network.tf                 - Network, subnet, router, and RBAC sharing policies
  security.tf                - Security groups (firewall rules per project)
  instances-blue-windows.tf  - Blue Team Windows VMs (first VM = Domain Controller)
  instances-blue-linux.tf    - Blue Team Linux VMs
  instances-scoring.tf       - Scoring/Grey Team VMs
  instances-red-kali.tf      - Red Team Kali VMs
  outputs.tf                 - Network & shared infrastructure outputs
  windows-userdata.ps1       - Cloud-init script for Windows (enables WinRM)
  debian-userdata.sh         - Cloud-init script for Linux (creates user, enables SSH)
  kali-userdata.sh           - Cloud-init script for Kali (installs xRDP)
```

## How It Works

OpenTofu reads **all** `.tf` files in this directory as a single configuration. The file split is purely for organization.

### Multi-Project Architecture

Three OpenStack provider aliases deploy resources to different projects:

| Provider | Project | Resources |
|----------|---------|-----------|
| `openstack.main` | Grey Team (main) | Network, router, RBAC, scoring VMs |
| `openstack.blue` | Blue Team | Windows VMs, Linux VMs |
| `openstack.red` | Red Team | Kali VMs |

### Per-VM-Type Instance Files

Each VM type lives in its own `instances-*.tf` file. Every file follows the same pattern:

1. **Variables** - VM-specific inputs (count, image name, hostnames)
2. **`locals` block** - Configuration values (references variables + shared vars like flavor/keypair)
3. **Image data source** - Looks up the OS image in OpenStack Glance
4. **Compute instance** - Creates the VMs
5. **Floating IP allocation** - Reserves external IPs
6. **Floating IP association** - Attaches external IPs to VMs
7. **Outputs** - Exposes names, internal IPs, and floating IPs

This pattern makes it straightforward to add new VM types by copying an existing file. See [Adding a New VM Type](../docs/adding-vm-types.md) for a step-by-step guide.

### IP Address Scheme

Each VM type gets a dedicated range within the `10.10.10.0/24` subnet, controlled by the `ip_base` value in each file's `locals` block:

| VM Type | `ip_base` | IP Range | Max VMs |
|---------|-----------|----------|---------|
| Scoring (Grey) | 10 | 10.10.10.11 - 10.10.10.20 | 10 |
| Blue Windows | 20 | 10.10.10.21 - 10.10.10.99 | 79 |
| Blue Linux | 100 | 10.10.10.101 - 10.10.10.149 | 49 |
| Red Kali | 150 | 10.10.10.151 - 10.10.10.249 | 99 |

The formula is: `fixed_ip = 10.10.10.<ip_base + count.index + 1>`

When adding a new VM type, pick an `ip_base` that doesn't overlap with existing ranges.

### Outputs

VM-type outputs (names, IPs, floating IPs) live in the same `instances-*.tf` file as the resources they reference. Network and shared infrastructure outputs live in `outputs.tf`.

The `import-tofu-to-ansible.py` script reads these outputs to generate the Ansible inventory.

## Common Commands

```bash
# Load credentials (required before every session)
source ../app-cred-openrc.sh

# Initialize (first time or after adding providers)
tofu init

# Preview changes
tofu plan

# Deploy
tofu apply

# View outputs
tofu output
tofu output -json

# Destroy everything
tofu destroy

# Rebuild a single VM type
tofu taint 'openstack_compute_instance_v2.blue_linux[0]'
tofu apply
```

## Customization

### Changing VM Counts

Edit the count variable in the relevant instance file (e.g., `instances-blue-linux.tf`):

```hcl
variable "blue_linux_count" {
  default = 4  # Change this number
}
```

Then run `tofu plan` and `tofu apply`.

### Changing VM Images or Flavors

Edit the image variable in the relevant instance file, or the shared `flavor_name` in `variables.tf`.

### Adding a New VM Type

See [docs/adding-vm-types.md](../docs/adding-vm-types.md) for a complete walkthrough and checklist.

### Adding Custom Hostnames

Edit the hostname list variable in the relevant instance file (e.g., `instances-blue-linux.tf`):

```hcl
variable "blue_linux_hostnames" {
  default = ["webserver", "database", "mailserver"]
}
```

VMs beyond the list length get auto-generated names (e.g., `blue-linux-4`).
