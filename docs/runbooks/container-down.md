# Runbook: Container Down

## Тригери
- `ContainerDown`
- `ContainerHighRestarts`

## Дії
1. Перевірити `docker compose ps` і `docker compose logs <service> --tail=200`.
2. Перевірити причину: crash-loop, dependency down, помилка конфігурації.
3. Якщо root-cause у останньому деплої: виконати rollback.
4. Якщо залежність недоступна (DB/мережа): відновити залежність і перевірити reconnect.

## Перевірка відновлення
- Контейнер `Up` без restart-loop
- `ContainerDown` cleared, restart rate нормалізувався
