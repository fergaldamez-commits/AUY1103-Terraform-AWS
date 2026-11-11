variable "environment" {
  description = "Ambiente de despliegue (dev, qa, prod)."
  type        = string

  validation {
    condition     = contains(["dev", "qa", "prod"], var.environment)
    error_message = "El ambiente debe ser uno de los permitidos: dev, qa o prod."
  }
}

variable "empresa" {
  description = "Nombre o identificador corto de la empresa."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.empresa))
    error_message = "La empresa solo puede contener caracteres alfanumericos en minusculas y guiones."
  }
}

variable "proyecto" {
  description = "Nombre del proyecto o plataforma a desplegar."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.proyecto))
    error_message = "El proyecto solo puede contener caracteres alfanumericos en minusculas y guiones."
  }
}

variable "integrantes" {
  description = "Lista de nombres de los integrantes a cargo del proyecto."
  type        = list(string)
  default     = ["fernando galdamez"]
}

variable "vpc_cidr" {
  description = "Bloque CIDR asignado a la VPC."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr debe ser un bloque de red IPv4 valido en formato CIDR."
  }
}

variable "cantidad_zonas" {
  description = "Cantidad de zonas de disponibilidad a utilizar (entre 2 y 3)."
  type        = number

  validation {
    condition     = tonumber(var.cantidad_zonas) >= 2 && tonumber(var.cantidad_zonas) <= 3
    error_message = "La cantidad de zonas debe ser un numero entre 2 y 3."
  }
}

variable "crear_subred_datos" {
  description = "Bandera booleana para decidir si se aprovisionan subredes dedicadas a datos."
  type        = bool
}

variable "conservar_datos" {
  description = "Bandera booleana para determinar si se genera snapshot final antes de destruir RDS."
  type        = bool
}

variable "snapshot_restauracion" {
  description = "Identificador o ARN de un snapshot previo de RDS para restaurar la base de datos (null si es creacion inicial)."
  type        = string
  default     = null
}
