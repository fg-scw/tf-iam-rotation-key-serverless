
# ====================================================================
# variables.tf (détails supplémentaires)
# ====================================================================

variable "enable_cron" {
  description = "Activer le trigger CRON pour la rotation automatique"
  type        = bool
  default     = true
}

variable "cron_schedule" {
  description = "Expression cron pour la fréquence de rotation (format: minute heure jour mois jour_semaine)"
  type        = string
  default     = "0 2 1 * *"  # 1er jour de chaque mois à 2h00
  validation {
    condition     = can(regex("^[0-9*,/-]+ [0-9*,/-]+ [0-9*,/-]+ [0-9*,/-]+ [0-9*,/-]+$", var.cron_schedule))
    error_message = "Le format cron doit être valide (minute heure jour mois jour_semaine)."
  }
}

variable "rotation_memory_limit" {
  description = "Limite de mémoire pour la fonction de rotation (MB)"
  type        = number
  default     = 256
  validation {
    condition     = var.rotation_memory_limit >= 128 && var.rotation_memory_limit <= 3008
    error_message = "La limite de mémoire doit être entre 128MB et 3008MB."
  }
}

variable "rotation_timeout" {
  description = "Timeout pour la fonction de rotation (secondes)"
  type        = number
  default     = 300
  validation {
    condition     = var.rotation_timeout >= 1 && var.rotation_timeout <= 900
    error_message = "Le timeout doit être entre 1 et 900 secondes."
  }
}

variable "retrieval_memory_limit" {
  description = "Limite de mémoire pour la fonction de récupération (MB)"
  type        = number
  default     = 128
}

variable "retrieval_timeout" {
  description = "Timeout pour la fonction de récupération (secondes)"
  type        = number
  default     = 60
}