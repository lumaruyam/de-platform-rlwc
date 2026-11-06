# Container images (step 6). The class registry "dataeng" is created and managed by the teaching
# team: we cannot create a repository (artifactregistry.repositories.create denied, 2026-11-06).
# We read it here, so the code says where our images live, without managing it.
data "google_artifact_registry_repository" "class" {
  location      = var.region
  repository_id = "dataeng"
}

output "registry" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${data.google_artifact_registry_repository.class.repository_id}"
}
