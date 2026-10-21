locals {
  nombre_base = lower("${var.proyecto}-${var.entorno}")

  tags_comunes = merge(
    var.tags_adicionales,
    {
      Owner       = var.owner
      Environment = var.entorno
      Project     = var.proyecto
      Asignatura  = var.asignatura
      ManagedBy   = "Terraform"
    }
  )

  azs = slice(data.aws_availability_zones.disponibles.names, 0, 2)

  # Subredes derivadas de var.vpc_cidr: sin CIDR fijos en el código.
  subredes_publicas = [for i in range(length(local.azs)) : cidrsubnet(var.vpc_cidr, 8, i)]
  subredes_privadas = [for i in range(length(local.azs)) : cidrsubnet(var.vpc_cidr, 8, i + 10)]

  mi_ip_cidr = "${chomp(data.http.mi_ip.response_body)}/32"

  # Las claves del mapa vienen solo de variables (se conocen en el plan). El valor se usa para repartir instancias entre AZs.
  backends = {
    for i in range(var.cantidad_backends) :
    format("backend-%02d", i + 1) => i
  }
}
