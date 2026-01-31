#!/bin/bash
#
# AmneziaWG Client Setup for RemnaWave Node
# Запускать на каждой ноде
#

set -e

# ===== НАСТРОЙКИ (ИЗМЕНИ ПОД СВОЮ НОДУ!) =====
PANEL_PUBLIC_IP="91.208.184.247"   # Публичный IP панели
PANEL_AWG_PORT="51820"              # AWG порт панели
PANEL_PUBLIC_KEY="ВСТАВЬ_ПУБЛИЧНЫЙ_КЛЮЧ_ПАНЕЛИ"  # Получишь после запуска скрипта на панели

# AWG IP этой ноды (выбери из списка):
# 10.10.0.2 - Node DE
# 10.10.0.3 - Node NL  
# 10.10.0.4 - Node US
# 10.10.0.5 - Node RU
NODE_AWG_IP="10.10.0.3/32"  # <-- ИЗМЕНИ!

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
echo -e "${GREEN}========================================${NC}"

# Проверка root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Запустите скрипт от root!${NC}"
   exit 1
fi

# Проверка что ключ панели указан
if [[ "$PANEL_PUBLIC_KEY" == "ВСТАВЬ_ПУБЛИЧНЫЙ_КЛЮЧ_ПАНЕЛИ" ]]; then
    echo -e "${RED}ОШИБКА: Укажи публичный ключ панели в переменной PANEL_PUBLIC_KEY!${NC}"
    echo -e "Получи его после запуска скрипта на панели."
    exit 1
fi

# 1. Установка AmneziaWG
echo -e "\n${YELLOW}[1/5] Установка AmneziaWG...${NC}"

if ! command -v awg &> /dev/null; then
    apt-get update
    apt-get install -y software-properties-common
    add-apt-repository -y ppa:amnezia/ppa
    apt-get update
    apt-get install -y amneziawg amneziawg-tools
    
    modprobe amneziawg || {
        echo -e "${YELLOW}Попробуем DKMS установку...${NC}"
        apt-get install -y amneziawg-dkms
        modprobe amneziawg
    }
else
    echo -e "${GREEN}AmneziaWG уже установлен${NC}"
fi

# 2. Генерация ключей
echo -e "\n${YELLOW}[2/5] Генерация ключей...${NC}"

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
echo -e "\n${YELLOW}[3/5] Создание конфигурации...${NC}"

cat > "$AWG_CONFIG_DIR/$AWG_INTERFACE.conf" << EOF
[Interface]
Address = $NODE_AWG_IP
PrivateKey = $PRIVATE_KEY

# AmneziaWG обфускация
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
echo -e "\n${YELLOW}[4/5] Настройка файрвола...${NC}"

# Разрешаем трафик из AWG сети к порту RemnaNode
NODE_PORT=$(grep -oP '^\d+' /opt/remnanode/.env 2>/dev/null | head -1 || echo "47891")

# Удаляем старое правило если есть (для конкретного IP панели)
ufw delete allow from 91.208.184.247 to any port 47891 proto tcp 2>/dev/null || true

# Добавляем правило для AWG сети
ufw allow from 10.10.0.0/24 to any port $NODE_PORT proto tcp comment "RemnaWave via AWG"
echo -e "${GREEN}Файрвол обновлён: разрешено 10.10.0.0/24 → порт $NODE_PORT${NC}"

# 5. Запуск сервиса
echo -e "\n${YELLOW}[5/5] Запуск AmneziaWG...${NC}"

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
Environment=WG_ENDPOINT_RESOLUTION_RETRIES=infinity

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable awg-quick@$AWG_INTERFACE
systemctl start awg-quick@$AWG_INTERFACE || awg-quick up $AWG_INTERFACE

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}  Установка завершена!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "Публичный ключ этой ноды:"
echo -e "${YELLOW}$PUBLIC_KEY${NC}"
echo ""
echo -e "${RED}ВАЖНО! Следующие шаги:${NC}"
echo ""
echo -e "1. На панели добавь эту ноду:"
echo -e "   ${YELLOW}./add-peer.sh node-xxx $PUBLIC_KEY ${NODE_AWG_IP%/*}${NC}"
echo ""
echo -e "2. В RemnaWave Panel измени адрес ноды:"
echo -e "   Было:  193.x.x.x (публичный IP)"
echo -e "   Стало: ${YELLOW}${NODE_AWG_IP%/*}${NC} (AWG IP)"
echo ""
echo -e "Проверка связи: ${YELLOW}ping 10.10.0.1${NC}"
echo -e "Статус AWG: ${YELLOW}awg show${NC}"
