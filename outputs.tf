output "alb_web_dns" {
  description = "Direccion DNS del Application Load Balancer para el WebServer estatico."
  value       = "http://${aws_lb.web.dns_name}"
}

output "alb_backend_dns" {
  description = "Direccion DNS del Application Load Balancer para los backends Docker."
  value       = "http://${aws_lb.api.dns_name}"
}

output "rds_endpoint" {
  description = "Punto de enlace (endpoint) de conexion a la base de datos MySQL."
  value       = aws_db_instance.mysql.endpoint
}

output "rds_password" {
  description = "Contraseña maestra de la base de datos MySQL."
  value       = random_password.rds.result
  sensitive   = true
}

output "backend_instance_ids" {
  description = "Mapa de identificadores de las instancias backend aprovisionadas."
  value       = { for k, b in module.backend : k => b.instance_id }
}

output "nat_gateway_ip" {
  description = "Direccion IP elastica del NAT Gateway (o mensaje informativo si esta deshabilitado)."
  value       = local.es_prod ? try(module.vpc.nat_public_ips[0], "NAT aprovisionandose") : "NAT deshabilitado en ${var.environment}"
}

output "monitoreo_sg_id" {
  description = "ID del Security Group de monitoreo interno habilitado condicionalmente en dev/qa."
  value       = length(aws_security_group.monitoreo) > 0 ? aws_security_group.monitoreo[0].id : "No habilitado en prod"
}

output "subredes_datos_ids" {
  description = "Lista de identificadores de las subredes de datos creadas."
  value       = var.crear_subred_datos ? module.vpc.database_subnets : []
}

output "metadata_despliegue" {
  description = "Resumen de metadata de despliegue serializado en formato JSON."
  value       = local.metadata_json
}
