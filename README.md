# Diagnost

Репозиторий для диагностики и настройки VPN нод RemnaWave.

## Быстрый запуск

Общий шаблон команды:
```bash
curl -sL https://raw.githubusercontent.com/Ravil346/repoforanal/main/СКРИПТ.sh | sudo bash
```

---

## Скрипты и команды

### 1. Диагностика ноды

Собирает информацию о системе, сети, Docker, Xray конфиге.

```bash
curl -sL https://raw.githubusercontent.com/Ravil346/repoforanal/main/node_diagnostic.sh | sudo bash 2>&1 | tee /tmp/diag.txt
```

После выполнения скопируй вывод:
```bash
cat /tmp/diag.txt
```

---

### 2. Оптимизация VPS

Настраивает BBR, TCP буферы, sysctl параметры, swap.

**Опции:**
| Опция | Описание |
|-------|----------|
| `--check` | Только проверить текущее состояние |
| `--bbr` | Включить BBR congestion control |
| `--sysctl` | Оптимизировать сетевые параметры ядра |
| `--swap` | Создать swap файл (2GB) |
| `--all` | Применить все оптимизации |

**Команды:**

```bash
# Только проверка (ничего не меняет)
curl -sL https://raw.githubusercontent.com/Ravil346/repoforanal/main/vps-optimization.sh | sudo bash -s -- --check

# Включить BBR
curl -sL https://raw.githubusercontent.com/Ravil346/repoforanal/main/vps-optimization.sh | sudo bash -s -- --bbr

# BBR + sysctl (без swap)
curl -sL https://raw.githubusercontent.com/Ravil346/repoforanal/main/vps-optimization.sh | sudo bash -s -- --bbr --sysctl

# Все оптимизации сразу
curl -sL https://raw.githubusercontent.com/Ravil346/repoforanal/main/vps-optimization.sh | sudo bash -s -- --all
```

---

### 3. Настройка безопасности ноды (стандартная)

Для всех нод с портом **443**.

**Что делает:**
- SSH порт: 22 → **41022**
- NODE_PORT: 2222 → **47891** (только для IP панели)
- VPN порт: **443** открыт для всех
- Всё остальное: закрыто (UFW)

```bash
curl -sL https://raw.githubusercontent.com/Ravil346/repoforanal/main/setup_node_security.sh | sudo bash
```

**Ноды:** Германия 2, Нидерланды, США, США 2, Белые списки, Индия, Россия, Южная Корея

---

### 4. Настройка безопасности Германии (xhttp)

Для ноды **de.meerguard.net** с портами **443 + 8443**.

**Что делает:**
- SSH порт: 22 → **41022**
- NODE_PORT: 2222 → **47891** (только для IP панели)
- VPN порты: **443** и **8443** открыты для всех
- Всё остальное: закрыто (UFW)

```bash
curl -sL https://raw.githubusercontent.com/Ravil346/repoforanal/main/setup_germany_node.sh | sudo bash
```

**Нода:** Германия (de.meerguard.net)

---

## После настройки безопасности

### 1. Проверь SSH на новом порту

```bash
ssh -p 41022 root@IP_СЕРВЕРА
```

### 2. Удали старый SSH порт

```bash
ufw delete allow 22/tcp
```

### 3. В панели RemnaWave измени порт ноды на 47891

---

## Откат изменений

### Отключить файрволл
```bash
ufw disable
```

### Восстановить SSH
```bash
cp /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
systemctl restart sshd
```

### Восстановить .env ноды
```bash
ls -la /opt/remnanode/.env.backup.*
cp /opt/remnanode/.env.backup.ДАТА /opt/remnanode/.env
cd /opt/remnanode && docker compose down && docker compose up -d
```

---

## Конфигурация

| Параметр | Значение |
|----------|----------|
| IP панели | 91.208.184.247 |
| SSH порт | 41022 |
| NODE_PORT | 47891 |