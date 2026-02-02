#!/bin/bash

# ===========================================
# Promtail Setup для RemnaWave нод
# Отправка логов через AWG на VictoriaLogs
# ===========================================
# Использование: ./install-promtail.sh <node-name>
# Пример: ./install-promtail.sh hop-ya-ru
# ===========================================

set -e

NODE_NAME=${1:-""}
VICTORIA_URL="http://10.10.0.1:9428/insert/loki/api/v1/push"

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "========================================"
echo "  Promtail Installer for RemnaWave"
echo "========================================"
echo ""

# Проверка имени ноды
if [ -z "$NODE_NAME" ]; then
    echo -e "${RED}❌ Укажи имя ноды!${NC}"
    echo ""
    echo "Использование: ./install-promtail.sh <node-name>"
    echo ""
    echo "Примеры:"
    echo "  ./install-promtail.sh hop-ya-ru"
    echo "  ./install-promtail.sh india-node"
    echo "  ./install-promtail.sh usa-node"
    echo ""
    exit 1
fi

echo -e "Имя ноды: ${GREEN}$NODE_NAME${NC}"
echo ""

# Проверка AWG туннеля
echo "🔍 Проверка AWG туннеля..."
if ping -c 1 -W 3 10.10.0.1 &> /dev/null; then
    echo -e "${GREEN}✅ AWG туннель активен${NC}"
else
    echo -e "${RED}❌ AWG туннель не работает!${NC}"
    echo ""
    echo "Сначала настрой AWG на этой ноде."
    echo "Проверь: wg show"
    exit 1
fi

# Поиск директории remnanode
echo ""
echo "🔍 Поиск директории remnanode..."

REMNANODE_DIR=""
SEARCH_DIRS=(
    "/opt/remnanode"
    "/opt/remnawave-node"
    "/root/remnawave-node"
    "/home/*/remnawave-node"
)

for pattern in "${SEARCH_DIRS[@]}"; do
    for dir in $pattern; do
        if [ -f "$dir/docker-compose.yml" ] && grep -q "remnawave/node" "$dir/docker-compose.yml" 2>/dev/null; then
            REMNANODE_DIR="$dir"
            break 2
        fi
    done
done

if [ -z "$REMNANODE_DIR" ]; then
    echo -e "${RED}❌ Не найден docker-compose.yml для remnanode${NC}"
    echo ""
    echo "Попробуй указать путь вручную:"
    echo "  REMNANODE_DIR=/path/to/node ./install-promtail.sh $NODE_NAME"
    exit 1
fi

echo -e "${GREEN}✅ Найден каталог: $REMNANODE_DIR${NC}"
cd "$REMNANODE_DIR"

# Бэкап существующих файлов
if [ -f docker-compose.override.yml ]; then
    echo ""
    echo "📦 Бэкап существующего docker-compose.override.yml..."
    cp docker-compose.override.yml "docker-compose.override.yml.bak.$(date +%Y%m%d_%H%M%S)"
fi

if [ -f promtail-config.yaml ]; then
    echo "📦 Бэкап существующего promtail-config.yaml..."
    cp promtail-config.yaml "promtail-config.yaml.bak.$(date +%Y%m%d_%H%M%S)"
fi

# Создаём docker-compose.override.yml
echo ""
echo "📝 Создание docker-compose.override.yml..."

cat > docker-compose.override.yml << 'EOF'
services:
  remnanode:
    volumes:
      - xray-logs:/var/log/supervisor

  promtail:
    image: grafana/promtail:3.0.0
    container_name: promtail
    restart: always
    network_mode: host
    volumes:
      - xray-logs:/var/log/xray:ro
      - ./promtail-config.yaml:/etc/promtail/config.yaml
    command: -config.file=/etc/promtail/config.yaml

volumes:
  xray-logs:
EOF

echo -e "${GREEN}✅ docker-compose.override.yml создан${NC}"

# Создаём promtail-config.yaml
echo "📝 Создание promtail-config.yaml..."

cat > promtail-config.yaml << EOF
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: ${VICTORIA_URL}

scrape_configs:
  - job_name: xray
    static_configs:
      - targets:
          - localhost
        labels:
          job: xray
          node: ${NODE_NAME}
          __path__: /var/log/xray/xray.out.log

  - job_name: xray-errors
    static_configs:
      - targets:
          - localhost
        labels:
          job: xray-errors
          node: ${NODE_NAME}
          __path__: /var/log/xray/xray.err.log
EOF

echo -e "${GREEN}✅ promtail-config.yaml создан${NC}"

# Перезапуск контейнеров
echo ""
echo "🔄 Перезапуск контейнеров..."
docker compose down
docker compose up -d

# Ожидание запуска
echo ""
echo "⏳ Ожидание запуска контейнеров..."
sleep 5

# Проверки
echo ""
echo "========================================"
echo "  Проверка установки"
echo "========================================"
echo ""

ERRORS=0

# Проверка Promtail
if docker ps --format '{{.Names}}' | grep -q "^promtail$"; then
    echo -e "${GREEN}✅ Promtail запущен${NC}"
else
    echo -e "${RED}❌ Promtail не запустился${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Проверка Remnanode
if docker ps --format '{{.Names}}' | grep -q "^remnanode$"; then
    echo -e "${GREEN}✅ Remnanode запущен${NC}"
else
    echo -e "${RED}❌ Remnanode не запустился${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Проверка соединения с VictoriaLogs
sleep 2
if ss -tnp 2>/dev/null | grep -q "10.10.0.1:9428"; then
    echo -e "${GREEN}✅ Соединение с VictoriaLogs установлено${NC}"
else
    echo -e "${YELLOW}⚠️  Соединение с VictoriaLogs пока не установлено${NC}"
    echo "   (может появиться через несколько секунд)"
fi

# Итог
echo ""
echo "========================================"
if [ $ERRORS -eq 0 ]; then
    echo -e "  ${GREEN}Установка завершена успешно!${NC}"
    echo "========================================"
    echo ""
    echo "Логи ноды '$NODE_NAME' отправляются на VictoriaLogs"
    echo ""
    echo "Полезные команды:"
    echo "  docker logs promtail --tail 20    # Логи Promtail"
    echo "  docker logs remnanode --tail 20   # Логи Remnanode"
    echo "  ss -tnp | grep 9428               # Соединение с VictoriaLogs"
else
    echo -e "  ${RED}Установка завершена с ошибками${NC}"
    echo "========================================"
    echo ""
    echo "Проверь логи:"
    echo "  docker logs promtail --tail 30"
    echo "  docker logs remnanode --tail 30"
    exit 1
fi
