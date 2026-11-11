# Informe Técnico Evaluación Parcial N° 3 (AUY1103)
## Parametrización Multi-Ambiente, Funciones Built-in, Expresiones Condicionales y Persistencia en AWS con Terraform

- **Integrantes:** Fernando Galdamez | Jose Villaroel (`fer.galdamez@duocuc.cl`)
- **Asignatura:** AUY1103 – Infraestructura como Código I
- **Institución:** Duoc UC – Escuela de Informática y Telecomunicaciones
- **Cuenta AWS Academy Learner Lab:** `1510-6332-3597` (`voclabs/user4133678=fer.galdamez@duocuc.cl`)
- **Región:** `us-east-1` (N. Virginia)

---

## 1. Resumen Ejecutivo y Arquitectura Multi-Ambiente

El proyecto evoluciona la plataforma corporativa desplegada en la Evaluación Parcial 2 hacia una solución 100% declarativa y parametrizada para operar en tres ambientes (**`dev`**, **`qa`** y **`prod`**) a partir de un único código fuente de Terraform (`>= 1.9.0`, provider `hashicorp/aws ~> 6.0`).

Todos los nombres de recursos, etiquetas obligatorias (`Environment`, `Owner`, `Project`, `Asignatura`), cantidad de contenedores backend Docker, tipos de instancia (`t3.micro` vs `t3.small`), topología de red (2 o 3 Zonas de Disponibilidad), NAT Gateway, reglas administrativas SSH (puerto 22 restringido a `dev`) y políticas de respaldo/protección en Amazon RDS MySQL 8.0 se derivan dinámicamente mediante **funciones built-in** y **expresiones condicionales** en `locals.tf`.

---

## 2. Tabla de Funciones Built-in Utilizadas

| Categoría | Función | Archivo | Línea | Propósito Técnico en el Proyecto |
| :--- | :--- | :--- | :---: | :--- |
| **Cadenas** | `lower()` | `locals.tf` | 6 | Normaliza el prefijo general a minúsculas (`duoc-plataforma-dev`). |
| **Cadenas** | `upper()` | `locals.tf` | 14 | Convierte el ambiente a mayúsculas (`DEV`, `QA`, `PROD`) para etiquetas y sitio estático. |
| **Cadenas** | `title()` | `locals.tf` | 15, 16 | Capitaliza los nombres de los integrantes (`Fernando Galdamez, Jose Villaroel`) y del proyecto (`Plataforma`). |
| **Cadenas** | `trimspace()` | `locals.tf` | 6, 15 | Elimina espacios accidentales al inicio o final de las variables de entrada. |
| **Cadenas** | `replace()` | `locals.tf` | 6 | Reemplaza espacios internos por guiones en nombres de empresa y proyecto. |
| **Cadenas** | `substr()` | `locals.tf` | 9 | Trunca el prefijo a un máximo de 32 caracteres para nombres de ALB y Target Groups. |
| **Cadenas** | `format()` | `locals.tf` | 6, 61 | Construye el prefijo (`"%s-%s-%s"`) y las claves estáticas del mapa de backends (`"backend-%02d"`). |
| **Cadenas** | `join()` | `locals.tf` | 15 | Concatena la lista de integrantes capitalizados separados por coma. |
| **Cadenas** | `chomp()` | `locals.tf` | 73 | Limpia saltos de línea del cuerpo devuelto por `data.http.mi_ip`. |
| **Colecciones** | `merge()` | `locals.tf` | 12 | Combina `local.tags_comunes` con las etiquetas particulares de cada recurso. |
| **Colecciones** | `lookup()` | `locals.tf` | 51, 54-56 | Obtiene los parámetros del mapa `local.config` por ambiente con valor por defecto. |
| **Colecciones** | `slice()` | `locals.tf` | 65 | Selecciona 2 o 3 zonas de disponibilidad desde `data.aws_availability_zones.available.names`. |
| **Colecciones** | `length()` | `locals.tf` | 68-70, 105 | Calcula dinámicamente el número de zonas, subredes y recursos condicionales. |
| **Colecciones** | `range()` | `locals.tf` | 60, 68-70 | Genera secuencias numéricas para iterar subredes y backends Docker. |
| **Colecciones** | `keys()` | `locals.tf` | 99 | Lista las claves de ambientes disponibles en `local.config`. |
| **Colecciones** | `values()` | `locals.tf` | 100 | Extrae los objetos de configuración de todos los ambientes. |
| **Colecciones** | `flatten()` | `locals.tf` | 101 | Aplana las listas de subredes públicas, privadas y de datos en un solo vector. |
| **Colecciones** | `distinct()` | `locals.tf` | 101 | Garantiza que no existan bloques CIDR duplicados en la lista consolidada de subredes. |
| **Colecciones** | `contains()` | `locals.tf` | 95 | Filtra reglas de seguridad según si `var.environment` pertenece a `r.ambientes`. |
| **Colecciones** | `toset()` | `main.tf` | 31 | Convierte `["web", "api"]` en conjunto tipado para iterar con `for_each`. |
| **Colecciones** | `try()` / `coalesce()` | `locals.tf` | 73 | Resuelve de forma resiliente la IP pública del estudiante con fallback seguro. |
| **Red** | `cidrsubnet()` | `locals.tf` | 68-70 | Deriva subredes `/24` públicas, privadas y de datos desde el bloque `var.vpc_cidr` (`/16`). |
| **Red** | `cidrhost()` / `cidrnetmask()` | `variables.tf` | 42 | Valida estáticamente que `var.vpc_cidr` sea un bloque IPv4 CIDR bien formado. |
| **Codificación** | `templatefile()` | `main.tf` | 75, 106 | Renderiza los scripts `web_nginx.sh.tftpl` y `backend_docker.sh.tftpl` para `user_data`. |
| **Codificación** | `jsonencode()` | `locals.tf` | 102 | Codifica en JSON el resumen de metadata de despliegue expuesto en `outputs.tf`. |
| **Validación** | `can()` / `regex()` | `variables.tf` | 16, 26, 42 | Evalúa restricciones de formato (`^[a-z0-9-]+$`) y validez de CIDR en bloques `validation`. |
| **Conversión** | `tonumber()` / `tostring()` | `variables.tf` | 52 | Convierte tipos escalares para validaciones numéricas y serialización JSON. |

---

## 3. Matriz de Condiciones y Comparativa de Planes (`dev`, `qa`, `prod`)

| Parámetro / Recurso | `dev` (`plan_dev.txt`) | `qa` (`plan_qa.txt`) | `prod` (`plan_prod.txt`) | Técnica Implementada |
| :--- | :---: | :---: | :---: | :--- |
| **VPC CIDR** | `10.10.0.0/16` | `10.20.0.0/16` | `10.30.0.0/16` | Variable `var.vpc_cidr` por `.tfvars` |
| **Zonas de Disponibilidad** | 2 (`us-east-1a`, `1b`) | 2 (`us-east-1a`, `1b`) | 3 (`us-east-1a`, `1b`, `1c`) | `slice(data.aws_availability_zones.available.names, 0, var.cantidad_zonas)` |
| **Subredes Totales** | 6 subredes `/24` | 6 subredes `/24` | 9 subredes `/24` | Expresiones `for` + `cidrsubnet()` |
| **NAT Gateway** | Deshabilitado (`0`) | Deshabilitado (`0`) | Habilitado (`1` Single NAT) | `enable_nat_gateway = local.es_prod` |
| **Backends Docker** | 2 instancias | 3 instancias | 4 instancias | `lookup(local.env_config, "backends_count", 2)` |
| **Tipo de Instancia EC2** | `t3.micro` | `t3.micro` | `t3.small` | `lookup(local.env_config, "instance_type", "t3.micro")` + `precondition` |
| **Regla SSH (Puerto 22)** | Sí (IP del estudiante) | No | No | `dynamic "ingress"` con `for ... if contains(r.ambientes, var.environment)` |
| **SG Monitoreo (`count`)** | Sí (`count = 1`) | Sí (`count = 1`) | No (`count = 0`) | `count = !local.es_prod ? 1 : 0` |
| **RDS Multi-AZ** | `false` | `false` | `true` | `local.es_prod ? true : false` |
| **RDS Retención Backups** | 1 día | 3 días | 7 días | `lookup(local.env_config, "rds_retention_days", 1)` |
| **RDS Deletion Protection** | `false` | `false` | `true` | `local.es_prod ? true : false` |
| **RDS Snapshot Final** | Según `conservar_datos` | Sí (`duoc-plataforma-qa-final-snapshot`) | Sí (`duoc-plataforma-prod-final-snapshot`) | `skip_final_snapshot = !(local.es_prod \|\| var.environment == "qa" \|\| var.conservar_datos)` |
| **Total Recursos en Plan** | **37 recursos a crear** | **39 recursos a crear** | **49 recursos a crear** | Verificado con `terraform plan -no-color` |

---

## 4. Evidencias Reales Capturadas en Navegador y AWS CloudShell

### 4.1. Sitio Estático Nginx (`ALB Web`)
Respuesta HTTP 200 en el navegador sobre `http://duoc-plataforma-dev-web-1638812590.us-east-1.elb.amazonaws.com` mostrando el ambiente en mayúsculas (`DEV`) y el nombre del alumno con `title()` (`Fernando Galdamez, Jose Villaroel`):

![Captura ALB Web](./captura_alb_web.png)

### 4.2. Balanceo de Carga entre Contenedores Docker (`ALB Backend API`)
Respuesta en el navegador sobre `http://duoc-plataforma-dev-api-873114828.us-east-1.elb.amazonaws.com` rotando entre `web-backend-01` y `web-backend-02`:

![Captura ALB Backend 01](./captura_alb_backend_01.png)

![Captura ALB Backend 02](./captura_alb_backend_02.png)

### 4.3. Verificación desde AWS CloudShell (`us-east-1`)
Ejecución en vivo dentro de AWS CloudShell (`voclabs/user4133678=fer.galdamez@duocuc.cl`, cuenta `1510-6332-3597`) comprobando las 3 instancias EC2 en estado `running`, los 2 Application Load Balancers en estado `active` y la instancia RDS MySQL 8.0 en estado `available`:

![Captura AWS CloudShell Recursos](./captura_aws_cloudshell_recursos.png)

### 4.4. Consola de Amazon EC2 y Amazon RDS (Base de Datos e Instantánea)
Vista real de las instancias en la consola de EC2, la instancia `duoc-plataforma-dev-mysql` disponible en RDS y el snapshot `duoc-plataforma-dev-final-snapshot`:

![Captura Consola EC2](./captura_ec2_consola.png)

![Captura Consola RDS](./captura_rds_consola.png)

![Captura Snapshot RDS](./captura_rds_snapshot_consola.png)

---

## 5. Resumen de Bitácora de Depuración (3 Incidencias Reales)

| Incidencia | Archivo Evidencia | Herramienta | Error Capturado | Causa Raíz y Solución |
| :--- | :--- | :--- | :--- | :--- |
| **Incidencia 1** | `error_1.txt` | `terraform plan` | `Invalid key: the given map does not contain an element with the key "zona_horaria" and no default value was specified.` | Se invocó `lookup()` con 2 argumentos sobre una clave inexistente. Se corrigió añadiendo el tercer argumento por defecto en todos los `lookup()`. |
| **Incidencia 2** | `error_2.txt` | `terraform plan` | `Invalid prefix length: prefix length 16 plus 20 is 36, which is greater than the 32 bits available for IPv4.` | `cidrsubnet(var.vpc_cidr, 20, 1)` excede los 32 bits de IPv4. Se corrigió utilizando `newbits = 8` para obtener subredes `/24`. |
| **Incidencia 3** | `error_3.txt` | `terraform validate` | `A single static boolean value is required (true or false). Dynamic expressions and variable references are not permitted in lifecycle configuration blocks.` | `lifecycle { prevent_destroy }` se evalúa en el AST antes de interpolar variables. Se reemplazó por `deletion_protection = local.es_prod ? true : false` en RDS. |
