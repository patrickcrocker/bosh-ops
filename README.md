# BOSH Ops

Opinionated method to create and manage a BOSH environment.

## Overview

The `bosh-ops` repo does all the heavy lifting with a sibling `bosh-secrets` folder
for storing all the secret stuff.

Start off by cloning the `bosh-ops` folder:
```bash
$ git clone https://github.com/.../bosh-ops
```

Please note, that throughout this guide, we never `cd bosh-ops`... rather we stay in the
parent folder and execute commands from there.

If you are starting fresh, you'll need to create a `bosh-secrets` folder in the same parent folder as `bosh-ops`.
The `bosh-secrets` folder is where we store the bosh generated `creds.yml` and `state.json` as well as our base
configuration files.  Later on, we'll also utilize credhub to store certain credentials.
```bash
$ mkdir -p bosh-secrets/bosh
$ mkdir -p bosh-secrets/pcf
$ mkdir -p bosh-secrets/ssl
```

## Deploy/Update BOSH
Example `bosh-secrets/vars.yml`:
```yml
---
director_name: bosh
internal_cidr: 10.0.0.0/24
internal_gw: 10.0.0.1
internal_ip: 10.0.0.6
network_name: bosh
vcenter_cluster: cluster1
vcenter_dc: datacenter1
vcenter_disks: bosh-disks
vcenter_ds: datastore[0-9]
vcenter_ip: vcsa.example.com
vcenter_templates: bosh-templates
vcenter_vms: bosh-vms
internal_dns:
- 10.0.0.1
ntp_servers:
- 0.pool.ntp.org
- 1.pool.ntp.org
- 2.pool.ntp.org
- 3.pool.ntp.org
```

```bash
# Interpolate the bosh and cloud config manifests
$ bosh-ops/environment/bin/interpolate

# Export the vcenter credentials for the create-env script:
$ export BOSHOPS_vcenter_user=some-user
$ export BOSHOPS_vcenter_password=some-pass

# Deploy the director
$ bosh-ops/environment/bin/create-env
```

## Login to BOSH
```bash
# Configure local alias
$ bosh alias-env prod -e 10.0.8.2 --ca-cert <(bosh int bosh-secrets/bosh/creds.yml --path /director_ssl/ca)

# Log in to the Director
$ export BOSH_CLIENT=admin
$ export BOSH_CLIENT_SECRET=$(bosh int bosh-secrets/bosh/creds.yml --path /admin_password)

# Verify you are logged in
$ bosh -e prod env

# Update cloud config
$ bosh-ops/environment/bin/update-cloud-config

# Upload a stemcell
$ bosh -e prod upload-stemcell https://s3.amazonaws.com/bosh-core-stemcells/vsphere/bosh-stemcell-3468.25-vsphere-esxi-ubuntu-trusty-go_agent.tgz

```

## Login to Credhub
```bash
# Log in to CredHub
$ credhub login --server https://10.0.8.2:8844 \
    --ca-cert=<(bosh int bosh-secrets/bosh/creds.yml --path /default_ca/ca) \
    --ca-cert=<(bosh int bosh-secrets/bosh/creds.yml --path /credhub_ca/ca) \
    --client-name=credhub-admin \
    --client-secret=$(bosh int bosh-secrets/bosh/creds.yml --path /credhub_admin_client_secret)
```

## Deploy instant-https
Example `bosh-secrets/vars-instant-https.yml`:
```yml
---
# Staging url:
#acme_url: https://acme-staging.api.letsencrypt.org/directory
# Production url:
acme_url: https://acme-v01.api.letsencrypt.org/directory
contact_email: user@example.com
ci_hostnames: [ci.example.com]
ci_backends:
- "http://192.168.1.10:8080"
- "http://192.168.1.11:8080"
opsman_hostnames: [opsman.example.com]
opsman_backends: ["https://192.168.2.6:443"]
pas_hostnames:
- "*.sys.example.com"
- "*.cfapps.example.com"
pas_backends:
- "https://192.168.3.10:443"
- "https://192.168.3.11:443"
```

```bash
# Deploy
$ bosh-ops/deployments/instant-https/bin/deploy
```

## Deploy Concourse
Create/Update `bosh-secrets/vars-concourse.yml`:
```yml
---
deployment_name: concourse
network_name: default
external_url: "https://ci.example.com"
web_vm_type: micro
db_persistent_disk_type: 51200
db_vm_type: micro
worker_vm_type: micro
web_instances: 1
worker_instances: 1
azs: [z1]
credhub_static_ip: 10.0.8.6
internal_dns:
- 10.0.0.1
```

```bash
# Interpolate
$ bosh-ops/deployments/concourse/bin/interpolate

# Set CredHub vars
$ credhub set -n /bosh/concourse/atc_basic_auth -t user -z 'some-user' -w 'some-pass'
$ credhub set -n /bosh/concourse/credhub_tls -t certificate -r <(bosh int bosh-secrets/bosh/creds.yml --path /credhub_tls/ca)
$ credhub set -n /bosh/concourse/uaa_ssl -t certificate -r <(bosh int bosh-secrets/bosh/creds.yml --path /uaa_ssl/ca)
$ credhub set -n /bosh/concourse/uaa_clients_concourse_to_credhub -t password -w $(bosh int bosh-secrets/bosh/creds.yml --path /uaa_clients_concourse_to_credhub)

# Deploy
$ bosh-ops/deployments/concourse/bin/deploy
```

## PCF Pipelines
```bash
# Set pipeline credentials
$ credhub generate -n /concourse/cloudops/git_key -t ssh # upload git_key.public_key to GitHub
$ credhub set -n /concourse/cloudops/opsman -t user -z "<some-user>" -w "<some-pass>"
$ credhub set -n /concourse/cloudops/opsman_decrypt_password -t password -w "<some-pass>"
$ credhub set -n /concourse/cloudops/opsman_vm -t user -z "ubuntu" -w "<some-pass>"
$ credhub set -n /concourse/cloudops/pivnet_api_token -t password -w "<pivnet-api-token>"
$ credhub set -n /concourse/cloudops/root_ca -t certificate -c <(cat bosh-secrets/ssl/root-ca.pem)
$ credhub set -n /concourse/cloudops/vcenter -t user -z "<some-user>" -w "<some-pass>"

# Set pipeline
$ bosh-ops/pcf/bin/sp-install-pcf
```
