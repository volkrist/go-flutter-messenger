# Бэкап PostgreSQL

## Что есть в репозитории

- **infra/backup-postgres.sh** — скрипт: делает `pg_dump` из контейнера, сохраняет в `backups/`, удаляет дампы старше 7 дней.

## Настройка на сервере (один раз)

Подключись как **alex** и выполни по шагам.

### 1. Папка для бэкапов

```bash
mkdir -p /opt/go-flutter-messenger/backups
```

### 2. Скопировать скрипт с ПК (или создать вручную)

С ПК (из папки проекта):

```powershell
scp infra/backup-postgres.sh alex@89.167.112.246:/opt/go-flutter-messenger/
```

На сервере исправить переводы строк (если скрипт с Windows):

```bash
sed -i 's/\r$//' /opt/go-flutter-messenger/backup-postgres.sh
chmod +x /opt/go-flutter-messenger/backup-postgres.sh
```

### 3. Проверка вручную

```bash
/opt/go-flutter-messenger/backup-postgres.sh
ls -lh /opt/go-flutter-messenger/backups
```

Должен появиться файл вида `postgres_2026-03-15_00-40-10.sql`.

### 4. Cron — ежедневно в 03:00

```bash
crontab -e
```

Добавь строку (один раз):

```
0 3 * * * /opt/go-flutter-messenger/backup-postgres.sh >> /opt/go-flutter-messenger/backups/backup.log 2>&1
```

Сохрани и выйди из редактора.

## Итог

- Бэкап каждый день в 03:00.
- В каталоге `backups/` хранятся дампы за последние 7 дней.
- Лог запусков: `backups/backup.log`.

Скрипт подхватывает `POSTGRES_DB` и `POSTGRES_USER` из `/opt/go-flutter-messenger/.env`, если файл есть (как в docker-compose).
