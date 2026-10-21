resource "aws_db_subnet_group" "rds" {
  name        = "${local.nombre_base}-rds-subnets"
  description = "Subredes para RDS (acceso restringido por SG)"
  subnet_ids  = module.vpc.public_subnets

  tags = merge(local.tags_comunes, { Name = "${local.nombre_base}-rds-subnets" })
}

resource "random_password" "rds" {
  length           = 20
  special          = true
  override_special = "!#$%^&*()-_=+" # RDS no acepta '/', '@', '"' ni espacios
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
}

resource "aws_security_group" "rds" {
  name_prefix = "${local.nombre_base}-rds-"
  description = "MySQL solo desde backends e IP del operador"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "MySQL desde SG de backends"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [for b in module.backend : b.security_group_id]
  }

  # Regla de mínimo privilegio para administración desde la IP pública del estudiante.
  ingress {
    description = "MySQL desde IP publica del operador"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [local.mi_ip_cidr]
  }

  egress {
    description = "Salida total"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags_comunes, { Name = "${local.nombre_base}-rds-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "mysql" {
  identifier        = "${local.nombre_base}-mysql"
  engine            = "mysql"
  engine_version    = var.db_engine_version
  instance_class    = var.db_instance_class
  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_nombre
  username = var.db_username
  password = random_password.rds.result

  # En subredes públicas para validar la conexión directa desde MySQL Workbench/DBeaver según la Etapa 3 de la pauta,
  # pero restringido por el Security Group únicamente a los backends y a la IP pública del estudiante (/32).
  db_subnet_group_name   = aws_db_subnet_group.rds.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = true
  multi_az               = false

  backup_retention_period = 0 # Entorno académico: sin backups, para crear y destruir más rápido
  skip_final_snapshot     = true
  deletion_protection     = false
  apply_immediately       = true

  tags = merge(local.tags_comunes, { Name = "${local.nombre_base}-mysql" })
}
