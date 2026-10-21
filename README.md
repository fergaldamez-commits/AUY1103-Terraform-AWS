# AUY1103 – Infraestructura como Código I (Evaluación Parcial N° 2)

**Estudiantes:** Fernando Galdamez y Jose Villaroel  
**Contacto:** `fer.galdamez@duocuc.cl`  
**Entorno de Nube:** AWS Academy Learner Lab (`us-east-1`)  

---

## 1. Resumen de la Arquitectura Implementada

Se implementó en AWS la arquitectura completa descrita en la pauta de evaluación mediante código Terraform profesional y modular:
* **Red (VPC):** Creada con el módulo verificado `terraform-aws-modules/vpc/aws` (`~> 6.0`). Integra 2 Zonas de Disponibilidad (`us-east-1a`, `us-east-1b`), subredes públicas y privadas aisladas, Internet Gateway, tablas de enrutamiento dedicadas y un único NAT Gateway (`single_nat_gateway = true`) para optimizar el presupuesto del laboratorio.
* **Capa Web Estática:** Instancia EC2 con Ubuntu 24.04 aprovisionada en subred privada a través del módulo local `./modules/servidor`. Contiene Nginx sirviendo una página personalizada con los nombres de los estudiantes. Su Security Group restringe el tráfico entrante únicamente al Security Group de su Application Load Balancer (`ALB`).
* **Capa Backend Distribuida:** 3 instancias EC2 iteradas con `for_each` sobre el módulo local `./modules/servidor`, ejecutando contenedores Docker web (`nginxdemos/hello`). Balanceadas por un segundo ALB público que distribuye el tráfico equitativamente entre las instancias registradas y saludables.
* **Base de Datos:** Instancia Amazon RDS MySQL 8.0 (`db.t3.micro`) configurada en un `aws_db_subnet_group` con credenciales administradas por `random_password` (marcada `sensitive`), deshabilitando snapshots finales y protección contra eliminación para garantizar ciclos de vida efímeros. Su Security Group admite conexiones exclusivamente desde los Security Groups de los backends y la dirección IP pública del administrador (`data.http.mi_ip`).
* **Almacenamiento y CDN:** Bucket Amazon S3 privado con versionamiento activado y bloqueo estricto de acceso público, conectado con CloudFront mediante Origin Access Control (`OAC`).

---

## 2. Tabla de Módulos Utilizados

| Módulo | Tipo / Origen | Versión | Propósito Arquitectónico |
|---|---|---|---|
| `vpc` | Registro Público (`terraform-aws-modules/vpc/aws`) | `~> 6.0` | Abstracción integral de red: VPC, subredes públicas/privadas, IGW, NAT Gateway y tablas de ruteo. |
| `servidor` | Módulo Local (`./modules/servidor`) | Local | Plantilla reutilizable para EC2 + Security Group con bloque `dynamic "ingress"`, IMDSv2 obligatorio y `user_data` parametrizado. Se reutiliza tanto para el WebServer como para los backends. |

### Documentación del Módulo Local (`./modules/servidor`)

* **Inputs requeridos:**
  * `nombre` (`string`): Identificador lógico del recurso y prefijo de Security Group.
  * `ami_id` (`string`): Identificador de la AMI (obtenido dinámicamente vía `data.aws_ami.ubuntu`).
  * `instance_type` (`string`): Tipo de instancia EC2.
  * `vpc_id` (`string`): ID de la VPC en donde se aloja el Security Group.
  * `subnet_id` (`string`): Subred de despliegue de la instancia.
  * `user_data` (`string`): Script bash de inicialización inyectado mediante `templatefile()`.
  * `reglas_ingress` (`list(object)`): Matriz de reglas de entrada procesadas mediante un bloque `dynamic "ingress"`.
* **Outputs expuestos:**
  * `instance_id`: ID físico de la instancia creada en AWS.
  * `private_ip`: Dirección IP privada asignada a la interfaz de red.
  * `security_group_id`: ID del Security Group creado por el módulo (consumido por RDS).

---

## 3. Justificación Técnica: `for_each` vs `count`

Para el despliegue de los servidores backend y el registro en el balanceador se seleccionó **`for_each`** sobre un mapa con claves semánticas (`backend-01`, `backend-02`, `backend-03`) por las siguientes razones de ingeniería:

1. **Estabilidad de Identificadores en el State:** `count` asocia los recursos a un índice posicional numérico (`[0]`, `[1]`, `[2]`). Si una instancia intermedia se destruye o modifica, Terraform reasigna los índices destruyendo y recreando innecesariamente las instancias subsecuentes. `for_each` vincula cada recurso a una clave fija e inmutable (`module.backend["backend-02"]`).
2. **Reemplazo Selectivo (`-replace`):** Permite ejecutar operaciones de mantenimiento y reciclaje granular sobre un nodo específico (`terraform apply -replace='module.backend["backend-02"].aws_instance.this'`) sin afectar el estado ni los attachments de los demás nodos.
3. **Determinismo en Plan:** Las claves del iterador se computan a partir de `var.cantidad_backends`, garantizando que son conocidas desde la fase de planificación estática.

---

## 4. Instrucciones de Ejecución por Entorno

### Configuración de Credenciales
Descargar las credenciales temporales desde la consola del Learner Lab e integrarlas en el archivo estándar `~/.aws/credentials`:
```ini
[default]
aws_access_key_id = ASIASGLA...
aws_secret_access_key = ...
aws_session_token = ...
```

### Inicialización y Validación
```bash
# 1. Inicializar providers y descargar módulos
terraform init

# 2. Formatear y verificar sintaxis
terraform fmt -check
terraform validate
```

### Despliegue en Entorno de Desarrollo (`dev`)
```bash
# Planificar y desplegar
terraform plan -var-file=dev.tfvars -out=plan.tfplan
terraform apply plan.tfplan

# Comprobar idempotencia ("No changes")
terraform plan -var-file=dev.tfvars

# Consultar endpoints y outputs
terraform output
```

### Demostración de Entorno de Producción (`prod`)
```bash
terraform plan -var-file=prod.tfvars
```

### Limpieza de Recursos (Cierre de Laboratorio)
```bash
terraform destroy -var-file=dev.tfvars -auto-approve
```
