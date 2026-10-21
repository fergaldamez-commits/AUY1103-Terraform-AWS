module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${local.nombre_base}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  public_subnets  = local.subredes_publicas
  private_subnets = local.subredes_privadas

  # Un solo NAT para reducir costos en el Learner Lab. Se acepta perder alta disponibilidad de salida a Internet.
  enable_nat_gateway = true
  single_nat_gateway = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags  = { Tier = "public" }
  private_subnet_tags = { Tier = "private" }

  tags = local.tags_comunes
}
