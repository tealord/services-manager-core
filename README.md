# Service Manager Core

## What is this?

This repository provides a **lightweight service management framework** for building, publishing, and operating Docker-based services in a **reproducible and revision-safe way**.

It is designed to simplify the full lifecycle of services:

* building Docker images locally (including multi-arch)
* publishing images to a central Docker registry
* deploying and operating services on remote servers
* documenting all running services declaratively and version-controlled

The Service Manager abstracts this process so services can be built and deployed **consistently and repeatably**, independent of local architecture.

---

## Core concept

This repository is the **core module** and is intended to be used as a **Git submodule** inside a company- or project-specific services repository.

It provides:

* reusable service templates
* build & deploy scripts
* [Infisical](https://infisical.com) integration for centralized secure handling of secrets
* [Docker Registry](https://docs.docker.com/registry/) integration for authenticated image build, push, and pull operations
* instruction on how to build your own services manager

---

## Using this module (recommended setup)

Create a new repository for a specific company or project and clone it:

```bash
git clone git@github.com:company/company-services.git
cd company-services
```

### Add the Service Manager Core as a submodule

```bash
git submodule add git@github.com:tealord/services-manager-core.git
./services-manager-core/scaffold/install.sh
```

### Server side setup

### Deploy and configure Reverse Proxy

### Deploy and configure Infisical

Infisical is used as the centralized secrets manager for all services.

#### 1. Generate initial ENCRYPTION_KEY and AUTH_SECRET

Infisical requires a persistent encryption key to protect all stored secrets.

```bash
# ENCRYPTION_KEY
openssl rand -hex 16
# AUTH_SECRET
openssl rand -base64 32
```

**Important**

* This key is a **root secret**
* It must **not** be committed to Git
* It must be **stored securely outside of this repository** (password manager, secure notes, etc.)

---

#### 2. Initial bootstrap

For the initial bootstrap, the encryption key is temporarily defined in `services.yaml`

```yaml
services:
  infisical.example.com:
    template: infisical
    host: node1.example.com
    env:
      ENCRYPTION_KEY: <generated-encryption-key>
      AUTH_SECRET: <generated-auth-secret>
      POSTGRES_PASSWORD: <password>
    networks:
      - infisical-example-com_net
```

Deploy Infisical:

```bash
./services.sh -s infisical.example.com deploy
./services.sh -s infisical.example.com start
```

## Infisical: UI setup + credentials for this repo

After deploying Infisical and logging into the UI, configure it so this repo can authenticate via Universal Auth.

### 1) Disable public signups

For production deployments, disable user self-signups:

- Open the admin UI at `https://infisical.example.com/admin`
- In **General settings**, disable **Allow user signups**

### 2) Create a project and copy the Project ID

Create (or select) the project that will store your secrets:

- **Organization** → **Overview** → **Add new Project**
- Go to **Project** → **Settings** → **General**
- Copy the **Project ID**
- Store it in your local `.env` as `INFISICAL_WORKSPACE_ID`

### 3) Create a Machine Identity (Universal Auth)

Create an organization-level machine identity for automated access (example name: `services-manager`):

- **Organization** → **Access Control** → **Machine Identities**
- **Create Organization Machine Identity**
- In the created identity, open **Universal Auth**
- Copy the **Client ID**
- Create a **Client Secret** and copy it

### 4) Grant the Machine Identity access to the project

Add the Machine Identity to your Infisical project with sufficient permissions (typically **Admin** for initial setup).

### 5) Configure this repo via `.env`

Add the following variables to your local `.env` (do not commit this file):

```bash
INFISICAL_URL=https://infisical.example.com
INFISICAL_CLIENT_ID=xxx
INFISICAL_CLIENT_SECRET=xxx
INFISICAL_WORKSPACE_ID=xxx
```

---

#### 3. Store the secret env in Infisical

Once Infisical is running:

```bash
./services.sh -s infisical.example.com infisical-set ENCRYPTION_KEY xxx
./services.sh -s infisical.example.com infisical-set AUTH_SECRET xxx
./services.sh -s infisical.example.com infisical-set POSTGRES_PASSWORD xxx
```

From this point on, Infisical can provide the secret env during deployments.

---

#### 4. Switch to Infisical-managed secret

Remove the encryption key from `services.yaml` and replace it with a reference:

```yaml
services:
  infisical.example.com:
    template: infisical
    host: node1.example.com
    env:
      ENCRYPTION_KEY:
        from: infisical
      AUTH_SECRET:
        from: infisical
      POSTGRES_PASSWORD:
        from: infisical
    networks:
      - infisical-example-com_net
```

Redeploy Infisical:

```bash
./services-manager/scripts/deploy.sh infisical.example.com
```

---

#### 5. Critical notes

* The encryption key **must be backed up externally**
* Losing the key means **all Infisical data becomes unrecoverable**
* The key **must never be regenerated**
* This bootstrap approach avoids special-case logic in the deployment code

### Deploy and configure Docker Registry

If your services repository contains **custom builds** (i.e. you build images locally and deploy them to remote hosts), you need a **Docker registry** so the remote host can pull the exact image version you built.

This repository ships a ready-to-use registry template (`docker-registry`).

#### 1. Add the registry service to `services.yaml`

Example:

```yaml
services:
  # DOCKER REGISTRY
  docker.company.com:
    template: docker-registry
    host: node1.company.com
    networks:
      - rp-node1-company-com_net
```

#### 2. Deploy and start the registry

```bash
./services.sh -s docker.company.com deploy
./services.sh -s docker.company.com start
```

#### 3. Configure registry credentials (htpasswd)

The registry uses basic auth via an `htpasswd` file on the target host.

On your machine, generate an entry (replace `docker` with your desired username):

```bash
htpasswd -Bn docker
```

Copy the output into the `htpasswd` file on the target host:

- Path: `/opt/docker/docker.company.com/auth/htpasswd`

#### 4. Configure this repo to use the registry

Add the registry access details to your local `.env` (do not commit):

```bash
# DOCKER REGISTRY
DOCKER_URL=docker.company.com
DOCKER_USER=docker
DOCKER_PASS=your-password
```

These variables are used by the `login`/`logout` flow during `push` and during remote `deploy` when a template contains a `Dockerfile`.

#### 5. (Optional) Store registry credentials in Infisical

If you want an additional layer of safety and documentation, you can also store the credentials in Infisical.

Important: This **does not replace** the local `.env` values. The Service Manager still relies on `DOCKER_URL`, `DOCKER_USER`, and `DOCKER_PASS` from `.env` for registry login/push/pull.

```bash
./services.sh -s docker.company.com infisical-set DOCKER_USER docker
./services.sh -s docker.company.com infisical-set DOCKER_PASS your-password
```

---

## Recommended structure for your services repository

```
company-services/
├── services-manager-core/   # git submodule (this repo)
├── templates/               # your custom templates
├── services.yaml            # service deployment definition
├── .env                     # infisical access tokens (NOT committed)
├── .gitignore
└── README.md
```

---

## Service definitions

All services are declared in a single `services.yaml` file.

This file:

* is fully version-controlled
* documents **what runs in production**
* contains **no secrets**, only references resolved by Infisical

Example (simplified):

```yaml
services:
  app.example.com:
    template: laravel-app
    host: node1.example.com
    version: v1.2.0
    env:
      DB_PASSWORD: ${DB_PASSWORD}
```

---

## Templates

Project- or company-specific templates can be added in:

```
templates/
```

---

## Building and publishing images

The Service Manager supports:

* native local builds
* multi-architecture builds (e.g. `linux/amd64`, `linux/arm64`)
* publishing images to your private registry

---

## Example Usage (Build and Deployment)

Typical flow:

1. resolve templates
2. fetch secrets from the secrets manager
3. build or pull Docker images
4. deploy services on the target host

```
scripts/deploy.sh -s flexidienstplan.de build
scripts/deploy.sh -s flexidienstplan.de push
scripts/deploy.sh -s flexidienstplan.de deploy
scripts/deploy.sh -s flexidienstplan.de start
```

---

## Requirements

* `docker`, `docker compose`
* `ssh` access to target hosts
* [`yq`](https://github.com/mikefarah/yq)
* `envsubst` (from `gettext`)
