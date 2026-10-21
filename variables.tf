# ---------- Generales ----------
variable "region" {
  description = "Región AWS de despliegue (Learner Lab: us-east-1 o us-west-2)."
  type        = string
}

variable "proyecto" {
  description = "Nombre corto del proyecto, se usa como prefijo de los recursos."
  type        = string
  default     = "auy1103"
}

variable "entorno" {
  description = "Entorno de despliegue (dev o prod)."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.entorno)
    error_message = "entorno debe ser 'dev' o 'prod'."
  }
}

variable "owner" {
  description = "Responsable de la infraestructura (tag Owner)."
  type        = string
}

variable "asignatura" {
  description = "Código de la asignatura (tag Asignatura)."
  type        = string
  default     = "AUY1103"
}

variable "nombre_alumno" {
  description = "Nombre del alumno que se muestra en el index.html del WebServer y del CDN."
  type        = string
}

variable "tags_adicionales" {
  description = "Tags extra que se combinan con los tags comunes."
  type        = map(string)
  default     = {}
}

# ---------- Red ----------
variable "vpc_cidr" {
  description = "Bloque CIDR de la VPC. Las subredes se derivan de él con cidrsubnet()."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr debe ser un CIDR IPv4 válido."
  }
}

variable "puertos_alb_publicos" {
  description = "Puertos que exponen los ALB a Internet (se usan en el bloque dynamic ingress)."
  type        = list(number)
  default     = [80]
}

# ---------- Cómputo ----------
variable "instance_type" {
  description = "Tipo de instancia EC2 para el WebServer y los backends."
  type        = string
}

variable "cantidad_backends" {
  description = "Cantidad de instancias backend con Docker."
  type        = number

  validation {
    condition     = var.cantidad_backends > 0 && var.cantidad_backends <= 6 && floor(var.cantidad_backends) == var.cantidad_backends
    error_message = "cantidad_backends debe ser un número entero entre 1 y 6 (límite del Learner Lab)."
  }
}

variable "imagen_docker" {
  description = "Imagen del contenedor web que corre en los backends."
  type        = string
  default     = "nginxdemos/hello:latest"
}

variable "tamano_disco_gb" {
  description = "Tamaño del volumen raíz de las EC2 en GB."
  type        = number
  default     = 10
}

# ---------- CDN ----------
variable "cloudfront_price_class" {
  description = "Price class de CloudFront."
  type        = string
  default     = "PriceClass_100"
}

# ---------- Base de datos ----------
variable "db_instance_class" {
  description = "Clase de instancia RDS."
  type        = string
  default     = "db.t3.micro"
}

variable "db_engine_version" {
  description = "Versión del motor MySQL."
  type        = string
  default     = "8.0"
}

variable "db_nombre" {
  description = "Nombre de la base de datos inicial."
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Usuario maestro de RDS."
  type        = string
  default     = "dbadmin"
  sensitive   = true
}

variable "db_allocated_storage" {
  description = "Almacenamiento asignado a RDS en GB."
  type        = number
  default     = 20
}
