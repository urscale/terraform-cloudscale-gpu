# terraform-cloudscale-gpu
Using Terraform to dynamically manage cloudscale.ch GPU resources

## Introduction
Terraform example to spawn a cloudscale.ch GPU instance on-demand, connect
a persistant data volume, launch ComfyUI living on that persistent volume,
and providing the user with the SSH port-forwarding command to access the
ComfyUI instance at http://127.0.0.1:8818

Teardown and deletion of the pricey GPU instance with a single command, while
leaving the data volume intact for future use.

## Usage
### Launching a GPU instance
- `export CLOUDSCALE_API_TOKEN='d34db33f'`
- `terraform init`
- `terraform apply`

### Remove GPU instance, while keeping the data volume
- `terraform apply -var gpu=false`
