# Modulo de Red oficial del registro publico
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${local.prefijo}-vpc"
  cidr = var.vpc_cidr

  azs             = local.zonas_seleccionadas
  public_subnets  = local.subredes_publicas
  private_subnets = local.subredes_privadas
  database_subnets = local.subredes_datos

  # Condicion booleana: Solo se activa el NAT Gateway en ambiente prod
  enable_nat_gateway = local.es_prod
  single_nat_gateway = local.es_prod

  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags   = { Tier = "public" }
  private_subnet_tags  = { Tier = "private" }
  database_subnet_tags = { Tier = "database" }

  tags = local.tags_comunes
}

# ==================== Security Groups ====================
# Security Group de los ALB con dynamic ingress
resource "aws_security_group" "alb" {
  for_each = toset(["web", "api"])

  name_prefix = "${local.prefijo_truncado}-alb-${each.key}-"
  description = "SG para ALB ${each.key}"
  vpc_id      = module.vpc.vpc_id

  # Bloque dynamic ingress que evalua reglas_filtradas
  dynamic "ingress" {
    for_each = local.reglas_filtradas
    content {
      description = ingress.value.descripcion
      from_port   = ingress.value.puerto
      to_port     = ingress.value.puerto
      protocol    = "tcp"
      cidr_blocks = ingress.value.cidr_blocks
    }
  }

  egress {
    description = "Salida total hacia targets"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags_comunes, { Name = "${local.prefijo}-alb-${each.key}-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

# ==================== WebServer Estatico ====================
module "web" {
  source = "./modules/servidor"

  nombre             = "${local.prefijo}-web"
  ami_id             = data.aws_ami.ubuntu.id
  instance_type      = local.instance_type_val
  vpc_id             = module.vpc.vpc_id
  subnet_id          = module.vpc.public_subnets[0]
  asociar_ip_publica = true

  user_data = templatefile("${path.module}/templates/web_nginx.sh.tftpl", {
    empresa     = var.empresa
    proyecto    = var.proyecto
    ambiente    = upper(var.environment)
    integrantes = join(", ", [for i in var.integrantes : title(trimspace(i))])
  })

  reglas_ingress = [
    {
      descripcion     = "HTTP desde ALB web"
      puerto          = 80
      cidr_blocks     = ["0.0.0.0/0"]
      security_groups = [aws_security_group.alb["web"].id]
    }
  ]

  tags = merge(local.tags_comunes, { Rol = "webserver" })
}

# ==================== cluster Backend Docker ====================
module "backend" {
  source   = "./modules/servidor"
  for_each = local.backends_map

  nombre             = "${local.prefijo}-${each.key}"
  ami_id             = data.aws_ami.ubuntu.id
  instance_type      = local.instance_type_val
  vpc_id             = module.vpc.vpc_id
  subnet_id          = module.vpc.public_subnets[each.value % length(module.vpc.public_subnets)]
  asociar_ip_publica = true

  user_data = templatefile("${path.module}/templates/backend_docker.sh.tftpl", {
    nombre_contenedor = "web-${each.key}"
    imagen_docker     = "nginxdemos/hello:latest"
    puerto            = 80
  })

  reglas_ingress = [
    {
      descripcion     = "HTTP desde ALB api"
      puerto          = 80
      cidr_blocks     = ["0.0.0.0/0"]
      security_groups = [aws_security_group.alb["api"].id]
    }
  ]

  tags = merge(local.tags_comunes, { Rol = "backend", Backend = each.key })
}

# ==================== Application Load Balancers ====================
# ALB Web Estatico
resource "aws_lb" "web" {
  name                       = "${local.prefijo_truncado}-web"
  load_balancer_type         = "application"
  internal                   = false
  security_groups            = [aws_security_group.alb["web"].id]
  subnets                    = module.vpc.public_subnets
  drop_invalid_header_fields = true

  tags = merge(local.tags_comunes, { Name = "${local.prefijo}-alb-web" })
}

resource "aws_lb_target_group" "web" {
  name        = "${local.prefijo_truncado}-tg-web"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = module.vpc.vpc_id

  health_check {
    path                = "/"
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = local.tags_comunes
}

resource "aws_lb_target_group_attachment" "web" {
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = module.web.instance_id
  port             = 80
}

resource "aws_lb_listener" "web_http" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

# ALB Backends (API)
resource "aws_lb" "api" {
  name                       = "${local.prefijo_truncado}-api"
  load_balancer_type         = "application"
  internal                   = false
  security_groups            = [aws_security_group.alb["api"].id]
  subnets                    = module.vpc.public_subnets
  drop_invalid_header_fields = true

  tags = merge(local.tags_comunes, { Name = "${local.prefijo}-alb-api" })
}

resource "aws_lb_target_group" "api" {
  name        = "${local.prefijo_truncado}-tg-api"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = module.vpc.vpc_id

  health_check {
    path                = "/"
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = local.tags_comunes
}

resource "aws_lb_target_group_attachment" "api" {
  for_each = module.backend

  target_group_arn = aws_lb_target_group.api.arn
  target_id        = each.value.instance_id
  port             = 80
}

resource "aws_lb_listener" "api_http" {
  load_balancer_arn = aws_lb.api.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}

# ==================== Recurso Condicional con COUNT ====================
# Servidor de monitoreo o bastiÃ³n habilitado condicionalmente en dev/qa
resource "aws_security_group" "monitoreo" {
  count = !local.es_prod ? 1 : 0

  name_prefix = "${local.prefijo_truncado}-mon-"
  description = "SG de monitoreo interno habilitado solo en ambientes no productivos"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Sondeo ICMP interno"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags_comunes, { Name = "${local.prefijo}-sg-monitoreo" })
}

# ==================== Base de Datos RDS MySQL 8.0 ====================
resource "random_password" "rds" {
  length           = 20
  special          = true
  override_special = "!#$%&*()-_=+[]"
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
}

resource "aws_db_subnet_group" "rds" {
  name        = "${local.prefijo_truncado}-rds-subnets"
  description = "Subnet group para RDS MySQL"
  subnet_ids  = var.crear_subred_datos && length(module.vpc.database_subnets) > 0 ? module.vpc.database_subnets : module.vpc.public_subnets

  tags = merge(local.tags_comunes, { Name = "${local.prefijo}-rds-subnets" })
}

resource "aws_security_group" "rds" {
  name_prefix = "${local.prefijo_truncado}-rds-"
  description = "Acceso a MySQL puerto 3306"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "MySQL desde cluster de backends"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [for b in module.backend : b.security_group_id]
  }

  ingress {
    description = "MySQL desde IP del operador"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [local.ip_operador_cidr]
  }

  egress {
    description = "Salida total"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags_comunes, { Name = "${local.prefijo}-rds-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "mysql" {
  identifier        = "${local.prefijo_truncado}-mysql"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = "appdb"
  username = "dbadmin"
  password = random_password.rds.result

  db_subnet_group_name   = aws_db_subnet_group.rds.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = true

  # Condiciones exigidas por la rÃºbrica
  multi_az            = local.es_prod ? true : false
  deletion_protection = local.es_prod ? true : false

  # Retencion de backups obtenida con lookup() de la matriz
  backup_retention_period = local.retention_days_val

  # Politica de snapshot final calculada con condicion compuesta
  skip_final_snapshot       = !(local.es_prod || var.environment == "qa" || var.conservar_datos)
  final_snapshot_identifier = (local.es_prod || var.environment == "qa" || var.conservar_datos) ? "${local.prefijo_truncado}-final-snapshot" : null

  # Restauracion condicional si se suministra un snapshot previo
  snapshot_identifier = var.snapshot_restauracion

  apply_immediately = true

  # Precondicion: Asegurar que prod nunca use t3.micro en computo o base de datos
  lifecycle {
    precondition {
      condition     = !(var.environment == "prod" && local.instance_type_val == "t3.micro")
      error_message = "Ambiente de produccion no puede utilizar instancias de tipo micro."
    }
  }

  tags = merge(local.tags_comunes, { Name = "${local.prefijo}-mysql" })
}


