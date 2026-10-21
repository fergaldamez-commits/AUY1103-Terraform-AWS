variable "nombre" {
  description = "Nombre lógico de la instancia (se usa en Name y en el prefijo del SG)."
  type        = string
}

variable "ami_id" {
  description = "ID de la AMI que se usa para la instancia."
  type        = string
}

variable "instance_type" {
  description = "Tipo de instancia EC2."
  type        = string
}

variable "vpc_id" {
  description = "VPC donde se crea el Security Group."
  type        = string
}

variable "subnet_id" {
  description = "Subred donde se lanza la instancia."
  type        = string
}

variable "user_data" {
  description = "Script de arranque (cloud-init), ya renderizado con templatefile()."
  type        = string
}

variable "reglas_ingress" {
  description = "Reglas de entrada del SG. Se acepta origen por CIDR o por Security Group."
  type = list(object({
    descripcion     = string
    puerto          = number
    protocolo       = optional(string, "tcp")
    cidr_blocks     = optional(list(string), [])
    security_groups = optional(list(string), [])
  }))
  default = []
}

variable "asociar_ip_publica" {
  description = "Asociar IP pública a la instancia."
  type        = bool
  default     = false
}

variable "perfil_iam" {
  description = "Instance profile IAM opcional (por ejemplo LabInstanceProfile en el Learner Lab)."
  type        = string
  default     = null
}

variable "tamano_disco_gb" {
  description = "Tamaño del volumen raíz en GB."
  type        = number
  default     = 10
}

variable "tags" {
  description = "Tags que se aplican a la instancia y al SG."
  type        = map(string)
  default     = {}
}
