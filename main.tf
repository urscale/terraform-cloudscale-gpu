terraform {
  required_providers {
    cloudscale = {
      source = "cloudscale-ch/cloudscale"
    }
  }
}

# "On/off switch to spawn/destroy a GPU node, while leaving data volume in place
variable "gpu" {
  type    = bool
  default = true
}

# Define our GPU node
resource "cloudscale_server" "cloudscale_gpu_vm" {
  # If gpu is true, count is 1 (exists). If false, count is 0 (absent).
  count          = var.gpu ? 1 : 0
  name           = "cloudscale-gpu-vm"
  flavor_slug    = "gpu1-96-24-1-200"
  image_slug     = "ubuntu-22.04"
  zone_slug      = "lpg1"
  volume_size_gb = 50
  ssh_keys       = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFdtTp1Dyr6g/ZHulhof3AvTvS0SWUcfjHOr/0rdzKLW gandalf@ignore.net"]
  user_data = <<-YAML
    #cloud-config

    # Though adding over a minute to bootstrapping due to > 300 package
    # upgrades (plus a reboot), keep our GPU node up-to-date
    package_update: true
    package_upgrade: true
    package_reboot_if_required: true

    # Since the volume only gets attached after creation of the server has
    # completed, configure some systemd jobs to take care of mounting our
    # data volume once it's been attached
    write_files:
      - path: /etc/systemd/system/mount-opt.service
        permissions: '0644'
        content: |
          [Unit]
          Description=Wait for /dev/sdc1 to appear, then mount to /opt
          After=local-fs.target
          Wants=local-fs.target

          [Service]
          Type=simple
          ExecStart=/bin/bash -c 'while [ ! -b /dev/sdc1 ]; do sleep 1; done; mount /dev/sdc1 /opt'

          [Install]
          WantedBy=multi-user.target

      # Again, we need to wait for the above volume mount to complete before
      # launching our ComfyUI instance on it
      - path: /etc/systemd/system/comfy.service
        permissions: '0644'
        content: |
          [Unit]
          Description=Wait for /opt to appear, then launch ComfyUI
          After=mount-opt.service
          Wants=mount-opt.service

          [Service]
          Type=simple
          ExecStart=/bin/bash -c 'while ! mountpoint -q /opt; do sleep 1; done; sudo -u ubuntu bash -c "source /opt/venv/bin/activate && cd /opt/ComfyUI && exec python3 main.py"'

          [Install]
          WantedBy=multi-user.target

    packages:
      - python3-venv
      - python3-pip
      - nvidia-driver-580
      - nvidia-cuda-toolkit
      - nvtop
      - ocl-icd-opencl-dev

    runcmd:
      # Call nvidia-smi to initialize the NVIDIA driver
      # Not really needed when we perform a reboot in the context of package
      # upgrades above, but rather be safe our driver is there in all
      # scenarios
      - /usr/bin/nvidia-smi
      # Configure & launch systemd services defined in write_files that will:
      # - Mount data volume (Terraform attaches our volume only after cloud-init)
      # - Launch ComfyUI from data volume once /opt is mounted
      - systemctl daemon-reload
      - systemctl enable mount-opt.service comfy.service
      - systemctl start mount-opt.service comfy.service
  YAML
}

# Define persistent data volume
resource "cloudscale_volume" "cloudscale_data_volume" {
  name         = "my-precious"
  size_gb      = 1024
  type         = "ssd"

  # Use a conditional to pass the server ID only if the server is enabled
  # If gpu is false, it sends an empty list [], which detaches the volume
  server_uuids = var.gpu ? [cloudscale_server.cloudscale_gpu_vm[0].id] : []

  # Safeguard: Prevent Terraform from deleting our precious data. EVER.
  lifecycle {
    prevent_destroy = true
  }
}

# Print server IP
output "cloudscale_gpu_vm_ip" {
  description = "Public IP"
  value       = try(cloudscale_server.cloudscale_gpu_vm[0].public_ipv4_address, "")
}

# Print ComfyUI connection command
output "cloudscale_gpu_vm_ssh" {
#  count          = var.gpu ? 1 : 0
  description = "ComfyUI via SSH"
  value       = "ssh -L 8188:127.0.0.1:8188 ubuntu@${try(cloudscale_server.cloudscale_gpu_vm[0].public_ipv4_address, "")} 2>/dev/null"
}

# To install ComfyUI on persistent volume in /opt/ComfyUI (required once),
# use something like:
# cd /opt
# python3 -m venv /opt/venv
# pip install comfy
# comfy --workspace=/opt/ComfyUI install --nvidia --cuda-version=12.9
# comfy launch
