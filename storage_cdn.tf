resource "random_id" "sufijo_bucket" {
  byte_length = 4
}

resource "aws_s3_bucket" "estatico" {
  bucket        = "${local.nombre_base}-estatico-${random_id.sufijo_bucket.hex}"
  force_destroy = true # Permite destroy limpio en un entorno académico efímero

  tags = merge(local.tags_comunes, { Name = "${local.nombre_base}-estatico" })
}

resource "aws_s3_bucket_versioning" "estatico" {
  bucket = aws_s3_bucket.estatico.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "estatico" {
  bucket = aws_s3_bucket.estatico.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# SSE-S3 (y no KMS) porque OAC funciona sin tener que modificar políticas de llaves.
resource "aws_s3_bucket_server_side_encryption_configuration" "estatico" {
  bucket = aws_s3_bucket.estatico.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_object" "logo_svg" {
  bucket       = aws_s3_bucket.estatico.id
  key          = "logo.svg"
  content_type = "image/svg+xml"
  content      = <<-SVG
    <svg xmlns="http://www.w3.org/2000/svg" width="520" height="220" viewBox="0 0 520 220">
      <rect width="520" height="220" rx="16" fill="#0f172a"/>
      <text x="260" y="85" font-family="Arial,sans-serif" font-size="26" font-weight="bold" fill="#38bdf8" text-anchor="middle">Duoc UC - ${var.asignatura}</text>
      <text x="260" y="130" font-family="Arial,sans-serif" font-size="20" fill="#f8fafc" text-anchor="middle">Alumno: ${var.nombre_alumno}</text>
      <text x="260" y="170" font-family="Arial,sans-serif" font-size="16" fill="#94a3b8" text-anchor="middle">CloudFront + S3 (OAC) | Entorno: ${var.entorno}</text>
    </svg>
  SVG
  etag         = md5("${var.asignatura}${var.nombre_alumno}${var.entorno}")
}

resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.estatico.id
  key          = "index.html"
  content_type = "text/html; charset=utf-8"
  content      = <<-HTML
    <!DOCTYPE html>
    <html lang="es">
    <head><meta charset="utf-8"><title>${var.proyecto} CDN</title></head>
    <body style="font-family:sans-serif;text-align:center;margin-top:6%">
      <h1>Contenido servido por CloudFront + S3 (OAC)</h1>
      <h2>Alumno: ${var.nombre_alumno}</h2>
      <p>Entorno: ${var.entorno}</p>
      <img src="/logo.svg" alt="Imagen desde S3 via CloudFront" style="margin-top:20px;box-shadow:0 8px 24px rgba(0,0,0,0.2);border-radius:16px"/>
    </body>
    </html>
  HTML
  etag         = md5("${var.proyecto}${var.nombre_alumno}${var.entorno}")
}

resource "aws_cloudfront_origin_access_control" "s3" {
  name                              = "${local.nombre_base}-oac"
  description                       = "OAC para bucket ${aws_s3_bucket.estatico.id}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CDN ${local.nombre_base}"
  default_root_object = "index.html"
  price_class         = var.cloudfront_price_class

  origin {
    domain_name              = aws_s3_bucket.estatico.bucket_regional_domain_name
    origin_id                = "s3-${aws_s3_bucket.estatico.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.s3.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-${aws_s3_bucket.estatico.id}"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = merge(local.tags_comunes, { Name = "${local.nombre_base}-cdn" })
}

# Solo esta distribución puede leer el bucket (condición AWS:SourceArn). Así se evita el problema de "confused deputy".
data "aws_iam_policy_document" "bucket_cdn" {
  statement {
    sid       = "AllowCloudFrontOAC"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.estatico.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.cdn.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "estatico" {
  bucket = aws_s3_bucket.estatico.id
  policy = data.aws_iam_policy_document.bucket_cdn.json

  depends_on = [aws_s3_bucket_public_access_block.estatico]
}
