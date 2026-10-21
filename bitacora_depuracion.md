# Bitácora de Depuración (Debugging) – AUY1103

**Asignatura:** AUY1103 – Infraestructura como Código I  
**Evaluación:** Evaluación Parcial N° 2  
**Estudiantes:** Fernando Galdamez y Jose Villaroel (`fer.galdamez@duocuc.cl`)  
**Entorno de ejecución:** AWS Academy Learner Lab (`us-east-1`)  

---

## Incidencia 1 (Provocada): `for_each` sobre un tuple/lista sin `toset()`

* **Error observado:**
  ```text
  Error: Invalid for_each argument
    on compute.tf line 3, in resource "aws_security_group" "alb":
     3:   for_each = ["web", "backend"]
  The given "for_each" argument value is unsuitable: the "for_each" argument
  must be a map, or set of strings, and you have provided a value of type
  tuple.
  ```
* **Herramienta de diagnóstico:**
  `terraform validate` (evidencia almacenada en `evidencias/incidencia1_error_validate.txt`).
* **Causa raíz:**
  En Terraform, la meta-instrucción `for_each` requiere estrictamente una estructura de tipo `map` o `set(string)`. Al proporcionar una lista estática literal entre corchetes `["web", "backend"]`, el motor de tipos de Terraform infiere un tipo `tuple`, el cual no asegura claves únicas no indexadas por posición.
* **Solución aplicada en código:**
  Se aplicó la función de casteo `toset()` en `compute.tf`:
  ```hcl
  resource "aws_security_group" "alb" {
    for_each = toset(["web", "backend"])
    # ...
  }
  ```
  Tras la corrección, `terraform validate` devolvió: `Success! The configuration is valid.`

---

## Incidencia 2: Claves de `for_each` derivadas de atributos desconocidos durante el plan

* **Error observado:**
  ```text
  Error: Invalid for_each argument
    on compute.tf line 65, in module "backend":
    65:   for_each = local.backends
      ├─ local.backends will be known only after apply
  The "for_each" map includes keys derived from resource attributes that cannot
  be determined until apply, and so Terraform cannot determine the full set of
  keys that will identify the instances of this resource.
  ```
* **Herramienta de diagnóstico:**
  `terraform plan` (evidencia almacenada en `evidencias/incidencia2_error_plan.txt`).
* **Causa raíz:**
  El bloque de `backends` en `locals.tf` utilizaba temporalmente el identificador generado por un recurso dinámico (`random_id.sufijo_bucket.hex`) en las claves del mapa iterador. Dado que el valor del identificador solo se computa tras el `apply`, Terraform no puede predecir el grafo de ejecución ni la cantidad e identificación de las instancias a crear.
* **Solución aplicada en código:**
  Se desvincularon las claves de cualquier output de recurso, construyendo las claves del mapa basándose exclusivamente en variables de entrada (`var.cantidad_backends`), de modo que las claves son estáticas y conocidas durante el ciclo de planificación:
  ```hcl
  # locals.tf
  backends = {
    for i in range(var.cantidad_backends) :
    format("backend-%02d", i + 1) => i
  }
  ```

---

## Incidencia 3: Falla de bootstrap en instancias privadas por concurrencia con NAT Gateway

* **Error observado:**
  Al consultar el endpoint DNS de los Balanceadores de Carga (`ALB`), las peticiones HTTP retornaban respuestas `HTTP/1.1 502 Bad Gateway` debido a que los target groups marcaban las instancias EC2 en estado no saludable (*unhealthy*).
  Revisando el registro de inicialización en consola EC2 (`cloud-init`):
  ```text
  [ 165.904683] cloud-init[1067]: E: Unable to fetch some archives, maybe run apt-get update or try with --fix-missing?
  [ 165.907090] cloud-init[1067]: 2026-10-21 21:47:52,134 - cc_scripts_user.py[WARNING]: Failed to run module scripts_user
  ```
* **Herramienta de diagnóstico:**
  `curl -s -i <DNS_ALB>` y lectura de consola de instancia (`GetConsoleOutput` vía API AWS).
* **Causa raíz:**
  Al desplegarse las instancias EC2 en subredes privadas simultáneamente con la creación del NAT Gateway, `cloud-init` inició la ejecución de `apt-get update` antes de que la interfaz del NAT Gateway y las tablas de enrutamiento alcanzaran el estado de propagación total en la VPC de AWS, provocando fallas transitorias de DNS y descarga de paquetes de Nginx y Docker.
* **Solución aplicada en código:**
  Se implementó un bucle de comprobación de conectividad saliente y reintentos en los templates `templates/web_nginx.sh.tftpl` y `templates/backend_docker.sh.tftpl`:
  ```bash
  for i in {1..30}; do
    if curl -s -m 2 https://archive.ubuntu.com > /dev/null 2>&1; then break; fi
    sleep 3
  done

  for i in {1..5}; do
    apt-get update -y && apt-get install -y nginx && break || sleep 5
  done
  ```
  Tras la corrección y recreación, las instancias alcanzaron estado saludable, respondiendo el WebServer con HTTP 200 y los backends Docker con la rotación de nombres de servidor.

---

## Prueba de Reemplazo Forzado (`terraform apply -replace`) – Indicador IE 3.3.2

Se ejecutó la orden de reemplazo declarativo para recrear la instancia `backend-02`:
```bash
terraform apply -var-file=dev.tfvars -replace='module.backend["backend-02"].aws_instance.this' -auto-approve
```

### Evidencia del Plan `-/+` (Destroy and Create Replacement)
```text
Terraform will perform the following actions:

  # aws_lb_target_group_attachment.backend["backend-02"] must be replaced
-/+ resource "aws_lb_target_group_attachment" "backend" {
      ~ id               = "arn:aws:elasticloadbalancing:.../a4c5eb5659f0a72c,i-00eadc04060c86cbb,80" -> (known after apply)
      ~ target_id        = "i-00eadc04060c86cbb" -> (known after apply) # forces replacement
    }

  # module.backend["backend-02"].aws_instance.this will be replaced, as requested
-/+ resource "aws_instance" "this" {
      ~ arn                  = "arn:aws:ec2:us-east-1:151063323597:instance/i-00eadc04060c86cbb" -> (known after apply)
      ~ id                   = "i-00eadc04060c86cbb" -> (known after apply)
      ~ instance_state       = "running" -> (known after apply)
      ~ primary_network_interface_id = "eni-048b6bbbaef74f38c" -> (known after apply)
      ~ private_ip           = "10.10.11.205" -> (known after apply)
      # ...
    }

Plan: 2 to add, 0 to change, 2 to destroy.
```

### Explicación Técnica del Plan `-/+`:
1. **Símbolo `-/+`:** Representa una sustitución destructiva controlada (*replace*). Terraform primero destruye la instancia existente y aprovisiona una nueva para preservar la inmutabilidad de la infraestructura.
2. **Reemplazo en cascada:** La recreación de la instancia `module.backend["backend-02"].aws_instance.this` genera un nuevo `target_id`. En el recurso de asociación `aws_lb_target_group_attachment`, cualquier variación del atributo `target_id` es no modificable en caliente (*forces replacement*), lo que obliga a Terraform a actualizar de forma atómica el registro en el Target Group del ALB sin interrumpir a los otros backends (`backend-01` y `backend-03`).
