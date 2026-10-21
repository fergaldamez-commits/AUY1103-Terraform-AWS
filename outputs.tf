output "cloudfront_url" {
  description = "URL HTTPS de la distribución CloudFront."
  value       = "https://${aws_cloudfront_distribution.cdn.domain_name}"
}

output "cloudfront_image_url" {
  description = "URL directa a la imagen alojada en S3 y servida por CloudFront."
  value       = "https://${aws_cloudfront_distribution.cdn.domain_name}/logo.svg"
}

output "alb_web_dns" {
  description = "DNS del ALB del WebServer estático."
  value       = "http://${aws_lb.web.dns_name}"
}

output "alb_backend_dns" {
  description = "DNS del ALB de los backends."
  value       = "http://${aws_lb.backend.dns_name}"
}

output "rds_endpoint" {
  description = "Endpoint (host:puerto) de RDS MySQL."
  value       = aws_db_instance.mysql.endpoint
}

output "bucket_name" {
  description = "Nombre del bucket S3 privado."
  value       = aws_s3_bucket.estatico.id
}

output "backend_instance_ids" {
  description = "IDs de las instancias backend por clave."
  value       = { for k, b in module.backend : k => b.instance_id }
}

output "region_desplegada" {
  description = "Región en uso."
  value       = data.aws_region.actual.region
}

output "rds_password" {
  description = "Password maestro de RDS."
  value       = random_password.rds.result
  sensitive   = true
}
