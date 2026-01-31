#!/bin/bash
#
# AmneziaWG Client Setup for RemnaWave Node
# Версия 2.0 - исправлена установка, добавлен ключ панели
#

set -e

# ===== НАСТРОЙКИ ПАНЕЛИ (НЕ МЕНЯТЬ!) =====
PANEL_PUBLIC_IP="91.208.184.247"
PANEL_AWG_PORT="51820"
PANEL_PUBLIC_KEY="1ZTPs2CbwJfwF8AUuGd3YEQA8YPWV4UKwqVHc/Fn3Cg="

# ===== НАСТРОЙКИ ЭТОЙ НОДЫ (ИЗМЕНИ!) =====
# Выбери AWG IP для этой ноды:
#   10.10.0.2  - Node DE (Германия)
#   10.10.0.3  - Node NL (Нидерланды)
#   10.10.0.4  - Node US (США)
#   10.10.0.5  - Node RU (Россия)
#   10.10.0.6  - Node IN (Индия)
#   10.10.0.7  - Node KR (Корея)

NODE_AWG_IP="10.10.0.3"  # <-- ИЗМЕНИ ПОД СВОЮ НОДУ!
NODE_NAME="node-nl"       # <-- ИЗМЕНИ ПОД СВОЮ НОДУ!

# ===== ПОРТ REMNAWAVE НОДЫ =====
# Если отличается от 47891, измени здесь
REMNAWAVE_PORT="47891"

# ===== НЕ МЕНЯТЬ НИЖЕ =====
AWG_INTERFACE="awg0"
AWG_CONFIG_DIR="/etc/amnezia/amneziawg"

# Обфускация (ДОЛЖНЫ СОВПАДАТЬ С СЕРВЕРОМ!)
JC=4
JMIN=40
JMAX=70
S1=0
S2=0
H1=1
H2=2
H3=3
H4=4

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  AmneziaWG Client Setup for Node${NC}"
echo -e "${GREEN}  Версия 2.0${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "Нода: ${YELLOW}$NODE_NAME${NC}"
echo -e "AWG IP: ${YELLOW}$NODE_AWG_IP${NC}"
echo ""

# Проверка root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Запустите скрипт от root!${NC}"
   exit 1
fi

# Проверка что NODE_AWG_IP изменён
if [[ "$NODE_AWG_IP" == "10.10.0.3" && "$NODE_NAME" == "node-nl" ]]; then
    echo -e "${YELLOW}ВНИМАНИЕ: Используются настройки по умолчанию (NL нода)${NC}"
    echo -e "Если это не NL нода, отредактируй NODE_AWG_IP и NODE_NAME в скрипте"
    read -p "Продолжить? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# 1. Установка AmneziaWG
echo -e "\n${YELLOW}[1/6] Установка AmneziaWG...${NC}"

if ! command -v awg &> /dev/null; then
    echo -e "${YELLOW}Добавляем репозиторий Amnezia (прямой метод)...${NC}"
    
    # Добавляем ключ напрямую
    curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x57290828" | gpg --dearmor -o /usr/share/keyrings/amnezia.gpg
    
    # Добавляем репозиторий
    echo "deb [signed-by=/usr/share/keyrings/amnezia.gpg] https://ppa.launchpadcontent.net/amnezia/ppa/ubuntu focal main" | tee /etc/apt/sources.list.d/amnezia.list
    
    # Устанавливаем
    apt-get update
    apt-get install -y linux-headers-$(uname -r)
    apt-get install -y amneziawg amneziawg-tools
    
    modprobe amneziawg
    
    echo -e "${GREEN}AmneziaWG установлен${NC}"
else
    echo -e "${GREEN}AmneziaWG уже установлен${NC}"
    modprobe amneziawg 2>/dev/null || true
fi

# Проверка модуля
if ! lsmod | grep -q amneziawg; then
    echo -e "${RED}Модуль amneziawg не загружен!${NC}"
    exit 1
fi

# 2. Генерация ключей
echo -e "\n${YELLOW}[2/6] Генерация ключей...${NC}"

mkdir -p "$AWG_CONFIG_DIR"
cd "$AWG_CONFIG_DIR"

if [[ ! -f privatekey ]]; then
    awg genkey | tee privatekey | awg pubkey > publickey
    chmod 600 privatekey
    echo -e "${GREEN}Ключи сгенерированы${NC}"
else
    echo -e "${GREEN}Ключи уже существуют${NC}"
fi

PRIVATE_KEY=$(cat privatekey)
PUBLIC_KEY=$(cat publickey)

# 3. Создание конфига клиента
echo -e "\n${YELLOW}[3/6] Создание конфигурации...${NC}"

cat > "$AWG_CONFIG_DIR/$AWG_INTERFACE.conf" << EOF
[Interface]
Address = ${NODE_AWG_IP}/32
PrivateKey = $PRIVATE_KEY

# Обфускация (совпадает с сервером)
Jc = $JC
Jmin = $JMIN
Jmax = $JMAX
S1 = $S1
S2 = $S2
H1 = $H1
H2 = $H2
H3 = $H3
H4 = $H4

[Peer]
# Panel Server
PublicKey = $PANEL_PUBLIC_KEY
Endpoint = ${PANEL_PUBLIC_IP}:${PANEL_AWG_PORT}
AllowedIPs = 10.10.0.0/24
PersistentKeepalive = 25
EOF

chmod 600 "$AWG_CONFIG_DIR/$AWG_INTERFACE.conf"

# 4. Настройка файрвола
echo -e "\n${YELLOW}[4/6] Настройка файрвола...${NC}"

if command -v ufw &> /dev/null; then
    # Разрешаем трафик из AWG сети к порту RemnaNode
    ufw allow from 10.10.0.0/24 to any port $REMNAWAVE_PORT proto tcp comment "RemnaWave via AWG" 2>/dev/null || true
    
    # Удаляем старое правило для публичного IP панели (если есть)
    ufw delete allow from 91.208.184.247 to any port $REMNAWAVE_PORT proto tcp 2>/dev/null || true
    
    echo -e "${GREEN}Файрвол настроен: 10.10.0.0/24 → порт $REMNAWAVE_PORT${NC}"
else
    echo -e "${YELLOW}UFW не установлен, настрой файрвол вручную${NC}"
fi

# 5. Создание systemd сервиса
echo -e "\n${YELLOW}[5/6] Настройка автозапуска...${NC}"

cat > /etc/systemd/system/awg-quick@.service << 'EOF'
[Unit]
Description=AmneziaWG via awg-quick(8) for %I
After=network-online.target nss-lookup.target
Wants=network-online.target nss-lookup.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/awg-quick up %i
ExecStop=/usr/bin/awg-quick down %i

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable awg-quick@$AWG_INTERFACE

# 6. Запуск
echo -e "\n${YELLOW}[6/6] Запуск AmneziaWG...${NC}"

awg-quick down $AWG_INTERFACE 2>/dev/null || true
awg-quick up $AWG_INTERFACE

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}  Установка завершена!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "Публичный ключ этой ноды:"
echo -e "${YELLOW}$PUBLIC_KEY${NC}"
echo ""
echo -e "${RED}ВАЖНО! Следующие шаги:${NC}"
echo ""
echo -e "1. ${YELLOW}На панели${NC} добавь эту ноду командой:"
echo -e "   ${GREEN}./add-peer.sh $NODE_NAME $PUBLIC_KEY $NODE_AWG_IP${NC}"
echo ""
echo -e "2. ${YELLOW}В RemnaWave Panel${NC} измени адрес ноды:"
echo -e "   Было:  публичный IP (например 193.x.x.x)"
echo -e "   Стало: ${GREEN}$NODE_AWG_IP${NC}"
echo ""
echo -e "3. Проверь связь:"
echo -e "   ${GREEN}ping 10.10.0.1${NC}  (должен пинговаться)"
echo ""
echo -e "Статус AWG: ${YELLOW}awg show${NC}"
echo ""

# Ждём handshake
echo -e "${YELLOW}Ожидание handshake с панелью...${NC}"
sleep 3
awg show

# Проверяем связь
echo ""
echo -e "${YELLOW}Проверка связи с панелью:${NC}"
ping -c 3 10.10.0.1 || echo -e "${RED}Нет связи! Добавь пир на панели.${NC}"