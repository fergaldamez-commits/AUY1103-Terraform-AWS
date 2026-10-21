# ==================== Security Groups de los ALB ====================
resource "aws_security_group" "alb" {
  for_each = toset(["web", "backend"])

  name_prefix = "${local.nombre_base}-alb-${each.key}-"
  description = "SG del ALB ${each.key}"
  vpc_id      = module.vpc.vpc_id

  dynamic "ingress" {
    for_each = var.puertos_alb_publicos
    content {
      description = "Trafico publico puerto ${ingress.value}"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    description = "Salida hacia targets"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags_comunes, { Name = "${local.nombre_base}-alb-${each.key}-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

# ==================== WebServer estático (módulo local) ====================
module "web" {
  source = "./modules/servidor"

  nombre          = "${local.nombre_base}-web"
  ami_id          = data.aws_ami.ubuntu.id
  instance_type   = var.instance_type
  vpc_id          = module.vpc.vpc_id
  subnet_id       = module.vpc.private_subnets[0] # Subred privada: solo se llega a través del ALB
  tamano_disco_gb = var.tamano_disco_gb

  user_data = templatefile("${path.module}/templates/web_nginx.sh.tftpl", {
    proyecto      = var.proyecto
    nombre_alumno = var.nombre_alumno
    entorno       = var.entorno
    asignatura    = var.asignatura
  })

  reglas_ingress = [{
    descripcion     = "HTTP solo desde ALB web"
    puerto          = 80
    security_groups = [aws_security_group.alb["web"].id]
  }]

  tags = merge(local.tags_comunes, { Rol = "webserver" })
}

# ==================== Backends Docker (módulo local + for_each) ====================
module "backend" {
  source   = "./modules/servidor"
  for_each = local.backends

  nombre          = "${local.nombre_base}-${each.key}"
  ami_id          = data.aws_ami.ubuntu.id
  instance_type   = var.instance_type
  vpc_id          = module.vpc.vpc_id
  subnet_id       = module.vpc.private_subnets[each.value % length(module.vpc.private_subnets)]
  tamano_disco_gb = var.tamano_disco_gb

  user_data = templatefile("${path.module}/templates/backend_docker.sh.tftpl", {
    nombre_contenedor = "web-${each.key}"
    imagen_docker     = var.imagen_docker
    puerto            = 80
  })

  reglas_ingress = [{
    descripcion     = "HTTP solo desde ALB backends"
    puerto          = 80
    security_groups = [aws_security_group.alb["backend"].id]
  }]

  tags = merge(local.tags_comunes, { Rol = "backend", Backend = each.key })
}

# ==================== ALB Estático ====================
resource "aws_lb" "web" {
  name                       = "${local.nombre_base}-alb-web"
  load_balancer_type         = "application"
  internal                   = false
  security_groups            = [aws_security_group.alb["web"].id]
  subnets                    = module.vpc.public_subnets
  drop_invalid_header_fields = true

  tags = merge(local.tags_comunes, { Name = "${local.nombre_base}-alb-web" })
}

resource "aws_lb_target_group" "web" {
  name        = "${local.nombre_base}-tg-web"
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

# ==================== ALB Backends ====================
resource "aws_lb" "backend" {
  name                       = "${local.nombre_base}-alb-be"
  load_balancer_type         = "application"
  internal                   = false
  security_groups            = [aws_security_group.alb["backend"].id]
  subnets                    = module.vpc.public_subnets
  drop_invalid_header_fields = true

  tags = merge(local.tags_comunes, { Name = "${local.nombre_base}-alb-be" })
}

resource "aws_lb_target_group" "backend" {
  name        = "${local.nombre_base}-tg-be"
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

resource "aws_lb_target_group_attachment" "backend" {
  for_each = module.backend

  target_group_arn = aws_lb_target_group.backend.arn
  target_id        = each.value.instance_id
  port             = 80
}

resource "aws_lb_listener" "backend_http" {
  load_balancer_arn = aws_lb.backend.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
}
