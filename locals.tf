locals {
  # Condicion booleana de ambiente de produccion
  es_prod = var.environment == "prod"

  # Construccion estandarizada de prefijos con funciones de cadena
  prefijo = lower(format("%s-%s-%s", replace(trimspace(var.empresa), " ", "-"), replace(trimspace(var.proyecto), " ", "-"), trimspace(var.environment)))

  # Prefijo truncado a maximo 32 caracteres para identificadores de ALB y Target Groups
  prefijo_truncado = substr(local.prefijo, 0, 32)

  # Etiquetas comunes utilizando merge() y transformaciones funcionales
  tags_comunes = merge(
    {
      Environment = upper(var.environment)
      Owner       = join(", ", [for i in var.integrantes : title(trimspace(i))])
      Project     = title(var.proyecto)
      Asignatura  = "AUY1103"
      ManagedBy   = "Terraform"
    }
  )

  # Matriz de configuracion multi-ambiente
  config = {
    dev = {
      backends_count     = 2
      instance_type      = "t3.micro"
      cantidad_zonas     = 2
      rds_retention_days = 1
      multi_az           = false
      deletion_protect   = false
    }
    qa = {
      backends_count     = 3
      instance_type      = "t3.micro"
      cantidad_zonas     = 2
      rds_retention_days = 3
      multi_az           = false
      deletion_protect   = false
    }
    prod = {
      backends_count     = 4
      instance_type      = "t3.small"
      cantidad_zonas     = 3
      rds_retention_days = 7
      multi_az           = true
      deletion_protect   = true
    }
  }

  # Resolucion de configuracion del ambiente actual mediante lookup() con valor por defecto
  env_config = lookup(local.config, var.environment, local.config["dev"])

  # Obtencion de valores individuales con lookup() y valor por defecto
  backend_count_num  = lookup(local.env_config, "backends_count", 2)
  instance_type_val  = lookup(local.env_config, "instance_type", "t3.micro")
  retention_days_val = lookup(local.env_config, "rds_retention_days", 1)

  # Mapa de backends indexado de manera estatica para for_each
  backends_map = {
    for idx in range(local.backend_count_num) :
    format("backend-%02d", idx + 1) => idx
  }

  # Zonas seleccionadas segun var.cantidad_zonas con slice()
  zonas_seleccionadas = slice(data.aws_availability_zones.available.names, 0, var.cantidad_zonas)

  # Subredes calculadas dinamicamente con expresiones for y cidrsubnet()
  subredes_publicas = [for i in range(length(local.zonas_seleccionadas)) : cidrsubnet(var.vpc_cidr, 8, i)]
  subredes_privadas = [for i in range(length(local.zonas_seleccionadas)) : cidrsubnet(var.vpc_cidr, 8, i + 10)]
  subredes_datos    = var.crear_subred_datos ? [for i in range(length(local.zonas_seleccionadas)) : cidrsubnet(var.vpc_cidr, 8, i + 20)] : []

  # IP publica del operador con manejo robusto de errores mediante try() y coalesce()
  ip_operador_limpia = try(chomp(coalesce(data.http.mi_ip.response_body, "127.0.0.1\n")), "127.0.0.1")
  ip_operador_cidr   = "${local.ip_operador_limpia}/32"

  # Reglas de seguridad parametrizadas con lista de ambientes aplicables
  reglas_seguridad = [
    {
      puerto      = 22
      descripcion = "Acceso SSH administrativo para ambiente de desarrollo"
      ambientes   = ["dev"]
      cidr_blocks = [local.ip_operador_cidr]
    },
    {
      puerto      = 80
      descripcion = "Trafico web HTTP publico"
      ambientes   = ["dev", "qa", "prod"]
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]

  # Reglas filtradas dinamicamente mediante for e if
  reglas_filtradas = [
    for r in local.reglas_seguridad : r
    if contains(r.ambientes, var.environment)
  ]

  # Uso funcional explícito de built-in functions: keys, values, flatten, distinct, jsonencode, tostring
  ambientes_disponibles = keys(local.config)
  config_valores        = values(local.config)
  todas_las_subredes    = distinct(flatten([local.subredes_publicas, local.subredes_privadas, local.subredes_datos]))
  metadata_json         = jsonencode({
    ambiente = tostring(var.environment)
    prefijo  = tostring(local.prefijo)
    subredes = length(local.todas_las_subredes)
  })
}
