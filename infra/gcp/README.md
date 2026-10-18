# GCP Deployment

This Terraform deploys the Spring Boot service to one Cloud Run instance with 2 vCPU and 2 GiB RAM, creates its Docker Artifact Registry repository and runtime service account, grants configured invokers, and creates a Cloud Monitoring dashboard. It never builds an image: `image_uri` must be an existing immutable `@sha256` digest.

## Bootstrap And Deploy

Authenticate with credentials that can manage Artifact Registry, Cloud Run, IAM, Service Usage, and Cloud Monitoring. Copy `terraform.tfvars.example` to `terraform.tfvars` and set real values.

The registry must exist before a buildpack image can be pushed. Create only the repository first:

```powershell
terraform init
terraform apply -target=google_artifact_registry_repository.images
```

Build and push with Spring Boot buildpacks; no Dockerfile is needed:

```powershell
$project = "my-gcp-project"
$region = "europe-west1"
$repository = "ride-matching"
$tag = "$region-docker.pkg.dev/$project/$repository/ride-matching:release"
gcloud auth configure-docker "$region-docker.pkg.dev"
..\..\ride-matching-springboot\mvnw.cmd "-Dspring-boot.build-image.imageName=$tag" spring-boot:build-image
docker push $tag
$digest = gcloud artifacts docker images describe $tag --format="value(image_summary.digest)"
```

Set `image_uri` to `$region-docker.pkg.dev/$project/$repository/ride-matching@$digest`, then deploy:

```powershell
terraform apply
```

`invoker_members` defaults to `allUsers` so browser clients can reach the service; the application still validates JWTs. Replace it with specific members if Cloud Run IAM should also gate access.

## Single-Instance Limitation

`min_instance_count` and `max_instance_count` are both `1` because ride and driver state is held in memory. This prevents cross-instance disagreement, but it does not make state durable: a revision rollout, restart, or crash loses every active ride. The service cannot scale horizontally until state moves to shared durable storage. The configured `container_concurrency` still permits concurrent requests within that one process.

The dashboard contains request rate, p95 latency, error rate, CPU utilization, memory utilization, and container count. Cloud Run supplies these platform metrics without exposing an application metrics endpoint.
