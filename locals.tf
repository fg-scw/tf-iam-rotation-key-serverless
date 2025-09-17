# ====================================================================
# locals.tf
# ====================================================================

locals {
  common_tags = {
    Environment = "production"
    Project     = "api-key-rotation"
    ManagedBy   = "terraform"
    Owner       = "devops"
  }

  # Configuration commune des variables d'environnement
  common_env_vars = {
    BETASCW_SECRET_KEY      = var.scw_secret_key
    BETASCW_PROJECT_ID      = var.scw_project_id
    BETASCW_ORGANIZATION_ID = var.scw_organization_id
    BETASCW_REGION          = var.scw_region
  }
}