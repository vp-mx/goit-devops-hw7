# modules/rds

Гнучкий Terraform-модуль для баз даних на AWS. Одним прапорцем `use_aurora`
перемикає, що саме створюється:

- `use_aurora = false` (за замовчуванням) — звичайний `aws_db_instance` (`rds.tf`).
- `use_aurora = true` — Aurora Cluster: `aws_rds_cluster` + N `aws_rds_cluster_instance` (`aurora.tf`).

Спільні для обох варіантів ресурси — DB Subnet Group, Security Group і
Parameter Group з базовими параметрами (`max_connections`, `log_statement`,
`work_mem`) — лежать в `shared.tf`. Всі output-и (`endpoint`, `port`, `arn`,
...) резолвяться в правильний ресурс автоматично, тож код виклику модуля
не залежить від `use_aurora` — міняється лише сама змінна.

## Структура

```
modules/rds/
├── rds.tf         # aws_db_instance (use_aurora = false)
├── aurora.tf       # aws_rds_cluster + aws_rds_cluster_instance (use_aurora = true)
├── shared.tf       # DB Subnet Group, Security Group, Parameter Group(s), master password
├── variables.tf
├── outputs.tf
└── README.md
```

## Приклад використання

Стандартна RDS-інстанція (наприклад, Postgres для Django-застосунку з теми 4,
у тій самій VPC, що й EKS-кластер з цього репозиторію):

```hcl
module "rds" {
  source = "./modules/rds"

  identifier = "${var.project}-db"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  # Дозволити доступ лише з нод EKS-кластера
  allowed_security_group_ids = [module.eks.node_security_group_id]

  use_aurora      = false
  engine          = "postgres"
  engine_version  = "16.4"
  family          = "postgres16"
  instance_class  = "db.t3.micro"
  multi_az        = false

  database_name   = "django_db"
  master_username = "django_admin"
  # master_password не передано -- модуль сам згенерує та збереже у state

  tags = {
    Project = var.project
  }
}

output "db_endpoint" {
  value = module.rds.endpoint
}
```

Той самий виклик, перемкнутий на Aurora (Multi-AZ через кількість інстансів
замість `multi_az`):

```hcl
module "rds" {
  source = "./modules/rds"

  identifier = "${var.project}-db"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  allowed_security_group_ids = [module.eks.node_security_group_id]

  use_aurora            = true
  engine                = "aurora-postgresql"
  engine_version        = "16.4"
  family                = "aurora-postgresql16"
  instance_class        = "db.t3.medium" # Aurora не має Free Tier, t3.micro тут не підтримується
  aurora_instance_count = 2              # 1 writer + 1 reader, у різних AZ

  database_name   = "django_db"
  master_username = "django_admin"
}
```

## Як змінити тип БД / engine / instance class

| Що змінити | Як |
|---|---|
| Standard RDS ↔ Aurora | змінити лише `use_aurora` (`false`/`true`) і переприкласти `terraform apply` — решта коду виклику модуля не міняється |
| Engine (Postgres → MySQL і т.д.) | `engine` (`"postgres"`/`"mysql"`/`"mariadb"`, або `"aurora-postgresql"`/`"aurora-mysql"` при `use_aurora = true`) + відповідний `engine_version` і `family` (parameter group family має відповідати engine+engine_version) |
| Версія engine-у | `engine_version`. Дізнатись доступні версії: `aws rds describe-db-engine-versions --engine postgres --query "DBEngineVersions[].EngineVersion"` |
| Parameter group family | `family`, має відповідати engine+engine_version: `aws rds describe-db-engine-versions --engine postgres --engine-version 16.4 --query "DBEngineVersions[].DBParameterGroupFamily"` |
| Розмір інстансу | `instance_class` (напр. `"db.t3.micro"` → `"db.t3.medium"` → `"db.r6g.large"`) |
| Multi-AZ (standard RDS) | `multi_az = true` — піднімає синхронний standby у другій AZ |
| Кількість інстансів Aurora | `aurora_instance_count` (1 writer + N-1 readers, ігнорується для standard RDS) |
| Розмір диска (standard RDS) | `allocated_storage` (GiB), `max_allocated_storage` для автоскейлінгу (0 = вимкнено). Ігнорується для Aurora — сховище там масштабується автоматично |
| Базові параметри БД | `max_connections`, `log_statement`, `work_mem` — застосовуються до обох варіантів через спільну Parameter Group. Додаткові параметри — через `extra_parameters` |
| Мережевий доступ | `allowed_security_group_ids` (рекомендовано — SG нод EKS-кластера) і/або `allowed_cidr_blocks` |

## Змінні

| Змінна | Тип | За замовчуванням | Опис |
|---|---|---|---|
| `identifier` | `string` | — (обов'язкова) | Префікс імені для всіх ресурсів модуля |
| `vpc_id` | `string` | — (обов'язкова) | VPC для Security Group бази |
| `subnet_ids` | `list(string)` | — (обов'язкова) | Підмережі для DB Subnet Group, мінімум 2 в різних AZ |
| `allowed_security_group_ids` | `list(string)` | `[]` | SG, яким дозволено підключення до бази |
| `allowed_cidr_blocks` | `list(string)` | `[]` | CIDR-блоки, яким дозволено підключення до бази |
| `publicly_accessible` | `bool` | `false` | Публічна IP-адреса (лишати `false`, окрім локальних експериментів) |
| `use_aurora` | `bool` | `false` | `true` = Aurora Cluster, `false` = звичайна RDS-інстанція |
| `engine` | `string` | `"postgres"` | Engine БД |
| `engine_version` | `string` | `null` (поточний дефолт AWS) | Версія engine-у |
| `family` | `string` | — (обов'язкова) | Parameter group family, має відповідати engine/engine_version |
| `instance_class` | `string` | `"db.t3.micro"` | Клас інстансу(ів) |
| `multi_az` | `bool` | `false` | Standard RDS: синхронний standby у іншій AZ. Ігнорується для Aurora |
| `allocated_storage` | `number` | `20` | Розмір диска в GiB (лише standard RDS) |
| `max_allocated_storage` | `number` | `0` (вимкнено) | Верхня межа автоскейлінгу диска в GiB (лише standard RDS) |
| `storage_type` | `string` | `"gp3"` | Тип диска (лише standard RDS) |
| `aurora_instance_count` | `number` | `1` | Кількість інстансів у Aurora-кластері (лише Aurora) |
| `database_name` | `string` | — (обов'язкова) | Ім'я бази даних, яка створюється всередині |
| `port` | `number` | `null` (5432/3306 залежно від engine) | Порт БД |
| `master_username` | `string` | `"dbadmin"` | Ім'я адміністратора |
| `master_password` | `string`, sensitive | `null` (генерується модулем) | Пароль адміністратора. `null` -- модуль сам згенерує через `random_password` і збереже у state |
| `max_connections` | `string` | `"100"` | Базовий параметр parameter group |
| `log_statement` | `string` | `"ddl"` | Базовий параметр parameter group |
| `work_mem` | `string` | `"4096"` | Базовий параметр parameter group (KB) |
| `extra_parameters` | `list(object({name=string, value=string}))` | `[]` | Додаткові параметри parameter group |
| `backup_retention_period` | `number` | `7` | Днів зберігання автоматичних бекапів |
| `deletion_protection` | `bool` | `false` | Захист від випадкового видалення |
| `skip_final_snapshot` | `bool` | `true` | Пропустити фінальний снапшот при видаленні (зручно для навчальних середовищ) |
| `tags` | `map(string)` | `{}` | Додаткові теги для всіх ресурсів модуля |

## Виводи (outputs)

`endpoint`, `reader_endpoint` (лише Aurora, інакше `null`), `address`, `port`,
`database_name`, `master_username`, `master_password` (sensitive), `arn`,
`identifier`, `security_group_id`, `db_subnet_group_name`,
`parameter_group_name`.

## Примітки з управління вартістю

- `db.t3.micro`/`db.t4g.micro` + `multi_az = false` — єдина комбінація в межах
  AWS Free Tier для standard RDS. Aurora Free Tier не має.
- `skip_final_snapshot = true` (дефолт) — щоб `terraform destroy` не лишав
  платний снапшот після навчального завдання. Перед реальним використанням
  поставте `false`.
- Не забувайте `terraform destroy` після завершення роботи з модулем, якщо
  це навчальне/тестове середовище.
