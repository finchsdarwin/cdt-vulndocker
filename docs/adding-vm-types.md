# Adding a New VM Type

This guide walks through adding a completely new set of VMs to the infrastructure. For example, adding database servers, mail servers, or a second set of Red Team machines.

## Checklist

Use this as a quick reference. Each step is explained in detail below.

### OpenTofu (Infrastructure)

- [ ] **Copy an existing `instances-*.tf` file** and rename it (e.g., `instances-blue-database.tf`)
- [ ] **Update the `locals` block** — set a unique prefix, pick a non-overlapping `ip_base`, and configure image/flavor/security group
- [ ] **Rename all resources and data sources** — search-and-replace the old prefix with your new one
- [ ] **Set the correct provider** — `openstack.main`, `openstack.blue`, or `openstack.red`
- [ ] **Set the correct `depends_on`** — include the RBAC policy for blue/red projects, or leave empty for main project
- [ ] **Update the `user_data`** — point to the right cloud-init script (or create a new one)
- [ ] **Rename all outputs** — match them to your new resource names
- [ ] **Add variables at the top of your instance file** — count, optional hostname list, optional image variable
- [ ] **Add or reuse a security group** in `security.tf` if the new VMs need different firewall rules
- [ ] **Run `tofu plan`** — verify only your new resources appear (no changes to existing ones)
- [ ] **Run `tofu apply`** — create the VMs

### Inventory Script (`import-tofu-to-ansible.py`)

- [ ] **Add output parsing** — extract the new `*_names`, `*_ips`, `*_floating_ips` arrays
- [ ] **Add inventory group** — write a new `[group_name]` section with the host entries
- [ ] **Add to hierarchy groups** — include in `[blue_team:children]`, `[linux_members:children]`, etc. as appropriate
- [ ] **Add group variables** — connection settings (`ansible_user`, `ansible_password`, etc.)
- [ ] **Run `python3 import-tofu-to-ansible.py`** — verify the new group appears in the generated inventory

### Ansible (Configuration)

- [ ] **Create a playbook** in `ansible/playbooks/` targeting the new inventory group
- [ ] **Create a role** in `ansible/roles/` if the configuration is complex
- [ ] **Add group variables** in `ansible/group_vars/<group_name>.yml` if needed
- [ ] **Add to `site.yml`** — import the new playbook in the right order
- [ ] **Run the playbook** — test against the new VMs

---

## Step-by-Step Guide

### 1. Copy an Existing Instance File

Pick the instance file closest to your new VM type as a starting point:

| Starting File | Best For |
|---------------|----------|
| `instances-blue-linux.tf` | Linux VMs in Blue Team project |
| `instances-blue-windows.tf` | Windows VMs in Blue Team project |
| `instances-scoring.tf` | VMs in Main/Grey Team project |
| `instances-red-kali.tf` | VMs in Red Team project |

```bash
cd opentofu
cp instances-blue-linux.tf instances-blue-database.tf
```

### 2. Update the `locals` Block

Open your new file and edit the `locals` block. This is the only place you define the core parameters:

```hcl
locals {
  blue_db = {
    count          = var.blue_database_count
    image_name     = var.debian_image_name
    flavor         = var.flavor_name
    keypair        = var.keypair
    security_group = openstack_networking_secgroup_v2.blue_linux_sg.name
    ip_base        = 60  # VMs get 10.10.10.61, .62, .63, ...
    volume_size    = 120
  }
}
```

**Choosing an `ip_base`**: Pick a value that doesn't overlap with existing ranges:

```
Currently used:
  10  → Scoring       (10.10.10.11 - 10.10.10.20)
  20  → Blue Windows  (10.10.10.21 - 10.10.10.99)
  100 → Blue Linux    (10.10.10.101 - 10.10.10.149)
  150 → Red Kali      (10.10.10.151 - 10.10.10.249)

Available gaps:
  50-99   → up to 49 VMs (e.g., ip_base = 50)
  60-99   → up to 39 VMs (e.g., ip_base = 60)
```

The formula is `10.10.10.<ip_base + count.index + 1>`, so `ip_base = 60` with 3 VMs gives `.61`, `.62`, `.63`.

### 3. Rename Resources and Outputs

Do a search-and-replace across the entire file. For example, if you copied `instances-blue-linux.tf`:

| Find | Replace With |
|------|-------------|
| `blue_linux` | `blue_db` |
| `debian` (data source name) | `db_image` |
| `blue_linux_fip` | `blue_db_fip` |
| `blue_linux_fip_assoc` | `blue_db_fip_assoc` |

Make sure every `resource`, `data`, and `output` block has a unique name. OpenTofu will error if two resources share a name.

### 4. Set the Provider and `depends_on`

The provider determines which OpenStack project owns the VMs:

```hcl
resource "openstack_compute_instance_v2" "blue_db" {
  provider = openstack.blue  # Blue Team project

  depends_on = [
    openstack_networking_rbac_policy_v2.share_with_blue  # Required for blue/red projects
  ]
}
```

| Project | Provider | `depends_on` |
|---------|----------|-------------|
| Main (Grey) | `openstack.main` | `[]` (empty — main owns the network) |
| Blue | `openstack.blue` | `[openstack_networking_rbac_policy_v2.share_with_blue]` |
| Red | `openstack.red` | `[openstack_networking_rbac_policy_v2.share_with_red]` |

The floating IP resources must use the **same provider** as the compute instance.

### 5. Update the User Data

Point to the appropriate cloud-init script:

| OS | Script | What It Does |
|----|--------|-------------|
| Linux (Debian/Ubuntu) | `debian-userdata.sh` | Creates `cyberrange` user, enables SSH password auth |
| Windows | `windows-userdata.ps1` | Enables WinRM for Ansible management |
| Kali | `kali-userdata.sh` | Creates user, installs xRDP with XFCE |

If your VMs need different initialization, create a new script in the `opentofu/` directory:

```hcl
user_data = templatefile("${path.module}/my-custom-userdata.sh", {
  instance_num = count.index + 1
})
```

### 6. Add Variables at the Top of Your Instance File

VM-specific variables live in the same file as the resources they configure. Add a count variable (required) and optionally a hostname list at the top of your new instance file, before the `locals` block:

```hcl
variable "blue_database_count" {
  description = "Number of Blue Team database servers"
  type        = number
  default     = 2
}

variable "blue_database_hostnames" {
  description = "Custom hostnames for Blue Team database VMs (optional)"
  type        = list(string)
  default     = ["db-primary", "db-replica"]
}
```

If you're using a different OS image, add an image variable too:

```hcl
variable "database_image_name" {
  description = "OS image for database servers"
  type        = string
  default     = "Ubuntu2404Desktop"
}
```

Shared variables like `flavor_name`, `keypair`, and `external_network` stay in `variables.tf` and are referenced by all instance files.

### 7. Add a Security Group (If Needed)

If the new VMs need different firewall rules, add a security group in `security.tf`. Otherwise, reuse an existing one (like `blue_linux_sg`).

```hcl
resource "openstack_networking_secgroup_v2" "blue_db_sg" {
  provider    = openstack.blue
  name        = "blue-database-sg"
  description = "Firewall rules for Blue Team database servers"
}

resource "openstack_networking_secgroup_rule_v2" "blue_db_ssh" {
  provider          = openstack.blue
  security_group_id = openstack_networking_secgroup_v2.blue_db_sg.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
}

resource "openstack_networking_secgroup_rule_v2" "blue_db_mysql" {
  provider          = openstack.blue
  security_group_id = openstack_networking_secgroup_v2.blue_db_sg.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 3306
  port_range_max    = 3306
  remote_ip_prefix  = "10.10.10.0/24"
}
```

Then reference it in your instance file's `locals`:

```hcl
security_group = openstack_networking_secgroup_v2.blue_db_sg.name
```

### 8. Validate with `tofu plan`

```bash
source ../app-cred-openrc.sh
tofu plan
```

You should see **only** new resources being created. If existing resources show changes, something went wrong with the renaming.

### 9. Deploy with `tofu apply`

```bash
tofu apply
```

---

## Updating the Inventory Script

After `tofu apply`, your new VMs exist but the Ansible inventory doesn't know about them yet. Edit `import-tofu-to-ansible.py` to add support.

### Add Output Parsing

Find the section that extracts data from OpenTofu outputs and add your new type:

```python
# Blue Team Database VMs
blue_db_names = tofu_data.get('blue_db_names', {}).get('value', [])
blue_db_ips = tofu_data.get('blue_db_ips', {}).get('value', [])
blue_db_floating_ips = tofu_data.get('blue_db_floating_ips', {}).get('value', [])
```

The keys (`blue_db_names`, etc.) must match the output names in your `.tf` file.

### Add Inventory Group

Find where the other groups are written and add a new section:

```python
f.write("[blue_database]\n")
for name, floating_ip, internal_ip in zip(blue_db_names, blue_db_floating_ips, blue_db_ips):
    services = host_to_services.get(name, [])
    services_json = json.dumps(services)
    f.write(f"{name} ansible_host={floating_ip} internal_ip={internal_ip} host_services='{services_json}'\n")
f.write("\n")
```

### Add to Hierarchy Groups

Include your new group in the appropriate parent groups:

```python
# If these are Blue Team Linux VMs:
f.write("[blue_team:children]\n")
f.write("blue_windows\n")
f.write("blue_linux\n")
f.write("blue_database\n")    # <-- add this
f.write("\n")

f.write("[linux_members:children]\n")
f.write("blue_linux_members\n")
f.write("blue_database\n")    # <-- add this if they're Linux
f.write("red_team\n")
f.write("scoring\n")
f.write("\n")
```

### Add Group Variables

Add connection settings for the new group:

```python
f.write("[blue_database:vars]\n")
f.write("ansible_user=cyberrange\n")
f.write("ansible_password=Cyberrange123!\n")
f.write("ansible_python_interpreter=/usr/bin/python3\n")
f.write("\n")
```

### Update the Summary

Add the new type to the summary output at the end of `create_inventory()`:

```python
print(f"  Blue Database VMs:    {len(blue_db_names)}")
```

### Regenerate the Inventory

```bash
python3 import-tofu-to-ansible.py
```

Open `ansible/inventory/production.ini` and verify your new group appears with the correct hosts.

---

## Adding Ansible Configuration

### Create a Playbook

Create `ansible/playbooks/setup-database.yml`:

```yaml
---
- name: Configure Database Servers
  hosts: blue_database
  become: true
  roles:
    - database_server
```

### Create a Role (If Needed)

```bash
mkdir -p ansible/roles/database_server/{tasks,handlers,templates,defaults}
```

Create `ansible/roles/database_server/tasks/main.yml`:

```yaml
---
- name: Install MySQL
  ansible.builtin.apt:
    name: mysql-server
    state: present
    update_cache: true

- name: Start MySQL service
  ansible.builtin.service:
    name: mysql
    state: started
    enabled: true
```

### Add Group Variables (If Needed)

Create `ansible/group_vars/blue_database.yml`:

```yaml
---
mysql_port: 3306
mysql_bind_address: "0.0.0.0"
```

### Add to `site.yml`

Edit `ansible/playbooks/site.yml` to include the new playbook in the correct order:

```yaml
- import_playbook: join-linux-domain.yml
- import_playbook: setup-database.yml     # <-- add after domain join
- import_playbook: create-domain-users.yml
```

### Run the Playbook

```bash
cd ansible
ansible-playbook playbooks/setup-database.yml
```

---

## Complete Example: Adding Blue Team Database Servers

Here is every file that needs to change, start to finish:

### Files to Create

| File | Purpose |
|------|---------|
| `opentofu/instances-blue-database.tf` | Variables, VM definitions, floating IPs, outputs |
| `ansible/playbooks/setup-database.yml` | Playbook targeting the new group |
| `ansible/roles/database_server/tasks/main.yml` | Role with setup tasks |
| `ansible/group_vars/blue_database.yml` | Group-specific variables (optional) |

### Files to Edit

| File | What to Change |
|------|---------------|
| `opentofu/security.tf` | Add security group if VMs need different firewall rules |
| `import-tofu-to-ansible.py` | Parse new outputs, write new inventory group, update hierarchy |
| `ansible/playbooks/site.yml` | Import the new playbook |

### Commands to Run

```bash
# 1. Deploy infrastructure
source app-cred-openrc.sh
cd opentofu
tofu plan    # Verify only new resources
tofu apply
cd ..

# 2. Regenerate inventory
python3 import-tofu-to-ansible.py

# 3. Configure VMs
cd ansible
ansible-playbook playbooks/setup-database.yml
```
