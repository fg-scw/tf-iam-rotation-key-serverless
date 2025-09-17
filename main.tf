# ====================================================================
# Configuration Terraform pour le workflow de rotation des clés API Scaleway
# ====================================================================

terraform {
  required_version = ">= 1.0"
  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.31"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# ====================================================================
# Variables de configuration
# ====================================================================

variable "scw_access_key" {
  description = "Scaleway Access Key"
  type        = string
  sensitive   = true
}

variable "scw_secret_key" {
  description = "Scaleway Secret Key"
  type        = string
  sensitive   = true
}

variable "scw_project_id" {
  description = "Scaleway Project ID"
  type        = string
}

variable "scw_organization_id" {
  description = "Scaleway Organization ID"
  type        = string
}

variable "scw_region" {
  description = "Scaleway Region"
  type        = string
  default     = "fr-par"
}

variable "scw_zone" {
  description = "Scaleway Zone"
  type        = string
  default     = "fr-par-1"
}

variable "prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "api-rotation"
}

# ====================================================================
# Configuration du provider
# ====================================================================

provider "scaleway" {
  access_key      = var.scw_access_key
  secret_key      = var.scw_secret_key
  organization_id = var.scw_organization_id
  project_id      = var.scw_project_id
  region          = var.scw_region
  zone            = var.scw_zone
}

# ====================================================================
# Création des fichiers Python localement
# ====================================================================

resource "local_file" "rotation_function" {
  filename = "${path.module}/functions/rotation/handler.py"
  content = <<-EOT
#!/usr/bin/env python3
import os
import json
import time
import urllib.request
import urllib.parse
import urllib.error
import base64

# --- Constantes pour la maintenance ---
IAM_API_BASE_URL = "https://api.scaleway.com/iam/v1alpha1"
SECRET_MANAGER_BASE_URL = "https://api.scaleway.com/secret-manager/v1beta1"
APP_NAME = "generative-api-consumer"
SECRET_NAME = "iam-keys-generative-api"

class ScalewayApiError(Exception):
    """Exception personnalisée pour les erreurs de l'API Scaleway."""
    pass

def api_call(url, method="GET", headers=None, data=None):
    """Effectue un appel API et lève une exception en cas d'erreur."""
    try:
        req_headers = headers or {}
        req_data = None
        if data and method in ["POST", "PUT"]:
            req_data = json.dumps(data).encode('utf-8')
            req_headers['Content-Type'] = 'application/json'
        
        req = urllib.request.Request(url, data=req_data, headers=req_headers, method=method)
        with urllib.request.urlopen(req, timeout=30) as response:
            res_data = response.read().decode('utf-8')
            return json.loads(res_data) if res_data else {}
    except urllib.error.HTTPError as e:
        raise ScalewayApiError(f"HTTP {e.code}: {e.read().decode()}") from e
    except Exception as e:
        raise ScalewayApiError(str(e)) from e

def handler(event, context):
    """Handler principal avec gestion d'erreurs par exceptions."""
    print("DÉBUT DU WORKFLOW IAM SCALEWAY")
    try:
        # Configuration
        required = ['BETASCW_SECRET_KEY', 'BETASCW_PROJECT_ID', 'BETASCW_ORGANIZATION_ID']
        if missing := [v for v in required if not os.environ.get(v)]:
            raise ValueError(f"Variables d'environnement manquantes: {', '.join(missing)}")
        
        secret_key = os.environ['BETASCW_SECRET_KEY']
        project_id = os.environ['BETASCW_PROJECT_ID']
        org_id = os.environ['BETASCW_ORGANIZATION_ID']
        region = os.environ.get('BETASCW_REGION', 'fr-par')
        headers = {'X-Auth-Token': secret_key}

        # --- Déroulement du workflow ---
        print("\n--- [1/4] Application IAM ---")
        app = find_or_create_app(headers, org_id)
        print(f"Application IAM '{app['name']}' trouvée/créée (ID: {app['id']})")

        print("\n--- [2/4] Clés API ---")
        keys = create_keys(headers, app['id'])
        print(f"Clés API créées (Access Key: {keys['access_key']})")

        print("\n--- [3/4] Stockage du Secret ---")
        secret = store_secret(headers, region, project_id, keys)
        print(f"Secret stocké (ID: {secret['id']}, Version: {secret['revision']})")

        print("\n--- [4/4] Vérification & Contenu ---")
        version_content = access_secret_version(headers, region, secret['id'])
        stored_data = decode_secret_data(version_content['data'])
        
        if stored_data.get('API_KEY') == keys['access_key']:
            print("Vérification réussie - Les clés correspondent.")
        else:
            print("Vérification échouée - Incohérence des clés.")
        
        print("\nINFORMATIONS DU SECRET:")
        print(f"   Nom: {secret['name']}, Région: {secret['region']}")
        print(f"CONTENU STOCKÉ:")
        print(f"   API_KEY: {stored_data.get('API_KEY', 'N/A')}")
        
        print("\nWORKFLOW TERMINÉ")
        return {"statusCode": 200, "body": json.dumps({"app_id": app['id'], "access_key": keys['access_key']})}

    except (ScalewayApiError, ValueError) as e:
        print(f"ERREUR WORKFLOW: {e}")
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}
    except Exception as e:
        print(f"ERREUR SYSTÈME INATTENDUE: {e}")
        return {"statusCode": 500, "body": json.dumps({"error": f"Erreur système: {e}"})}

def find_or_create_app(headers, org_id):
    """Trouve une application par son nom ou la crée si elle n'existe pas."""
    url = f"{IAM_API_BASE_URL}/applications"
    list_result = api_call(f"{url}?organization_id={org_id}&name={APP_NAME}", headers=headers)
    if list_result.get("applications"):
        return list_result["applications"][0]
    
    create_data = {"organization_id": org_id, "name": APP_NAME, "description": "App pour API Generative"}
    return api_call(url, "POST", headers, create_data)

def create_keys(headers, app_id):
    """Crée de nouvelles clés API pour une application."""
    data = {"application_id": app_id, "description": f"Auto-générée {time.strftime('%Y-%m-%d %H:%M')}"}
    return api_call(f"{IAM_API_BASE_URL}/api-keys", "POST", headers, data)

def store_secret(headers, region, project_id, keys_data):
    """Stocke les clés dans un secret et retourne les détails complets du secret."""
    url = f"{SECRET_MANAGER_BASE_URL}/regions/{region}/secrets"
    list_result = api_call(f"{url}?project_id={project_id}&name={SECRET_NAME}", headers=headers)
    
    if list_result.get("secrets"):
        secret_id = list_result["secrets"][0]["id"]
    else:
        create_data = {"project_id": project_id, "name": SECRET_NAME, "description": "Clés IAM pour API"}
        secret = api_call(url, "POST", headers, create_data)
        secret_id = secret["id"]

    # Création de la nouvelle version
    payload = json.dumps({"API_KEY": keys_data["access_key"], "SECRET_KEY": keys_data["secret_key"]})
    encoded_payload = base64.b64encode(payload.encode('utf-8')).decode('utf-8')
    version_data = {"data": encoded_payload}
    version_info = api_call(f"{url}/{secret_id}/versions", "POST", headers, version_data)

    # CORRECTION : On récupère les détails complets du secret et on y ajoute la nouvelle révision
    secret_details = api_call(f"{url}/{secret_id}", headers=headers)
    secret_details['revision'] = version_info['revision']
    
    return secret_details

def access_secret_version(headers, region, secret_id, version="latest"):
    """Accède au contenu d'une version de secret."""
    url = f"{SECRET_MANAGER_BASE_URL}/regions/{region}/secrets/{secret_id}/versions/{version}/access"
    return api_call(url, headers=headers)

def decode_secret_data(data_string):
    """Décode les données du secret (Base64)."""
    try:
        return json.loads(base64.b64decode(data_string).decode('utf-8'))
    except Exception as e:
        raise ValueError(f"Impossible de décoder les données du secret: {e}") from e
EOT
}

resource "local_file" "retrieval_function" {
  filename = "${path.module}/functions/retrieval/handler.py"
  content = <<-EOT
import os
import base64
import json
import urllib.request
import urllib.error

# --- Constantes ---
SECRET_MANAGER_BASE_URL = "https://api.scaleway.com/secret-manager/v1beta1"
SECRET_NAME = "iam-keys-generative-api"

class SecretRetrievalError(Exception):
    """Exception personnalisée pour les erreurs de récupération."""
    pass

def get_api_keys_from_secret_manager():
    """
    Logique principale pour récupérer et décoder les clés API depuis Secret Manager.
    Lève une SecretRetrievalError en cas de problème.
    """
    try:
        # 1. Récupération des variables d'environnement
        region = os.environ['BETASCW_REGION']
        project_id = os.environ['BETASCW_PROJECT_ID']
        auth_token = os.environ['BETASCW_SECRET_KEY']
        
        headers = {'X-Auth-Token': auth_token}

        # 2. Trouver le secret par son nom pour obtenir son ID
        url_find = f"{SECRET_MANAGER_BASE_URL}/regions/{region}/secrets?name={SECRET_NAME}&project_id={project_id}"
        req_find = urllib.request.Request(url_find, headers=headers)
        with urllib.request.urlopen(req_find) as response:
            secrets = json.loads(response.read().decode())
            if not secrets.get("secrets"):
                raise SecretRetrievalError("Secret non trouvé")
            secret_id = secrets["secrets"][0]["id"]

        # 3. Accéder à la dernière version du secret
        url_access = f"{SECRET_MANAGER_BASE_URL}/regions/{region}/secrets/{secret_id}/versions/latest/access"
        req_access = urllib.request.Request(url_access, headers=headers)
        with urllib.request.urlopen(req_access) as response:
            secret_version = json.loads(response.read().decode())
        
        # 4. Décoder le contenu
        return json.loads(base64.b64decode(secret_version['data']).decode('utf-8'))

    except KeyError as e:
        raise SecretRetrievalError(f"Variable d'environnement manquante: {e}")
    except urllib.error.HTTPError as e:
        raise SecretRetrievalError(f"Erreur API ({e.code}): {e.read().decode()}")
    except Exception as e:
        raise SecretRetrievalError(f"Erreur inattendue: {e}")

def handler(event, context):
    """
    Point d'entrée de la Serverless Function.
    Appelle la logique de récupération et formate la réponse HTTP.
    """
    print(f"Demande de récupération du secret '{SECRET_NAME}' reçue.")
    
    try:
        # Appel de la fonction contenant la logique principale
        api_keys = get_api_keys_from_secret_manager()
        
        print("Récupération réussie.")
        
        # En cas de succès, on retourne les clés
        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps(api_keys)
        }
        
    except SecretRetrievalError as e:
        # En cas d'erreur contrôlée, on retourne une erreur serveur
        print(f"ERREUR: {e}")
        return {
            "statusCode": 500,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": str(e)})
        }
EOT
}

# ====================================================================
# Archives ZIP pour les fonctions
# ====================================================================

data "archive_file" "rotation_function_zip" {
  type        = "zip"
  output_path = "${path.module}/rotation-function.zip"
  source {
    content  = local_file.rotation_function.content
    filename = "handler.py"
  }
  depends_on = [local_file.rotation_function]
}

data "archive_file" "retrieval_function_zip" {
  type        = "zip"
  output_path = "${path.module}/retrieval-function.zip"
  source {
    content  = local_file.retrieval_function.content
    filename = "handler.py"
  }
  depends_on = [local_file.retrieval_function]
}

# ====================================================================
# Namespace pour les fonctions serverless
# ====================================================================

resource "scaleway_function_namespace" "api_rotation" {
  name        = "${var.prefix}-namespace"
  description = "Namespace pour le workflow de rotation des clés API"
  region      = var.scw_region

  environment_variables = {
    BETASCW_SECRET_KEY      = var.scw_secret_key
    BETASCW_PROJECT_ID      = var.scw_project_id
    BETASCW_ORGANIZATION_ID = var.scw_organization_id
    BETASCW_REGION          = var.scw_region
  }

  tags = ["api-rotation", "terraform"]
}

# ====================================================================
# Fonction de rotation des clés
# ====================================================================

resource "scaleway_function" "rotation_function" {
  name         = "${var.prefix}-rotation"
  namespace_id = scaleway_function_namespace.api_rotation.id
  runtime      = "python311"
  handler      = "handler.handler"
  description  = "Fonction de rotation automatique des clés API Scaleway"
  
  zip_file = data.archive_file.rotation_function_zip.output_path
  zip_hash = data.archive_file.rotation_function_zip.output_base64sha256

  deploy      = true
  memory_limit = 256
  timeout     = 300

  # Configuration pour permettre l'invocation via trigger ou manuellement
  privacy = "public"

  environment_variables = {
    FUNCTION_TYPE = "rotation"
  }

  depends_on = [data.archive_file.rotation_function_zip]
}

# ====================================================================
# Fonction de récupération des clés
# ====================================================================

resource "scaleway_function" "retrieval_function" {
  name         = "${var.prefix}-retrieval"
  namespace_id = scaleway_function_namespace.api_rotation.id
  runtime      = "python311"
  handler      = "handler.handler"
  description  = "Fonction de récupération des clés API depuis Secret Manager"
  
  zip_file = data.archive_file.retrieval_function_zip.output_path
  zip_hash = data.archive_file.retrieval_function_zip.output_base64sha256

  deploy      = true
  memory_limit = 128
  timeout     = 60

  privacy = "public"

  environment_variables = {
    FUNCTION_TYPE = "retrieval"
  }

  depends_on = [data.archive_file.retrieval_function_zip]
}

# ====================================================================
# Trigger CRON pour la rotation automatique (optionnel)
# ====================================================================

resource "scaleway_function_cron" "rotation_cron" {
  function_id = scaleway_function.rotation_function.id
  schedule    = "0 2 1 * *"  # Premier jour de chaque mois à 2h du matin
  args = jsonencode({
    "source" = "cron-trigger"
  })
  name = "${var.prefix}-monthly-rotation"
}

# ====================================================================
# Outputs pour affichage des informations importantes
# ====================================================================

output "function_urls" {
  description = "URLs des fonctions déployées"
  value = {
    rotation_url  = "https://${scaleway_function.rotation_function.domain_name}"
    retrieval_url = "https://${scaleway_function.retrieval_function.domain_name}"
  }
}

output "namespace_info" {
  description = "Informations du namespace"
  value = {
    id     = scaleway_function_namespace.api_rotation.id
    name   = scaleway_function_namespace.api_rotation.name
    region = scaleway_function_namespace.api_rotation.region
  }
}

output "function_ids" {
  description = "IDs des fonctions créées"
  value = {
    rotation_id  = scaleway_function.rotation_function.id
    retrieval_id = scaleway_function.retrieval_function.id
  }
}

output "cron_info" {
  description = "Informations du trigger CRON"
  value = {
    cron_id   = scaleway_function_cron.rotation_cron.id
    schedule  = scaleway_function_cron.rotation_cron.schedule
    next_run  = "Premier jour du mois prochain à 2h00"
  }
}