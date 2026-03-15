# Як оновлювати дашборди (Config-as-Code)

## Правило
Зміна dashboard виконується тільки через файли в Git. Редагування тільки в UI заборонене для production workflow.

## Базовий процес
1. Взяти base dashboard з Grafana.com (`api/dashboards/<id>/revisions/latest/download`).
2. Зберегти у `grafana/dashboards/` з інформативною назвою файлу.
3. Адаптувати JSON перед комітом:
   - datasource на `uid: victoriametrics`
   - прибрати `__inputs` і `gnetId`
   - встановити стабільний `uid` (наприклад `kdi-...`)
   - перевірити, що немає placeholder-значень `${...}`
4. Оновити `docs/dashboards/dashboard-catalog.md`.
5. Перезапустити Grafana: `docker compose restart grafana`.
6. Перевірити появу dashboard у папці `KDI-P0`.

## Локальна перевірка перед commit
```bash
docker compose config --quiet
grep -Rno '\${[^}]*}' grafana/dashboards/*.json || true
```

## Rollback
- `git revert <commit>`
- `docker compose restart grafana`

## Типові проблеми
- Dashboard не з'явився: перевірити `grafana/provisioning/dashboards/dashboards.yml` і шлях `/var/lib/grafana/dashboards`.
- Панелі порожні: перевірити datasource `VictoriaMetrics` і статус targets у `http://127.0.0.1:8428/targets`.
- Помилка JSON: перевірити синтаксис файлу та унікальність `uid`.
