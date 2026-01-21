#!/bin/bash

# =============================================================================
# Диагностический скрипт для VPN нод (RemnaWave/Xray)
# Ubuntu 24.04
# =============================================================================

set -e

# Цвета для вывода (отключаем для чистого копирования)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Флаг для чистого вывода (без цветов)
CLEAN_OUTPUT=${1:-""}

if [[ "$CLEAN_OUTPUT" == "--clean" ]]; then
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    NC=""
fi

echo "============================================================================="
echo "           ДИАГНОСТИКА VPN НОДЫ - $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================================="
echo ""

# -----------------------------------------------------------------------------
# Функция установки пакетов
# -----------------------------------------------------------------------------
install_if_missing() {
    local cmd=$1
    local pkg=${2:-$1}
    
    if ! command -v "$cmd" &> /dev/null; then
        echo "[!] $cmd не найден, устанавливаю $pkg..."
        apt-get update -qq > /dev/null 2>&1
        apt-get install -y -qq "$pkg" > /dev/null 2>&1
        echo "[+] $pkg установлен"
    fi
}

# -----------------------------------------------------------------------------
# Проверка root
# -----------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
   echo "Этот скрипт нужно запускать с правами root (sudo)"
   exit 1
fi

# -----------------------------------------------------------------------------
# Установка необходимых утилит
# -----------------------------------------------------------------------------
echo ">>> Проверка и установка необходимых утилит..."
install_if_missing "curl" "curl"
install_if_missing "jq" "jq"
install_if_missing "ss" "iproute2"
install_if_missing "dig" "dnsutils"
install_if_missing "bc" "bc"
echo ""

# =============================================================================
# 1. БАЗОВАЯ ИНФОРМАЦИЯ О СИСТЕМЕ
# =============================================================================
echo "============================================================================="
echo "1. СИСТЕМА"
echo "============================================================================="

echo "Hostname: $(hostname)"
echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
echo "Kernel: $(uname -r)"
echo "Architecture: $(uname -m)"
echo "Uptime: $(uptime -p)"
echo "Boot time: $(who -b | awk '{print $3, $4}')"
echo ""

# =============================================================================
# 2. РЕСУРСЫ (CPU, RAM, DISK)
# =============================================================================
echo "============================================================================="
echo "2. РЕСУРСЫ"
echo "============================================================================="

echo "--- CPU ---"
echo "Cores: $(nproc)"
echo "Model: $(grep 'model name' /proc/cpuinfo | head -1 | cut -d':' -f2 | xargs)"
echo "Current load: $(cat /proc/loadavg | awk '{print $1, $2, $3}')"
echo ""

echo "--- RAM ---"
free -h | grep -E "^Mem|^Swap"
echo ""

echo "--- Disk ---"
df -h / | tail -1 | awk '{print "Root: " $2 " total, " $3 " used, " $4 " free (" $5 " used)"}'
echo ""

# =============================================================================
# 3. СЕТЕВАЯ ИНФОРМАЦИЯ
# =============================================================================
echo "============================================================================="
echo "3. СЕТЬ"
echo "============================================================================="

echo "--- IP информация ---"
# Внешний IP
EXTERNAL_IP=$(curl -s --connect-timeout 5 https://ipinfo.io/ip 2>/dev/null || echo "не удалось получить")
echo "External IP: $EXTERNAL_IP"

# Геолокация
if [[ "$EXTERNAL_IP" != "не удалось получить" ]]; then
    GEO_INFO=$(curl -s --connect-timeout 5 "https://ipinfo.io/$EXTERNAL_IP/json" 2>/dev/null)
    if [[ -n "$GEO_INFO" ]]; then
        echo "Location: $(echo $GEO_INFO | jq -r '.city // "N/A"'), $(echo $GEO_INFO | jq -r '.region // "N/A"'), $(echo $GEO_INFO | jq -r '.country // "N/A"')"
        echo "Provider: $(echo $GEO_INFO | jq -r '.org // "N/A"')"
        echo "ASN: $(echo $GEO_INFO | jq -r '.asn.asn // .org // "N/A"')"
    fi
fi
echo ""

echo "--- Сетевые интерфейсы ---"
ip -4 addr show | grep -E "^[0-9]|inet " | grep -v "127.0.0.1"
echo ""

echo "--- Активные соединения ---"
ss -s
echo ""

echo "--- Порты в LISTEN ---"
ss -tulpn | grep LISTEN | head -20
echo ""

# =============================================================================
# 4. BBR И СЕТЕВЫЕ НАСТРОЙКИ (КРИТИЧНО!)
# =============================================================================
echo "============================================================================="
echo "4. BBR И СЕТЕВЫЕ НАСТРОЙКИ ЯДРА"
echo "============================================================================="

echo "--- TCP Congestion Control ---"
CURRENT_CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "не задан")
AVAILABLE_CC=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo "не доступно")
echo "Текущий алгоритм: $CURRENT_CC"
echo "Доступные алгоритмы: $AVAILABLE_CC"

# Проверка загружен ли модуль BBR
if lsmod | grep -q tcp_bbr; then
    echo "Модуль tcp_bbr: ЗАГРУЖЕН"
else
    echo "Модуль tcp_bbr: НЕ ЗАГРУЖЕН"
fi
echo ""

echo "--- Ключевые сетевые параметры ---"
echo "net.core.default_qdisc = $(sysctl -n net.core.default_qdisc 2>/dev/null || echo 'не задан')"
echo "net.ipv4.tcp_fastopen = $(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null || echo 'не задан')"
echo "net.ipv4.ip_forward = $(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo 'не задан')"
echo "net.ipv4.tcp_ecn = $(sysctl -n net.ipv4.tcp_ecn 2>/dev/null || echo 'не задан')"
echo ""

echo "--- Буферы TCP ---"
echo "net.core.rmem_max = $(sysctl -n net.core.rmem_max 2>/dev/null || echo 'не задан')"
echo "net.core.wmem_max = $(sysctl -n net.core.wmem_max 2>/dev/null || echo 'не задан')"
echo "net.core.rmem_default = $(sysctl -n net.core.rmem_default 2>/dev/null || echo 'не задан')"
echo "net.core.wmem_default = $(sysctl -n net.core.wmem_default 2>/dev/null || echo 'не задан')"
echo "net.ipv4.tcp_rmem = $(sysctl -n net.ipv4.tcp_rmem 2>/dev/null || echo 'не задан')"
echo "net.ipv4.tcp_wmem = $(sysctl -n net.ipv4.tcp_wmem 2>/dev/null || echo 'не задан')"
echo "net.core.netdev_max_backlog = $(sysctl -n net.core.netdev_max_backlog 2>/dev/null || echo 'не задан')"
echo "net.core.somaxconn = $(sysctl -n net.core.somaxconn 2>/dev/null || echo 'не задан')"
echo ""

echo "--- Дополнительные параметры TCP ---"
echo "net.ipv4.tcp_max_syn_backlog = $(sysctl -n net.ipv4.tcp_max_syn_backlog 2>/dev/null || echo 'не задан')"
echo "net.ipv4.tcp_tw_reuse = $(sysctl -n net.ipv4.tcp_tw_reuse 2>/dev/null || echo 'не задан')"
echo "net.ipv4.tcp_fin_timeout = $(sysctl -n net.ipv4.tcp_fin_timeout 2>/dev/null || echo 'не задан')"
echo "net.ipv4.tcp_keepalive_time = $(sysctl -n net.ipv4.tcp_keepalive_time 2>/dev/null || echo 'не задан')"
echo "net.ipv4.tcp_keepalive_intvl = $(sysctl -n net.ipv4.tcp_keepalive_intvl 2>/dev/null || echo 'не задан')"
echo "net.ipv4.tcp_keepalive_probes = $(sysctl -n net.ipv4.tcp_keepalive_probes 2>/dev/null || echo 'не задан')"
echo "net.ipv4.tcp_syncookies = $(sysctl -n net.ipv4.tcp_syncookies 2>/dev/null || echo 'не задан')"
echo "net.ipv4.tcp_mtu_probing = $(sysctl -n net.ipv4.tcp_mtu_probing 2>/dev/null || echo 'не задан')"
echo ""

echo "--- Лимиты файловых дескрипторов ---"
echo "fs.file-max = $(sysctl -n fs.file-max 2>/dev/null || echo 'не задан')"
echo "Текущие лимиты (ulimit -n): $(ulimit -n)"
echo ""

# =============================================================================
# 5. КОНФИГУРАЦИЯ SYSCTL (все кастомные настройки)
# =============================================================================
echo "============================================================================="
echo "5. КАСТОМНЫЕ SYSCTL НАСТРОЙКИ"
echo "============================================================================="

echo "--- /etc/sysctl.conf (если есть кастомные настройки) ---"
if [[ -f /etc/sysctl.conf ]]; then
    grep -v "^#" /etc/sysctl.conf | grep -v "^$" | head -30 || echo "(пусто или только комментарии)"
else
    echo "(файл не существует)"
fi
echo ""

echo "--- /etc/sysctl.d/*.conf ---"
for f in /etc/sysctl.d/*.conf; do
    if [[ -f "$f" ]]; then
        echo "File: $f"
        grep -v "^#" "$f" | grep -v "^$" | head -20 || echo "(пусто)"
        echo ""
    fi
done
echo ""

# =============================================================================
# 6. XRAY / REMNAWAVE (Docker: remnanode)
# =============================================================================
echo "============================================================================="
echo "6. XRAY / REMNAWAVE (Docker)"
echo "============================================================================="

# Проверка Docker
if ! command -v docker &> /dev/null; then
    echo "Docker не установлен!"
    echo ""
else
    echo "--- Docker версия ---"
    docker --version
    echo ""
    
    echo "--- Все контейнеры ---"
    docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}\t{{.Image}}" 2>/dev/null
    echo ""
    
    echo "--- Контейнер remnanode ---"
    if docker ps -a --format '{{.Names}}' | grep -q "remnanode"; then
        # Статус контейнера
        CONTAINER_STATUS=$(docker inspect remnanode --format='{{.State.Status}}' 2>/dev/null)
        CONTAINER_STARTED=$(docker inspect remnanode --format='{{.State.StartedAt}}' 2>/dev/null)
        CONTAINER_RESTARTS=$(docker inspect remnanode --format='{{.RestartCount}}' 2>/dev/null)
        
        echo "Status: $CONTAINER_STATUS"
        echo "Started: $CONTAINER_STARTED"
        echo "Restart count: $CONTAINER_RESTARTS"
        echo ""
        
        # Версия Xray внутри контейнера
        echo "--- Xray версия (внутри контейнера) ---"
        docker exec remnanode xray version 2>/dev/null | head -5 || echo "Не удалось получить версию xray"
        echo ""
        
        # Ресурсы контейнера
        echo "--- Ресурсы контейнера ---"
        docker stats remnanode --no-stream --format "CPU: {{.CPUPerc}} | RAM: {{.MemUsage}} | Net I/O: {{.NetIO}} | Block I/O: {{.BlockIO}}" 2>/dev/null
        echo ""
        
        # Порты контейнера
        echo "--- Порты контейнера ---"
        docker port remnanode 2>/dev/null || echo "Порты не проброшены"
        echo ""
        
        # Volumes
        echo "--- Volumes контейнера ---"
        docker inspect remnanode --format='{{range .Mounts}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}' 2>/dev/null
        echo ""
        
        # Переменные окружения (без секретов)
        echo "--- Переменные окружения (без секретов) ---"
        docker inspect remnanode --format='{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep -vE "(KEY|SECRET|PASSWORD|TOKEN|ID=)" | head -20
        echo ""
        
        # Логи контейнера (последние 20 строк)
        echo "--- Логи remnanode (последние 20 строк) ---"
        docker logs remnanode --tail 20 2>&1
        echo ""
        
        # Логи ошибок
        echo "--- Ошибки в логах remnanode (последние 10) ---"
        docker logs remnanode 2>&1 | grep -iE "(error|fail|fatal|panic|warn)" | tail -10 || echo "Ошибок не найдено"
        echo ""
        
    else
        echo "Контейнер remnanode НЕ НАЙДЕН!"
        echo "Доступные контейнеры:"
        docker ps -a --format '{{.Names}}'
    fi
fi

echo "--- Systemd сервисы (docker/xray/remna) ---"
systemctl list-units --type=service --state=running | grep -iE "docker|xray|remna|3x-ui|marz" || echo "Сервисы не найдены"
echo ""

# =============================================================================
# 7. XRAY КОНФИГУРАЦИЯ (внутри Docker remnanode)
# =============================================================================
echo "============================================================================="
echo "7. XRAY КОНФИГУРАЦИЯ (RemnaWave Node)"
echo "============================================================================="

if command -v docker &> /dev/null && docker ps -a --format '{{.Names}}' | grep -q "remnanode"; then
    
    echo "--- Структура контейнера remnanode ---"
    docker exec remnanode ls -la / 2>/dev/null | head -20
    echo ""
    
    echo "--- Поиск всех конфигов внутри контейнера ---"
    # Расширенный поиск - все возможные места
    ALL_CONFIGS=$(docker exec remnanode sh -c '
        find / -maxdepth 4 -name "*.json" -type f 2>/dev/null | grep -vE "(node_modules|package)" | head -20
    ' 2>/dev/null)
    echo "Найденные JSON файлы:"
    echo "$ALL_CONFIGS"
    echo ""
    
    # Типичные пути для remnanode
    REMNANODE_PATHS=(
        "/var/lib/remnanode/config.json"
        "/etc/xray/config.json"
        "/app/config.json"
        "/config.json"
        "/data/config.json"
        "/xray/config.json"
        "/usr/local/etc/xray/config.json"
        "/root/config.json"
    )
    
    FOUND_CONFIG=""
    for cfg_path in "${REMNANODE_PATHS[@]}"; do
        if docker exec remnanode test -f "$cfg_path" 2>/dev/null; then
            FOUND_CONFIG="$cfg_path"
            echo "✓ Найден конфиг: $cfg_path"
            break
        fi
    done
    
    # Если не нашли в стандартных путях, берём первый найденный JSON
    if [[ -z "$FOUND_CONFIG" && -n "$ALL_CONFIGS" ]]; then
        FOUND_CONFIG=$(echo "$ALL_CONFIGS" | head -1)
        echo "Используем первый найденный: $FOUND_CONFIG"
    fi
    
    if [[ -n "$FOUND_CONFIG" ]]; then
        echo ""
        echo "============================================"
        echo "АНАЛИЗ КОНФИГА: $FOUND_CONFIG"
        echo "============================================"
        echo ""
        
        # Сохраняем конфиг во временную переменную
        CONFIG_CONTENT=$(docker exec remnanode cat "$FOUND_CONFIG" 2>/dev/null)
        
        echo "--- Inbounds (детально) ---"
        echo "$CONFIG_CONTENT" | jq -r '
            .inbounds[]? | 
            "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Tag: \(.tag // "no-tag")
Port: \(.port)
Protocol: \(.protocol)
Network: \(.streamSettings?.network // "N/A")
Security: \(.streamSettings?.security // "N/A")
Sniffing enabled: \(.sniffing?.enabled // false)
Sniffing routeOnly: \(.sniffing?.routeOnly // "N/A")
Sniffing destOverride: \(.sniffing?.destOverride // [] | join(", "))"
        ' 2>/dev/null || echo "Не удалось распарсить inbounds"
        echo ""
        
        echo "--- Outbounds ---"
        echo "$CONFIG_CONTENT" | jq -r '.outbounds[]? | "Tag: \(.tag // "no-tag") | Protocol: \(.protocol)"' 2>/dev/null || echo "Не удалось распарсить outbounds"
        echo ""
        
        echo "--- Routing ---"
        echo "DomainStrategy: $(echo "$CONFIG_CONTENT" | jq -r '.routing?.domainStrategy // "не задан"' 2>/dev/null)"
        echo "DomainMatcher: $(echo "$CONFIG_CONTENT" | jq -r '.routing?.domainMatcher // "не задан"' 2>/dev/null)"
        RULES_COUNT=$(echo "$CONFIG_CONTENT" | jq '.routing?.rules | length' 2>/dev/null || echo "0")
        echo "Количество правил: $RULES_COUNT"
        echo ""
        
        echo "--- Routing Rules (первые 10) ---"
        echo "$CONFIG_CONTENT" | jq -r '.routing?.rules[:10][]? | "[\(.outboundTag // "?")] <- \(.domain // .ip // .protocol // .inboundTag // "other" | tostring | .[0:50])"' 2>/dev/null || echo "Нет правил"
        echo ""
        
        echo "--- DNS ---"
        echo "$CONFIG_CONTENT" | jq '.dns // "DNS не настроен"' 2>/dev/null
        echo ""
        
        echo "--- Policy ---"
        echo "$CONFIG_CONTENT" | jq '.policy // "Policy не настроен"' 2>/dev/null
        echo ""
        
        echo "--- Reality Settings (если есть) ---"
        echo "$CONFIG_CONTENT" | jq '.inbounds[]?.streamSettings?.realitySettings // empty' 2>/dev/null | head -30
        echo ""
        
        echo "============================================"
        echo "ПОЛНЫЙ КОНФИГ (для детального анализа)"
        echo "============================================"
        echo "НАЧАЛО_КОНФИГА"
        echo "$CONFIG_CONTENT" | jq '.' 2>/dev/null || echo "$CONFIG_CONTENT"
        echo "КОНЕЦ_КОНФИГА"
        echo ""
        
    else
        echo "Конфиг не найден внутри контейнера!"
        echo ""
    fi
    
    # Проверяем volumes на хосте
    echo "--- Volumes на хосте ---"
    VOLUMES=$(docker inspect remnanode --format='{{range .Mounts}}{{.Source}} -> {{.Destination}} ({{.Type}}){{"\n"}}{{end}}' 2>/dev/null)
    echo "$VOLUMES"
    echo ""
    
    # Ищем конфиги в volumes на хосте
    echo "--- Конфиги в volumes на хосте ---"
    for vol_line in $(docker inspect remnanode --format='{{range .Mounts}}{{.Source}}{{"\n"}}{{end}}' 2>/dev/null); do
        if [[ -d "$vol_line" ]]; then
            FOUND_HOST=$(find "$vol_line" -name "*.json" -type f 2>/dev/null)
            if [[ -n "$FOUND_HOST" ]]; then
                echo "В $vol_line:"
                echo "$FOUND_HOST"
            fi
        elif [[ -f "$vol_line" ]]; then
            echo "Файл: $vol_line"
        fi
    done
    echo ""
    
    # Проверяем переменные окружения для путей конфига
    echo "--- Переменные окружения (пути и настройки) ---"
    docker inspect remnanode --format='{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep -iE "(config|path|xray|dir|file)" | head -10
    echo ""
    
else
    echo "Контейнер remnanode не найден или Docker не установлен"
    
    # Fallback: поиск на хосте
    echo ""
    echo "--- Поиск конфигурации на хосте ---"
    find /etc /opt /var /root -name "*xray*.json" -o -name "*remna*.json" 2>/dev/null | head -10
fi
echo ""

# =============================================================================
# 8. ТЕКУЩАЯ НАГРУЗКА И ПРОИЗВОДИТЕЛЬНОСТЬ
# =============================================================================
echo "============================================================================="
echo "8. ТЕКУЩАЯ НАГРУЗКА"
echo "============================================================================="

echo "--- Load Average ---"
cat /proc/loadavg
echo ""

echo "--- Top процессы по CPU ---"
ps aux --sort=-%cpu | head -6
echo ""

echo "--- Top процессы по RAM ---"
ps aux --sort=-%mem | head -6
echo ""

echo "--- Сетевая статистика ---"
if command -v vnstat &> /dev/null; then
    vnstat -h 2>/dev/null | tail -5 || echo "vnstat не настроен"
else
    echo "vnstat не установлен (опционально для мониторинга трафика)"
fi
echo ""

# =============================================================================
# 9. ЛОГИ ОШИБОК (последние)
# =============================================================================
echo "============================================================================="
echo "9. ПОСЛЕДНИЕ ОШИБКИ В ЛОГАХ"
echo "============================================================================="

echo "--- Docker remnanode логи (последние 30 строк) ---"
if command -v docker &> /dev/null && docker ps -a --format '{{.Names}}' | grep -q "remnanode"; then
    docker logs remnanode --tail 30 2>&1
else
    echo "Контейнер remnanode не найден"
fi
echo ""

echo "--- Docker remnanode ошибки (последние 15) ---"
if command -v docker &> /dev/null && docker ps -a --format '{{.Names}}' | grep -q "remnanode"; then
    docker logs remnanode 2>&1 | grep -iE "(error|fail|fatal|panic|refused|timeout|reset)" | tail -15 || echo "Критических ошибок не найдено"
else
    echo "Контейнер remnanode не найден"
fi
echo ""

echo "--- Системные ошибки (последние 10) ---"
journalctl -p err --no-pager -n 10 2>/dev/null | tail -15 || echo "Нет ошибок"
echo ""

echo "--- Docker daemon логи (последние 10) ---"
journalctl -u docker --no-pager -n 10 2>/dev/null | tail -15 || echo "Нет логов docker"
echo ""

# =============================================================================
# 10. РЕКОМЕНДАЦИИ (автоматический анализ)
# =============================================================================
echo "============================================================================="
echo "10. АВТОМАТИЧЕСКИЕ РЕКОМЕНДАЦИИ"
echo "============================================================================="

RECOMMENDATIONS=""

# Проверка BBR
if [[ "$CURRENT_CC" != "bbr" ]]; then
    RECOMMENDATIONS+="[!] BBR не активирован. Рекомендуется включить для лучшей производительности.\n"
fi

# Проверка буферов
RMEM_MAX=$(sysctl -n net.core.rmem_max 2>/dev/null || echo "0")
if [[ $RMEM_MAX -lt 16777216 ]]; then
    RECOMMENDATIONS+="[!] net.core.rmem_max низкий ($RMEM_MAX). Рекомендуется увеличить до 16777216+.\n"
fi

# Проверка file-max
FILE_MAX=$(sysctl -n fs.file-max 2>/dev/null || echo "0")
if [[ $FILE_MAX -lt 1000000 ]]; then
    RECOMMENDATIONS+="[!] fs.file-max низкий ($FILE_MAX). Рекомендуется увеличить для большого количества соединений.\n"
fi

# Проверка ip_forward
IP_FORWARD=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo "0")
if [[ "$IP_FORWARD" != "1" ]]; then
    RECOMMENDATIONS+="[!] IP forwarding отключен. Может потребоваться для некоторых конфигураций.\n"
fi

# Проверка RAM
FREE_MEM=$(free -m | awk '/^Mem:/ {print $7}')
if [[ $FREE_MEM -lt 256 ]]; then
    RECOMMENDATIONS+="[!] Мало свободной RAM ($FREE_MEM MB). Возможны проблемы с производительностью.\n"
fi

# Проверка диска
DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
if [[ $DISK_USAGE -gt 85 ]]; then
    RECOMMENDATIONS+="[!] Диск заполнен на $DISK_USAGE%. Рекомендуется очистка.\n"
fi

if [[ -z "$RECOMMENDATIONS" ]]; then
    echo "✓ Критических проблем не обнаружено"
else
    echo -e "$RECOMMENDATIONS"
fi

echo ""
echo "============================================================================="
echo "           ДИАГНОСТИКА ЗАВЕРШЕНА"
echo "============================================================================="
echo ""
echo "Скопируйте весь вывод выше и отправьте для анализа."
echo ""
