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
# Log in to the Director
$ export BOSH_CLIENT=admin
$ export BOSH_CLIENT_SECRET=$(bosh int bosh-secrets/bosh/creds.yml --path /admin_password)
$ export BOSH_CA_CERT=$(bosh int bosh-secrets/bosh/creds.yml --path /director_ssl/ca)
$ export BOSH_ENVIRONMENT=10.0.8.2

# Verify you are logged in
$ bosh env

# Update cloud config
$ bosh-ops/environment/bin/update-cloud-config

# Upload some stemcells
$ bosh upload-stemcell https://bosh-core-stemcells.s3-accelerate.amazonaws.com/621.117/bosh-stemcell-621.117-vsphere-esxi-ubuntu-xenial-go_agent.tgz
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

## Deploy caddy
Create `bosh-secrets/vars-caddy.yml`:
```yml
---
acme_url: https://acme-v02.api.letsencrypt.org/directory
contact_email: me@example.com
env:
  GCE_PROJECT: sample-project-201802
  GCE_SERVICE_ACCOUNT_FILE: |
    {
      "type": "sample_account",
      "project_id": "sample-project-201802",
      "private_key_id": "sample4c02016ac2d8abf5b1577993ded31626a8",
      "private_key": "-----BEGIN PRIVATE KEY-----\nMIIE...k8LAVeB==\n-----END PRIVATE KEY-----\n",
      "client_email": "caddys@sample-project-201802.iam.gserviceaccount.com",
      "client_id": "sample4c02016ac2d8abf",
      "auth_uri": "https://accounts.google.com/o/oauth2/auth",
      "token_uri": "https://accounts.google.com/o/oauth2/token",
      "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
      "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/caddy%sample-project-201802.iam.gserviceaccount.com"
    }
caddyfile: |
  (wildcard_cert) {
    tls {
      dns googlecloud
      wildcard
    }
  }
  ci.example.com {
    import wildcard_cert
    log / /var/vcap/sys/log/proxy/ci.access.log "{combined} {scheme} {host}"
    proxy / http://10.0.10.10:8080 {
      websocket
      transparent
    }
  }
  opsman.example.com {
    import wildcard_cert
    log / /var/vcap/sys/log/proxy/opsman.access.log "{combined} {scheme} {host}"
    proxy / https://10.0.20.10:443 {
      transparent
      insecure_skip_verify
    }
  }
  *.cfapps.example.com *.run.example.com *.login.run.example.com *.uaa.run.example.com {
    log / /var/vcap/sys/log/proxy/pas.access.log "{combined} {scheme} {host}"
    proxy / https://10.0.30.10:443 {
      transparent
      websocket
      insecure_skip_verify
    }
    tls {
      dns googlecloud
    }
  }
```

Deploy:
```bash
$ bosh-ops/deployments/caddy/deploy
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
credhub_url: https://10.0.8.2:8844/api/
garden_dns_servers:
- 10.0.0.1
main_team:
  github_orgs:
  - someorg
  github_teams:
  - someteam
  github_users: []
```

```bash
# Create an OAuth application on GitHub:
#   Single user: https://github.com/settings/applications/new
#   or...
#   Organization: https://github.com/organizations/YOUR_ORG_NAME/settings/applications/new

# Set CredHub vars
$ credhub set -n /bosh/concourse/github_client -t user -z 'your generated GitHub OAuth client_id' -w 'your generated GitHub oAuth client_secret'
$ credhub set -n /bosh/concourse/credhub_client_id -t password -w 'concourse_to_credhub'
$ credhub set -n /bosh/concourse/credhub_client_secret -t password -w "$(bosh int bosh-secrets/bosh/creds.yml --path /uaa_clients_concourse_to_credhub)"
$ credhub set -n /bosh/concourse/credhub_tls -t certificate \
              -r <(bosh int bosh-secrets/bosh/creds.yml --path /credhub_tls/ca) \
              -c <(bosh int bosh-secrets/bosh/creds.yml --path /credhub_tls/certificate)
$ credhub set -n /bosh/concourse/uaa_ssl -t certificate \
              -r <(bosh int bosh-secrets/bosh/creds.yml --path /uaa_ssl/ca) \
              -c <(bosh int bosh-secrets/bosh/creds.yml --path /uaa_ssl/certificate)

# Deploy
$ bosh-ops/deployments/concourse/deploy

# Login to Concourse
$ fly -t main login -c https://ci.example.com \
      -u "$(credhub get -n /bosh/concourse/local_user --key username)" \
      -p "$(credhub get -n /bosh/concourse/local_user --key password)"
```
