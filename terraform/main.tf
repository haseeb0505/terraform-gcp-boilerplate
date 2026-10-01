locals {
  gcs_bucket_name = var.gcs_bucket_name != "" ? var.gcs_bucket_name : "${var.name_prefix}-uploads"
  bastion_zone    = var.bastion_zone != "" ? var.bastion_zone : "${var.region}-a"
}

module "shared" {
  source = "./modules/shared"

  project_id      = var.project_id
  region          = var.region
  name_prefix     = var.name_prefix
  enable_ai_apis  = var.enable_ai_apis
  additional_apis = var.additional_apis
}

module "network" {
  source = "./modules/network"

  project_id      = var.project_id
  region          = var.region
  name_prefix     = var.name_prefix
  app_subnet_cidr = var.app_subnet_cidr
  psa_range_cidr  = var.psa_range_cidr
  nat_ip_count    = var.nat_ip_count

  depends_on = [module.shared]
}

module "bastion" {
  source = "./modules/bastion"

  project_id           = var.project_id
  zone                 = local.bastion_zone
  name_prefix          = var.name_prefix
  network_name         = module.network.network_name
  subnet_id            = module.network.subnet_id
  operator_members     = var.bastion_operator_members
  iap_ssh_source_cidrs = var.iap_ssh_source_cidrs

  depends_on = [module.shared, module.network]
}

module "frontend" {
  count  = var.enable_frontend ? 1 : 0
  source = "./modules/frontend"

  project_id             = var.project_id
  region                 = var.region
  name_prefix            = var.name_prefix
  artifact_registry_repo = module.shared.artifact_registry_repo

  depends_on = [module.shared]
}

module "backend" {
  source = "./modules/backend"

  project_id             = var.project_id
  region                 = var.region
  name_prefix            = var.name_prefix
  artifact_registry_repo = module.shared.artifact_registry_repo

  vpc_id                    = module.network.network_id
  subnet_id                 = module.network.subnet_id
  private_vpc_connection_id = module.network.private_vpc_connection_id
  nat_id                    = module.network.nat_id

  db_name                  = var.db_name
  db_tier                  = var.db_tier
  db_disk_size_gb          = var.db_disk_size_gb
  db_backup_retention_days = var.db_backup_retention_days
  db_backup_schedule       = var.db_backup_schedule
  db_backup_timezone       = var.db_backup_timezone

  gcs_bucket_name     = local.gcs_bucket_name
  gcs_bucket_location = var.gcs_bucket_location

  app_env      = var.app_env
  debug        = var.debug
  cors_origins = var.cors_origins
  frontend_url = var.enable_frontend ? module.frontend[0].service_url : ""

  app_env_vars          = var.app_env_vars
  app_secrets           = var.app_secrets
  enable_migration_job  = var.enable_migration_job
  migration_command     = var.migration_command
  enable_seed_job       = var.enable_seed_job
  seed_command          = var.seed_command
  enable_ai_integration = var.enable_ai_apis

  depends_on = [module.shared]
}

module "load_balancer" {
  source = "./modules/load_balancer"

  project_id            = var.project_id
  region                = var.region
  name_prefix           = var.name_prefix
  enable_frontend       = var.enable_frontend
  frontend_service_name = var.enable_frontend ? module.frontend[0].service_name : ""
  backend_service_name  = module.backend.service_name
  frontend_domain       = var.frontend_domain
  backend_domain        = var.backend_domain
  allow_rules           = var.cloud_armor_allow_rules
  route_api_docs        = var.app_env == "development"

  depends_on = [module.shared, module.backend]
}
