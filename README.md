# terraform-workspaces-advanced

Multi-environment AWS infrastructure using Terraform workspaces — dev, staging, and production from one codebase, with SSM-only access (no SSH), per-environment resource counts, KMS encryption, and production guardrails.

## Concept

One set of `.tf` files, three isolated environments via Terraform workspaces. Each workspace reads its own config from a central map and writes to its own state file in S3.

| Workspace | EC2 | DynamoDB | S3 | Instance type |
|-----------|-----|----------|----|---------------|
| dev | 1 | 1 | 1 | t2.micro |
| staging | 2 | 1 | 1 | t2.micro |
| prod | 2 | 2 | 2 | t2.micro |

## Architecture (per workspace)

```
┌──────────────────────── VPC (per workspace) ──────────────────────-──┐
│                                                                      │
│  Public Subnets                  Private Subnets                     │
│  ├─ NAT Gateway                  ├─ server-<env>-1  (t2.micro)       │
│  └─ Internet Gateway             │   └─ EBS volume attached          │
│                                  ├─ server-<env>-2  (staging/prod)   │
│                                  │                                   │
│                                  Access: SSM Session Manager ONLY    │
│                                  (no SSH, no public IPs, port 22     │
│                                   closed everywhere)                 │
└──────────────────────────────────────────────────────────────────────┘

AWS-managed services (encrypted with KMS CMK):
  s3-<env>-1, s3-<env>-2 ...        (versioned, public access blocked,
                                     bucket policy: HTTPS-only)
  db-<env>-1, db-<env>-2 ...        (DynamoDB, on-demand capacity,
                                     encryption, PITR-ready)
```

## Design principles

- **Terraform = what exists, Ansible = what's on it.** No user-data scripts here; servers arrive clean and get configured by Ansible later.
- **SSM over SSH.** No key pairs, no open port 22, no public IPs on EC2. Connect with `aws ssm start-session`.
- **Per-environment config in one map** (`locals.tf`) keyed by `terraform.workspace` — adding an env = adding a map entry.
- **Guardrails.** Workspace names are validated (only dev/staging/prod allowed); prod storage resources carry `prevent_destroy`.
- **Encryption everywhere.** KMS customer-managed key per workspace encrypts S3 and DynamoDB.
- **Tagged for battle.** Every resource gets Project/Environment/ManagedBy via provider `default_tags`.

## Project structure

```
.
├── versions.tf        # Version pinning
├── variables.tf       # Inputs (region, project name, CIDRs)
├── providers.tf       # AWS provider + default tags
├── backend.tf         # Partial S3 backend
├── backend.hcl        # Backend config (gitignored)
├── locals.tf          # Per-workspace config map + workspace validation
├── data.tf            # Dynamic Ubuntu AMI + AZ discovery
├── iam.tf             # IAM role/instance profile for SSM
├── main.tf            # VPC, SGs, EC2, EBS, S3, DynamoDB, KMS
├── outputs.tf         # IDs, names, ARNs
└── bootstrap/         # One-time S3 state bucket (from basic project)
```

## Prerequisites

- Terraform >= 1.9.0
- AWS CLI configured
- SSM Agent reachable (Ubuntu AWS AMIs include it; otherwise install via Ansible)

## Usage

### 1. Bootstrap state backend (one time)

```bash
cd bootstrap
terraform init
terraform apply
cd ..
```

### 2. Init once

```bash
terraform init -backend-config=backend.hcl
```

State keys are `env:/<workspace>/terraform.tfstate` — each workspace is automatically isolated.

### 3. Work with an environment

```bash
terraform workspace new dev        # first time only
terraform workspace select dev     # or switch later

terraform plan
terraform apply
```

Repeat for `staging` and `prod`.

### 4. Connect to an instance (no SSH keys)

```bash
aws ssm start-session --target <instance-id>
```

Find targets:

```bash
terraform output instance_ids
```

### 5. Tear down an environment

```bash
terraform workspace select dev
terraform destroy                   # dev/staging destroy cleanly
# prod storage has prevent_destroy guardrails — remove them intentionally if needed
```

## Guardrails explained

| Guardrail | Effect |
|-----------|--------|
| Workspace validation | `terraform workspace new test` works, but plan fails — only dev/staging/prod are valid |
| `prevent_destroy` (prod) | `terraform destroy` on prod S3/DynamoDB errors instead of deleting data |
| No public IPs on EC2 | Compromised server cannot be reached from the internet |
| HTTPS-only bucket policy | Buckets refuse non-TLS requests |

## What's intentionally left out

- **User data scripts** — Ansible will handle configuration management
- **SSH/key pairs** — replaced by SSM Session Manager
- **CI workflows** — manual plan/apply for now; workflows come in a later project
- **Cross-workspace state sharing** — planned as a phase-2 exercise (shared network workspace)
