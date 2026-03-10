# Runbook: High CPU

## Тригер
`HostHighCPU` (>90% протягом 5 хв)

## Дії
1. Перевірити dashboard Host Overview: CPU, load average, top process/container.
2. Перевірити чи це short spike чи стабільний saturation.
3. Якщо джерело у контейнері: перевірити логи і рестарти сервісу.
4. Якщо вузьке місце в host: обмежити фонoві задачі, перевести важкі jobs поза пік.
5. Якщо тримається >15 хв: ескалація в on-call.

## Перевірка відновлення
- CPU стабільно <80% 10+ хв
- Alert auto-resolved
