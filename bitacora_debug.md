# Bitácora de Debugging – AUY1103

## Incidencia 1 (provocada): `for_each` sobre una lista sin `toset()`
**Error**
```
│ Error: Invalid for_each argument
│   on compute.tf line 3, in resource "aws_security_group" "alb":
│    3:   for_each = ["web", "backend"]
│ The given "for_each" argument value is unsuitable: the "for_each" argument
│ must be a map, or set of strings, and you have provided a value of type tuple.
```
**Herramienta:** `terraform validate`
**Causa raíz:** `for_each` solo acepta `map` o `set(string)`. Una lista (tuple) tiene orden e índices duplicables, así que no entrega claves únicas y estables.
**Corrección en código:**
```hcl
for_each = toset(["web", "backend"])
```

## Incidencia 2: claves de `for_each` desconocidas en el plan
**Error**
```
│ Error: Invalid for_each argument
│ The "for_each" map includes keys derived from resource attributes that cannot
│ be determined until apply, and so Terraform cannot determine the full set of
│ keys that will identify the instances of this resource.
```
**Herramienta:** `terraform plan`
**Causa raíz:** El mapa se construía con `module.vpc.private_subnets` como **clave** (`{ for s in module.vpc.private_subnets : s => ... }`). Los IDs de subred no existen antes del apply.
**Corrección en código:** Las claves pasan a salir de `var.cantidad_backends` y la subred va en el **valor**:
```hcl
subnet_id = module.vpc.private_subnets[each.value % length(module.vpc.private_subnets)]
```

## Incidencia 3: password de RDS rechazada por la API
**Error**
```
│ Error: creating RDS DB Instance (auy1103-dev-mysql): operation error RDS: CreateDBInstance,
│ api error InvalidParameterValue: The parameter MasterUserPassword is not a valid password.
│ Only printable ASCII characters besides '/', '@', '"', ' ' may be used.
```
**Herramienta:** `TF_LOG=DEBUG` con `TF_LOG_PATH="terraform.log"`. En el log aparece el request `CreateDBInstance` y la respuesta HTTP 400. El plan no detecta este error porque el valor se valida en la API de AWS durante el apply.
**Causa raíz:** `random_password` con `special = true` usa por defecto un conjunto de caracteres que incluye `@`, `/` y `"`, y RDS los prohíbe.
**Corrección en código:**
```hcl
resource "random_password" "rds" {
  length           = 20
  special          = true
  override_special = "!#$%^&*()-_=+"
}
```

## Reemplazo forzado con `terraform apply -replace`
Caso: `backend-02` necesita recrearse de forma aislada sin tocar el código ni el resto del clúster.

```bash
terraform apply -var-file=dev.tfvars -replace='module.backend["backend-02"].aws_instance.this'
```
**Lectura del plan:**
```
  # module.backend["backend-02"].aws_instance.this will be replaced, as requested
-/+ resource "aws_instance" "this" {
      ~ id         = "i-0abc..." -> (known after apply)
      ~ private_ip = "10.10.11.25" -> (known after apply)
    }
  # aws_lb_target_group_attachment.backend["backend-02"] must be replaced
-/+ resource "aws_lb_target_group_attachment" "backend" {
      ~ target_id = "i-0abc..." -> (known after apply) # forces replacement
    }
Plan: 2 to add, 0 to change, 2 to destroy.
```
- `-/+`: se destruye la instancia y se crea una nueva.
- El attachment se reemplaza **en cascada** porque `target_id` cambia y ese atributo *forces replacement*.
- `backend-01`, `backend-03`, el SG y el ALB **no cambian** gracias a las claves estables de `for_each`.
