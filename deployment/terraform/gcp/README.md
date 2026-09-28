# XLSMART Onyx GCP test environment

This is an **isolated, billable production-readiness test design**, not a production certification. Target: existing project `internal-tech-tools-enterprise`, region `asia-southeast2`, upstream Onyx chart 0.8.28 and the branded source checkout. Nothing in this directory installs the application automatically. Review a real plan, spend and policy constraints before any `apply`.

## Topology and limits

- Regional GKE Standard in three zones with a **regional** floor of three `e2-standard-8` nodes and maximum six. The autoscaler's BALANCED policy is best-effort; OpenSearch hard zone anti-affinity requires pods on three distinct zones and the capacity must be confirmed on the running cluster. Nodes are private, with a restricted public control plane, Workload Identity, Shielded VMs, GKE Dataplane V2, CSI Persistent Disks, logging, VPC Flow Logs and Cloud NAT. Explicit `admin_cidrs` input rejects world-open access. Node identity can pull, but not push, images.
- Regional HA Cloud SQL PostgreSQL 16 **Enterprise** (private IP, TLS required, PITR, 14 backups, seven days of transaction logs, deletion protection); Memorystore Redis Standard HA (private services access, AUTH + server TLS, six-hour RDB snapshots); private versioned GCS file storage and a private immutable-tag Artifact Registry. Application passwords and signing key are generated once and synced through Secret Manager and External Secrets Operator (ESO). Protected versioned GCS bucket holds the Terraform state. Terraform state itself **contains** generated passwords and the Redis AUTH string: restrict state-bucket IAM to the deploy team and never publish plan/state files.
- Self-managed three-node OpenSearch with one `premium-rwo` 100Gi disk per zone, zone-hard anti-affinity and the subchart quorum PDB. API, web and both model deployments have two replicas spread across zones. Ingress service is `ClusterIP`; **no public HTTP/HTTPS endpoint** is created. Access uses local `kubectl port-forward` until a reviewed DNS/certificate/TLS ingress is designed.
- The public [XLSMART Private Services Access module](https://github.com/xlsmartenterprise/tfmodule-google-private-services-access/commit/b8f47c9eed605fa3cc61cf586bbfebafb0633109) is pinned to an immutable revision. No public XLSMART module was found for enabling GCP project services; `google_project_service` enables APIs without disabling shared APIs on destroy.

**Cost boundary:** 3–6 running 8-vCPU nodes, regional HA Cloud SQL, Redis Standard HA, NAT, three SSD-backed OpenSearch volumes, GCS, image builds/registry, egress and logging all incur recurring or usage charges. Check current pricing/quotas and obtain a budget decision before applying. The code deliberately cannot be fully validated as a deployed service without provisioning billable resources. Never assume a `terraform plan` proves quota, Kubernetes admission, image compatibility or data recovery.

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

Use a reviewed Git commit as an immutable tag. `.gcloudignore` excludes local credentials, artwork and Terraform state from the Cloud Build upload. Confirm the three Docker build contexts (`web/`, `backend/`) contain only approved source. Cloud Build's custom service account can read the dedicated source bucket, push only to the staging Artifact Registry repository, and write logs; its use requires the operator's `iam.serviceAccounts.actAs` permission. The model-server build is large; Cloud Build uses a 200Gi scratch disk. Base and dependency images are third-party: pin/digest-review and scan each published image before promotion.

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

Cloud Build does not prove that the generated images have been scanned, admitted, or scheduled on GKE. The fork `xlsmartenterprise/onyx-enterprise` was not publicly accessible at preparation time; build from this committed workspace until the intended authenticated fork and CI trust chain exist.

## External Secrets and CA trust

Install ESO chart 2.11.0 with the Terraform-linked `external-secrets/external-secrets` KSA, then create the Onyx namespace. The names of the four Google secrets are fixed in `deployment/helm/gcp-staging/external-secrets.yaml`; the operator's IAM can access **only these four secrets**. The application's `onyx/onyx-runtime` KSA can access only its file bucket. GCP server CAs are public certificates, not passwords; refresh the ConfigMaps after certificate rotation. Use `kubectl` with an authorized cluster context.

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

If the Memorystore certificate does not validate the private IP returned by `redis_host`, **do not switch off** hostname checking for a production-grade test. Fix endpoint/SAN trust before proceeding. Verify a real Cloud SQL + Redis TLS connection in running workloads; a rendered manifest cannot prove certificates or network access. Do not print Kubernetes Secret contents.

## Install full Onyx and smoke the changed path

Build pinned chart dependencies as documented in `deployment/helm/charts/onyx/Chart.yaml` (CNPG, OpenSearch, ingress-nginx, Redis Operator, MinIO and sandbox repositories), even though some dependencies are disabled. Chart values explicitly reject Lite/CI reductions; cloud SQL/Redis/GCS replace in-cluster singleton data stores. Use immutable matching commit tags for all three branded images:

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
  --set-string "global.version=$TAG" \
  --set-string "serviceAccount.annotations.iam\\.gke\\.io/gcp-service-account=$RUNTIME_GSA" \
  --set-string "configMap.POSTGRES_HOST=$SQL_HOST" \
  --set-string "configMap.REDIS_HOST=$REDIS_HOST" \
  --set-string "configMap.REDIS_PORT=$REDIS_PORT" \
  --set-string "configMap.GCS_PROJECT_ID=$PROJECT" \
  --set-string "configMap.GCS_FILE_STORE_BUCKET_NAME=$FILE_BUCKET" \
  --set-string "webserver.image.repository=$REGISTRY/web-server" \
  --set-string "api.image.repository=$REGISTRY/backend" \
  --set-string "celery_shared.image.repository=$REGISTRY/backend" \
  --set-string "inferenceCapability.image.repository=$REGISTRY/model-server" \
  --set-string "indexCapability.image.repository=$REGISTRY/model-server"
kubectl -n onyx get pods -o wide
kubectl -n onyx get pvc
kubectl -n onyx port-forward --address 127.0.0.1 service/onyx-nginx-controller 8080:80
# Separate terminal: curl -fsS http://localhost:8080/api/health/ready
# Browser: http://localhost:8080/auth/login?autoRedirectToSignup=false
```

Verify login/signup from the real browser, configure a **test** connector and its authorized credentials, synchronize a known document, then query it through search. Check three OpenSearch pods in different zones, all PVCs `Bound`, SQL/Redis TLS, the GCS file path, rolling restart with one node disrupted, and a PITR restore to an isolated database **before** claiming readiness. No real connector credentials, LLM keys or SMTP settings belong in values or Terraform state.

## Production promotion gates

This test defaults to a local-only, non-TLS browser tunnel; plan a TLS termination route with DNS and certificate rotation before a public hostname. The bundled OpenSearch 3.x chart defaults to demo/self-signed certificates and Onyx defaults to `OPENSEARCH_VERIFY_CERTS=false`; replace demo certificates with an internal PKI, enable certificate verification for every client, and exercise snapshot/restore of the OpenSearch index. Configure on-call notification channels/alerts, cross-region disaster recovery if policy demands, node/image vulnerability scanning, connector egress controls, quotas, PDB for any additional workloads, and backup restore drills. Application-level Celery beat/workers remain singleton by chart design. These are **readiness gates**, not claims silently satisfied by this infrastructure plan.
