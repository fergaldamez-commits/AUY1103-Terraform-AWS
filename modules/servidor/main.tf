terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

resource "aws_security_group" "this" {
  name_prefix = "${var.nombre}-sg-"
  description = "SG de ${var.nombre}"
  vpc_id      = var.vpc_id

  # Las reglas se pasan como parámetro para que cada uso del módulo defina su propio acceso.
  dynamic "ingress" {
    for_each = var.reglas_ingress
    content {
      description     = ingress.value.descripcion
      from_port       = ingress.value.puerto
      to_port         = ingress.value.puerto
      protocol        = ingress.value.protocolo
      cidr_blocks     = ingress.value.cidr_blocks
      security_groups = ingress.value.security_groups
    }
  }

  egress {
    description = "Salida total via NAT"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.nombre}-sg" })

  # Se crea el SG nuevo antes de borrar el viejo para no dejar la instancia sin SG.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_instance" "this" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.this.id]
  associate_public_ip_address = var.asociar_ip_publica
  iam_instance_profile        = var.perfil_iam

  user_data                   = var.user_data
  user_data_replace_on_change = true # Si cambia el bootstrap, la instancia se reemplaza (infraestructura inmutable).

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # Obliga a usar IMDSv2
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.tamano_disco_gb
    encrypted             = true
    delete_on_termination = true
  }

  tags = merge(var.tags, { Name = var.nombre })
}
