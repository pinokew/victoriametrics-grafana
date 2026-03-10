# Runbook: Disk Space Low

## Тригери
- `HostDiskWarning` (<20% протягом 5 хв)
- `HostDiskLow` (<10% протягом 5 хв)

## Дії
1. Визначити mountpoint із найменшим free space.
2. Перевірити зростання `.data/`, Docker volumes, logs, backups.
3. Прибрати безпечні тимчасові файли/старі артефакти.
4. Для `HostDiskLow`: пріоритетно захистити `assetstore`/DB диски від переповнення.
5. Запланувати розширення диска або cleanup policy.

## Перевірка відновлення
- Free space >25%
- Тренд росту стабілізований
