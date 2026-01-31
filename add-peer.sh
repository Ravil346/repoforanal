#!/bin/bash
#
# Добавление пира (ноды) к AWG серверу
# Запускать на панели после настройки ноды
#

AWG_CONFIG="/etc/amnezia/amneziawg/awg0.conf"
AWG_INTERFACE="awg0"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [[ $# -lt 3 ]]; then
    echo "Использование: $0 <имя_ноды> <публичный_ключ> <awg_ip>"
    echo ""
    echo "Примеры:"
    echo "  $0 node-de ПУБЛИЧНЫЙ_КЛЮЧ_НОДЫ 10.10.0.2"
    echo "  $0 node-nl ПУБЛИЧНЫЙ_КЛЮЧ_НОДЫ 10.10.0.3"
    echo "  $0 node-us ПУБЛИЧНЫЙ_КЛЮЧ_НОДЫ 10.10.0.4"
    echo "  $0 node-ru ПУБЛИЧНЫЙ_КЛЮЧ_НОДЫ 10.10.0.5"
    echo "  $0 admin ПУБЛИЧНЫЙ_КЛЮЧ_АДМИНА 10.10.0.100"
    exit 1
fi

NODE_NAME=$1
PUBLIC_KEY=$2
AWG_IP=$3

echo -e "${YELLOW}Добавляю пир: $NODE_NAME ($AWG_IP)${NC}"

# Проверяем что пир не существует
if grep -q "$PUBLIC_KEY" "$AWG_CONFIG" 2>/dev/null; then
    echo -e "${RED}Пир с таким ключом уже существует!${NC}"
    exit 1
fi

# Добавляем пир в конфиг
cat >> "$AWG_CONFIG" << EOF

# $NODE_NAME
[Peer]
PublicKey = $PUBLIC_KEY
AllowedIPs = ${AWG_IP}/32
PersistentKeepalive = 25
EOF

# Применяем конфиг без перезапуска
awg syncconf $AWG_INTERFACE <(awg-quick strip $AWG_INTERFACE)

echo -e "${GREEN}Пир $NODE_NAME добавлен!${NC}"
echo ""
echo -e "AWG IP ноды: ${YELLOW}$AWG_IP${NC}"
echo -e "Теперь измени адрес ноды в RemnaWave Panel на ${YELLOW}$AWG_IP${NC}"
