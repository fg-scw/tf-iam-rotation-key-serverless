# ====================================================================
# outputs.tf (outputs étendus)
# ====================================================================

output "deployment_summary" {
  description = "Résumé du déploiement"
  value = {
    namespace = {
      id   = scaleway_function_namespace.api_rotation.id
      name = scaleway_function_namespace.api_rotation.name
    }
    functions = {
      rotation = {
        id     = scaleway_function.rotation_function.id
        url    = "https://${scaleway_function.rotation_function.domain_name}"
        memory = scaleway_function.rotation_function.memory_limit
      }
      retrieval = {
        id     = scaleway_function.retrieval_function.id
        url    = "https://${scaleway_function.retrieval_function.domain_name}"
        memory = scaleway_function.retrieval_function.memory_limit
      }
    }
    automation = var.enable_cron ? {
      enabled  = true
      schedule = var.cron_schedule
      cron_id  = scaleway_function_cron.rotation_cron.id
    } : {
      enabled = false
    }
  }
}

output "curl_examples" {
  description = "Exemples de commandes curl pour tester les fonctions"
  value = {
    test_rotation = "curl -X POST https://${scaleway_function.rotation_function.domain_name}"
    test_retrieval = "curl -X GET https://${scaleway_function.retrieval_function.domain_name}"
  }
}

output "important_notes" {
  description = "Notes importantes pour l'utilisation"
  value = <<-EOT
  
  
  ✅ Fonctions créées:
     - Rotation: https://${scaleway_function.rotation_function.domain_name}
     - Récupération: https://${scaleway_function.retrieval_function.domain_name}
  
  ⏰ Rotation automatique: ${var.enable_cron ? "Activée (${var.cron_schedule})" : "Désactivée"}
  
  📝 Prochaines étapes:
     1. Testez la fonction de rotation manuellement 
        --> https://${scaleway_function.rotation_function.domain_name}
     2. Vérifiez que le secret est créé dans Secret Manager
     3. Testez la fonction de récupération
        --> https://${scaleway_function.retrieval_function.domain_name}
     4. Surveillez les logs des fonctions
  
  ⚠️  Important: 
     - Les clés sont stockées dans le Secret Manager sous le nom 'iam-keys-generative-api'
     - Vérifiez les permissions IAM si vous rencontrez des erreurs
  
  EOT
}