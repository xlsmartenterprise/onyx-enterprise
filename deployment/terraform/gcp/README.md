# XLSMART Onyx GCP test environment

This is an **isolated, billable production-readiness test deployment**, not a production certification. Target: existing project `internal-tech-tools-enterprise`, region `asia-southeast2`, upstream Onyx chart 0.8.28 and the branded source checkout. Review a real plan, spend and policy constraints before any further `apply`.

## Topology and limits

- Regional GKE Standard in three zones with a **regional** floor of three `e2-standard-8` nodes and maximum six. The autoscaler's BALANCED policy is best-effort; OpenSearch hard zone anti-affinity requires pods on three distinct zones and the capacity must be confirmed on the running cluster. Nodes are private, with a restricted public control plane, Workload Identity, Shielded VMs, GKE Dataplane V2, CSI Persistent Disks, logging, VPC Flow Logs and Cloud NAT. Explicit `admin_cidrs` input rejects world-open access. Node identity can pull, but not push, images.
- Regional HA Cloud SQL PostgreSQL 16 **Enterprise** (private IP, TLS required, PITR, 14 backups, seven days of transaction logs, deletion protection); Memorystore Redis Standard HA (private services access, AUTH + server TLS, six-hour RDB snapshots); private versioned GCS file storage and a private immutable-tag Artifact Registry. Application passwords and signing key are generated once and synced through Secret Manager and External Secrets Operator (ESO). Protected versioned GCS bucket holds the Terraform state. Terraform state itself **contains** generated passwords and the Redis AUTH string: restrict state-bucket IAM to the deploy team and never publish plan/state files.
- Self-managed three-node OpenSearch has one `premium-rwo` 100Gi disk per zone, zone-hard anti-affinity and a quorum PDB; API and web have two replicas spread across zones. No in-cluster model server is deployed: chat uses Vertex AI `gemini-3.8-flash` and search embeddings use `gemini-embedding-001` (3072 dimensions) via GKE Workload Identity. Gemini runs at `global`, **not** under a Jakarta data-residency guarantee; this location was accepted for staging. The nginx Service remains `ClusterIP`; a separate GKE external HTTPS load balancer uses the reserved global IP `136.69.66.33`. Certificate activation still requires the external Hostinger DNS A record.
- The public [XLSMART Private Services Access module](https://github.com/xlsmartenterprise/tfmodule-google-private-services-access/commit/b8f47c9eed605fa3cc61cf586bbfebafb0633109) is pinned to an immutable revision. No public XLSMART module was found for enabling GCP project services; `google_project_service` enables APIs without disabling shared APIs on destroy.

**Cost boundary:** 3–6 running 8-vCPU nodes, regional HA Cloud SQL, Redis Standard HA, NAT, three SSD-backed OpenSearch volumes, GCS, Vertex AI inference/embeddings, image builds/registry, egress and logging all incur recurring or usage charges. Check current pricing/quotas and keep a budget alert. Neither a `terraform plan` nor a healthy deployment proves data recovery, connector indexing or production readiness.

## Prerequisites and remote state

Use Terraform >=1.5, `gcloud`, `kubectl`, Helm 3 and access to the project. ADC should reference an authorized credential file; do **not** copy it into this repository or the image build context. The operator's network CIDR must be able to reach the GKE public control plane. Overlapping VPC/VPN/CIDR ranges must be changed in `infra/variables.tf` inputs before applying. Examples below assume commands run from repository root, `PROJECT=internal-tech-tools-enterprise` and an approved `<YOUR_PUBLIC_IP>/32`.

The protected state bucket `internal-tech-tools-enterprise-322861197394-onyx-tfstate` has already been created by `bootstrap/`, and its state migrated to GCS. Both stacks pin their own distinct GCS prefixes in tracked backend configuration. The GCS backend uses generation-based locking and object versioning. On a fresh checkout, **do not run bootstrap with local state**: initialize its tracked backend and confirm `terraform state list` contains `google_storage_bucket.terraform_state` before planning it. If restoring from loss of the state bucket itself, temporarily remove `bootstrap/backend.tf` from Terraform's load path, recreate the bucket with local state, then restore the backend file and `terraform init -migrate-state`; preserve the local state until migration succeeds.

```sh
export PROJECT=internal-tech-tools-enterprise
export GOOGLE_APPLICATION_CREDENTIALS=/home/workspace/.config/gcloud/application_default_credentials.json
terraform -chdir=deployment/terraform/gcp/bootstrap init
terraform -chdir=deployment/terraform/gcp/bootstrap state list
terraform -chdir=deployment/terraform/gcp/infra init
terraform -chdir=deployment/terraform/gcp/infra plan -var='admin_cidrs=["<YOUR_PUBLIC_IP>/32"]'
# Only after reviewing spend, IAM and 0 deletes:
terraform -chdir=deployment/terraform/gcp/infra apply -var='admin_cidrs=["<YOUR_PUBLIC_IP>/32"]'
```

Check `terraform output` only from a properly initialized infra backend, not from the temporary offline preview. The state bucket itself must not be force-destroyed. Secret rotation requires coordinated changes to Cloud SQL/Redis/OpenSearch, not merely publishing a new Secret Manager version. A Cloud SQL or GKE `terraform destroy` will intentionally fail while deletion protection remains enabled; review data export, snapshots and a change ticket before explicitly disabling it.

## Publish branded images and connect to the cluster

Use a reviewed Git commit as an immutable tag. `.gcloudignore` sends only the Docker source contexts (`web/`, `backend/`) and build definition; it excludes credentials, artwork, local `.next` caches and Terraform state. Cloud Build's custom service account can read the dedicated source bucket, push only to the staging Artifact Registry repository, and write logs; its use requires the operator's `iam.serviceAccounts.actAs` permission. The build requests a billable 32-vCPU worker, a 200Gi scratch disk and a two-hour deadline: the smaller 8-vCPU worker stopped internally during `next build`. Base and dependency images are third-party: pin/digest-review and scan each published image before promotion.

```sh
REGISTRY=$(terraform -chdir=deployment/terraform/gcp/infra output -raw artifact_registry_repository)
SOURCE_BUCKET=$(terraform -chdir=deployment/terraform/gcp/infra output -raw build_source_bucket)
BUILDER_GSA=$(terraform -chdir=deployment/terraform/gcp/infra output -raw image_builder_gsa_email)
TAG=$(git rev-parse --short=12 HEAD)
gcloud builds submit . --project="$PROJECT" --region=asia-southeast2 \
  --config=deployment/helm/gcp-staging/cloudbuild.yaml \
  --service-account="projects/$PROJECT/serviceAccounts/$BUILDER_GSA" \
  --gcs-source-staging-dir="gs://$SOURCE_BUCKET/source" \
  --substitutions="_REGISTRY=$REGISTRY,_TAG=$TAG"
gcloud container clusters get-credentials \
  "$(terraform -chdir=deployment/terraform/gcp/infra output -raw cluster_name)" \
  --region="$(terraform -chdir=deployment/terraform/gcp/infra output -raw cluster_location)" \
  --project="$PROJECT"
```

The authenticated fork is [xlsmartenterprise/onyx-enterprise](https://github.com/xlsmartenterprise/onyx-enterprise); `xlsmart-main` is the default branch. A least-privilege `SYNC_GITHUB_TOKEN` for CI and a real upstream-sync PR dry-run are still pending. Never put the operator's broad GitHub credential in Actions secrets.

## External Secrets and CA trust

Install ESO chart 2.11.0 with the Terraform-linked `external-secrets/external-secrets` KSA, then create the Onyx namespace. The names of the four Google secrets are fixed in `deployment/helm/gcp-staging/external-secrets.yaml`; the operator's IAM can access **only these four secrets**. The application's `onyx/onyx-runtime` KSA uses a GSA with access to its file bucket and Vertex AI prediction, not a downloaded service-account key. GCP server CAs are public certificates, not passwords; refresh the ConfigMaps after certificate rotation. Use `kubectl` with an authorized cluster context.

```sh
ESO_GSA=$(terraform -chdir=deployment/terraform/gcp/infra output -raw external_secrets_gsa_email)
helm repo add external-secrets https://charts.external-secrets.io
helm upgrade --install external-secrets external-secrets/external-secrets \
  --version 2.11.0 --namespace external-secrets --create-namespace \
  --set-string "serviceAccount.annotations.iam\\.gke\\.io/gcp-service-account=$ESO_GSA" \
  --wait --timeout 10m
kubectl create namespace onyx
SQL_INSTANCE=$(terraform -chdir=deployment/terraform/gcp/infra output -raw cloud_sql_instance_name)
gcloud sql ssl server-ca-certs list --project="$PROJECT" --instance="$SQL_INSTANCE" \
  --format=json | python3 -c 'import json,sys; print("\n".join(x["cert"] for x in json.load(sys.stdin)))' > cloudsql-ca.pem
gcloud redis instances describe onyx-staging-redis --project="$PROJECT" \
  --region=asia-southeast2 --format=json | \
  python3 -c 'import json,sys; print("\n".join(x["cert"] for x in json.load(sys.stdin)["serverCaCerts"]))' > redis-ca.pem
kubectl -n onyx create configmap onyx-cloudsql-ca --from-file=ca.crt=cloudsql-ca.pem
kubectl -n onyx create configmap onyx-redis-ca --from-file=ca.crt=redis-ca.pem
kubectl apply -f deployment/helm/gcp-staging/external-secrets.yaml
kubectl -n onyx wait --for=condition=Ready externalsecret/onyx-postgresql \
  externalsecret/onyx-redis externalsecret/onyx-opensearch \
  externalsecret/onyx-userauth --timeout=5m
```

If the Memorystore certificate does not validate the private IP returned by `redis_host`, **do not switch off** hostname checking. Cloud SQL's current per-instance CA lacks an Authority Key Identifier; Python 3.13 asyncpg otherwise fails startup under its default `VERIFY_X509_STRICT`. The chart enables `POSTGRES_SSL_ALLOW_LEGACY_CA=true` only for the Cloud SQL PostgreSQL asyncpg connection: it clears that strict verification flag, but **retains certificate chain verification** against the mounted CA. psycopg2 still uses `sslmode=verify-ca`. Replace the legacy CA and remove the exception when feasible. Verify real Cloud SQL + Redis TLS connections in running workloads; a rendered manifest cannot prove certificates or network access. Do not print Kubernetes Secret contents.

## Install Vertex-only Onyx and smoke the changed path

Build pinned chart dependencies as documented in `deployment/helm/charts/onyx/Chart.yaml` (CNPG, OpenSearch, ingress-nginx, Redis Operator, MinIO and sandbox repositories), even though some dependencies are disabled. Chart values explicitly reject Lite/CI reductions; cloud SQL/Redis/GCS replace in-cluster singleton data stores. Cloud Build produces **two**, not three, matching commit-tagged images (`web-server` and `backend`). The chart disables both model-server deployments/services and sets `DISABLE_MODEL_SERVER=true`; do not add a model image override.

```sh
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm repo add opensearch https://opensearch-project.github.io/helm-charts
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add ot-container-kit https://ot-container-kit.github.io/helm-charts
helm repo add minio https://charts.min.io/
helm repo add sandbox https://onyx-dot-app.github.io/python-sandbox/
helm dependency build deployment/helm/charts/onyx

RUNTIME_GSA=$(terraform -chdir=deployment/terraform/gcp/infra output -raw runtime_gsa_email)
SQL_HOST=$(terraform -chdir=deployment/terraform/gcp/infra output -raw postgres_private_ip)
REDIS_HOST=$(terraform -chdir=deployment/terraform/gcp/infra output -raw redis_host)
REDIS_PORT=$(terraform -chdir=deployment/terraform/gcp/infra output -raw redis_port)
FILE_BUCKET=$(terraform -chdir=deployment/terraform/gcp/infra output -raw file_store_bucket)
helm upgrade --install onyx deployment/helm/charts/onyx --namespace onyx \
  -f deployment/helm/gcp-staging/values.yaml --wait --timeout 30m \
  --set api.replicaCount=1 \
  --set-string "global.version=$TAG" \
  --set-string "serviceAccount.annotations.iam\\.gke\\.io/gcp-service-account=$RUNTIME_GSA" \
  --set-string "configMap.POSTGRES_HOST=$SQL_HOST" \
  --set-string "configMap.REDIS_HOST=$REDIS_HOST" \
  --set-string "configMap.REDIS_PORT=$REDIS_PORT" \
  --set-string "configMap.GCS_PROJECT_ID=$PROJECT" \
  --set-string "configMap.GCS_FILE_STORE_BUCKET_NAME=$FILE_BUCKET" \
  --set-string "webserver.image.repository=$REGISTRY/web-server" \
  --set-string "api.image.repository=$REGISTRY/backend" \
  --set-string "celery_shared.image.repository=$REGISTRY/backend"

helm upgrade onyx deployment/helm/charts/onyx --namespace onyx \
  --reuse-values --set api.replicaCount=2 --wait --timeout 10m
kubectl -n onyx get pods -o wide
kubectl -n onyx get pvc
kubectl -n onyx port-forward --address 127.0.0.1 service/onyx-nginx-controller 8080:80
# Separate terminal: curl -fsS http://localhost:8080/api/health/ready
# Browser: http://localhost:8080/auth/login?autoRedirectToSignup=false
```

On an initial install, start with one API replica to serialize first-run Alembic migrations, then scale to two. Confirm API/web 2/2, OpenSearch 3/3, three `Bound` PVCs, four synced ExternalSecrets and no model-server resources. A worker should generate a 3072-dimensional `gemini-embedding-001` vector, and the UI should generate a `gemini-3.8-flash` chat answer. Verify a test connector sync, real indexed search with a citation, password login, invite-only registration rejection, SQL/Redis TLS and GCS file read/write; a direct SDK call or rendered manifest does not prove the app path. Before calling the system production-ready, restore a PITR backup into an isolated database, test OpenSearch snapshot recovery, and exercise a node disruption. Keep connector credentials, model keys and SMTP settings out of values and Terraform state.

## Public HTTPS and signup lock

This deployment reserves `onyx-staging-chat-ip` (`136.69.66.33`). The authoritative nameservers for `vibecloud.id` are Hostinger (`cosmos.dns-parking.com` and `nova.dns-parking.com`); the GCP project has no DNS zone for that domain. Create the **A** record `chat-staging.vibecloud.id -> 136.69.66.33` there; no access to Hostinger DNS is present in this workspace. Google-managed certificate issuance requires the public DNS record and can take up to an hour after the Ingress is attached; until the certificate status is `Active`, do not claim usable public HTTPS.

Before exposing the host, log in as the named admin and PATCH `/api/admin/settings` with `{\"invite_only_enabled\":true}`. Confirm an anonymous POST to `/api/auth/register` returns 403, the invitation list is empty, `/api/auth/type` reports `password_auth_enabled:true`, `invite_only_enabled:true`, `oauth_enabled:false`, `sso_providers:[]`, and exactly one active human administrator exists. The built-in `anonymous@onyx.app` account must remain unable to log in (`anonymous_user_enabled:false`). Preserve password login; setting `password_auth_enabled:false` would disable both login and signup. Never put a password in Git, CLI arguments or debug output.

On an existing release, retain its Workload Identity, Cloud SQL, Redis, GCS and image-repository overrides while loading the updated public URL and ClusterIP/NEG annotations. Only after the new backend and web images are ready and signup is denied, create the public Ingress:

```sh
TAG='BUILT_IMAGE_COMMIT_SHA_12'
helm upgrade onyx deployment/helm/charts/onyx --namespace onyx \
  --reuse-values -f deployment/helm/gcp-staging/values.yaml \
  --set-string \"global.version=$TAG\" --wait --timeout 30m
kubectl -n onyx apply -f deployment/helm/gcp-staging/public-ingress.yaml
kubectl -n onyx get ingress onyx-staging-chat
kubectl -n onyx describe managedcertificate onyx-staging-chat-cert
```

The Ingress uses the global static IP, a Google-managed certificate, HTTP-to-HTTPS redirect and a NEG-backed `BackendConfig` with port 1024 `/nginx-health` and 900-second stream timeout. The nginx Service itself remains private. Check DNS with a public resolver, cert status `Active`, browser login over **HTTPS**, signup redirect and chat/search before announcing the URL. An HTTP-only response or a cert still `Provisioning` is not HTTPS completion. See Google's [managed GKE certificate](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/secure-traffic-management) and [Ingress/BackendConfig](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/ingress-configuration) guidance.

## Production promotion gates

An external HTTPS load balancer is configured, but its Google-managed certificate remains pending until Hostinger DNS points to the reserved IP and the certificate reports `Active`. The bundled OpenSearch 3.x chart still runs with demo certificates and `OPENSEARCH_VERIFY_CERTS=false`; the replacement is deliberately opt-in until snapshots and a coordinated maintenance window are available. The legacy Cloud SQL CA exception still validates the chain but relaxes Python's strict X.509 flag; schedule the one-way shared-CA migration below. Paid EE features require a valid subscription. On-call alerts, quotas/budgets, image and node vulnerability scanning, connector egress controls, isolated backup/PITR and OpenSearch restore drills, and any policy-required cross-region DR remain production gates. Celery beat/workers remain singleton by chart design; this is not a production-readiness certification.

## OpenSearch certificate migration (maintenance-only)

`deployment/helm/gcp-staging/opensearch-tls-certificates.yaml` and `opensearch-tls.values.yaml` are **prepared, not applied**. The present OpenSearch pods use the Helm chart's demo certificates and clients do not verify the certificate chain. None of the running nodes has a GCS/S3 snapshot plugin, and no `VolumeSnapshotClass` is configured. Do not replace certificates during an ordinary rolling Helm upgrade: old demo-cert and new private-CA nodes cannot authenticate one another, risking quorum and writes.

1. Obtain approval for a maintenance window. Set up an off-cluster OpenSearch snapshot repository with a vetted plugin/identity or a crash-consistent, coordinated storage-snapshot strategy; take a snapshot and **restore it to an isolated cluster**, checking document counts, index mappings and search. Retain all three original OpenSearch PVCs and a tested rollback plan.
2. Install a reviewed/pinned cert-manager controller and its CRDs. Apply `opensearch-tls-certificates.yaml` in namespace `onyx`, then wait for the CA and node/admin Certificates to be `Ready`. Back up the private CA Secret in a restricted location outside Git. Create `onyx-opensearch-ca` ConfigMap containing **only the public root certificate** as `onyx-opensearch-ca.crt`; never mount the admin certificate/private key into app pods.
3. Quiesce indexing and search clients, shut down all three demo-certificate nodes in coordination, and switch the OpenSearch StatefulSet together to `helm upgrade ... -f values.yaml -f opensearch-tls.values.yaml` without deleting PVCs or its persisted security index. Restart app clients against the trusted public CA; the opt-in values set `OPENSEARCH_USE_SSL=true`, `OPENSEARCH_VERIFY_CERTS=true` and the CA path. Verify 3/3 node quorum, healthy index/search, client certificate verification and a fresh chat/search smoke before resuming writes.
4. Schedule leaf renewal/restarts before certificate expiry and plan a CA rollover well before five years. The prepared staging chart shares one node leaf key across three replicas because the upstream StatefulSet mounts one Secret; issue **per-node** certs/keys and restrict RBAC before reusing this design in production.

## Cloud SQL CA migration (separate maintenance-only change)

The current instance has `GOOGLE_MANAGED_INTERNAL_CA` and `sslMode=ENCRYPTED_ONLY`. Its legacy per-instance CA lacks AKI; `POSTGRES_SSL_ALLOW_LEGACY_CA=true` only clears Python asyncpg's `VERIFY_X509_STRICT` flag, while the mounted CA chain is still checked and psycopg2 uses `verify-ca`. Do not remove the exception against this certificate. Cloud SQL supports a **one-way** migration to `GOOGLE_MANAGED_CAS_CA` and cannot switch back to the per-instance mode ([Google's CA-mode procedure](https://docs.cloud.google.com/sql/docs/postgres/edit-instance#edit-the-server-ca-mode-for-an-instance)).

1. Confirm that Cloud SQL automatic backups, 14 retained backups and seven-day PITR are healthy; restore a recent backup or PITR point into an isolated test instance, then delete that test instance after evidence is recorded. Agree on an outage/rollback plan before any irreversible CA-mode patch.
2. Download Google's [global and `asia-southeast2` CA bundles](https://docs.cloud.google.com/sql/docs/postgres/manage-ssl-instance#download-root-regional-ca-bundles); add them alongside the current per-instance CA in `onyx-cloudsql-ca` so old and new certificates are trusted simultaneously. Roll the backend/API/workers to pick up the new public trust bundle, then prove existing connections still work. Check any external SQL clients or proxy version requirements.
3. In a reviewed Terraform change set `settings.ip_configuration.server_ca_mode = \"GOOGLE_MANAGED_CAS_CA\"` in `infra/data.tf`; confirm **no SQL instance replacement or unrelated deletes** in the plan. Apply during maintenance, inspect the new CA chain and app TLS connections, then remove `POSTGRES_SSL_ALLOW_LEGACY_CA` from the Helm values **only after** an asyncpg connection succeeds with strict X.509 verification. Keep `sslMode=ENCRYPTED_ONLY` and `sslmode=verify-ca`; hostname verification requires a separate server-name/DNS design, not silently changing to `verify-full`.

