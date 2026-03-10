# Runbook: High Memory

## Тригер
`HostHighMemory` (>95% протягом 5 хв)

## Дії
1. Перевірити memory usage per container/process.
2. Перевірити swap activity та OOM події в системних логах.
3. Якщо є memory leak у конкретному сервісі: restart сервісу з фіксацією інциденту.
4. Перевірити ліміти контейнерів і workloads, що зросли після останніх deploy.

## Перевірка відновлення
- RAM стабільно <85%
- Немає нових OOM
