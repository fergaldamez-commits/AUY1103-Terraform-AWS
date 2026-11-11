data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_region" "current" {}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  lifecycle {
    postcondition {
      condition     = self.architecture == "x86_64"
      error_message = "La AMI obtenida debe ser estrictamente de arquitectura x86_64 para compatibilidad con el software."
    }
  }
}

data "http" "mi_ip" {
  url = "https://checkip.amazonaws.com"

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "No se pudo obtener la direccion IP publica desde el servicio checkip de AWS."
    }
  }
}
