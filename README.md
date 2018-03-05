# BOSH Ops

Create and manage a BOSH environment.

## Initial Setup
```bash
# Clone bosh-ops
$ git clone https://github.com/patrickcrocker/bosh-ops

# Create your secrets folder
$ mkdir -p bosh-secrets/bosh
$ mkdir -p bosh-secrets/manifests
$ touch bosh-secrets/vars.yml
$ touch bosh-secrets/vars-concourse.yml
```

Example `vars.yml`:
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

Example `vars-concourse.yml`:
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

## Deploy BOSH
```bash
# Interpolate the bosh and cloud config manifests
$ bosh-ops/environment/bin/interpolate

# Export the vcenter credentials for the initial install (later we'll get these from credhub)
$ export BOSHOPS_vcenter_user=some-user
$ export BOSHOPS_vcenter_password=some-pass

# Deploy the director
$ bosh-ops/environment/bin/create-env

# Configure local alias
$ bosh alias-env prod -e 10.0.8.2 --ca-cert <(bosh int bosh-secrets/bosh/creds.yml --path /director_ssl/ca)
```

## Login to BOSH
```bash
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

# Migrate vcenter credentials to credhub:
$ credhub set -n /vsphere/vcenter_user -t value -v "$BOSHOPS_vcenter_user"
$ credhub set -n /vsphere/vcenter_password -t password -w "$BOSHOPS_vcenter_password"
```

## Deploy instant-https
```bash
# Set the acme prod or staging URL
# staging: https://acme-staging.api.letsencrypt.org/directory
# prod   : https://acme-v01.api.letsencrypt.org/directory
$ credhub set -n /bosh/instant-https/acme_url -t value -v https://acme-staging.api.letsencrypt.org/directory

# Deploy
$ bosh -e prod deploy -d instant-https bosh-ops/deployments/instant-https.yml --vars-file=bosh-secrets/vars.yml
```

## Deploy Concourse
```bash
# Set CredHub vars
$ credhub set -n /bosh/concourse/atc_basic_auth -t 'some-user' -z admin -w 'some-pass'

# Interpolate
$ bosh-ops/deployments/concourse/bin/interpolate

# Deploy
$ bosh-ops/deployments/concourse/bin/deploy
```

## Re-deploy BOSH

If you need to redeploy bosh director:
```bash
# Re-interpolate:
$ bosh-ops/environment/bin/interpolate

# Set vcenter credentials:
$ export BOSHOPS_vcenter_user=$(credhub get -n /vsphere/vcenter_user -j | jq -r .value)
$ export BOSHOPS_vcenter_password=$(credhub get -n /vsphere/vcenter_password -j | jq -r .value)

# Redeploy BOSH director
$ bosh-ops/environment/bin/create-env
```
