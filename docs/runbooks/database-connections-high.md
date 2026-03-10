# Runbook: Database Connections High

## Тригери
- `MariaDBConnectionsHigh`
- `PostgreSQLConnectionsHigh`

## Дії
1. Перевірити поточний utilization (%) і active sessions по БД.
2. Виявити джерело burst: application pool, background job, stuck sessions.
3. Для Koha/DSpace перевірити останні deploy або зміни connection pool.
4. Якщо є завислі сесії: акуратно завершити довгі/idle транзакції за процедурою команди.
5. Якщо ризик вичерпання max_connections: тимчасово знизити навантаження на app.

## Перевірка відновлення
- Utilization стабільно <70%
- Alert cleared і немає повтору протягом 30 хв
