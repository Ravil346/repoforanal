#!/bin/bash
# VPN Node Optimization Script v2

# 1. Включить BBR
echo "Включение BBR..."
modprobe tcp_bbr
echo "tcp_bbr" >> /etc/modules-load.d/bbr.conf

# 2. Настройки sysctl (эталон с India)
cat > /etc/sysctl.d/99-vpn-optimization.conf << 'EOF'
# BBR
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Буферы (эталон с India)
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# Соединения
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 16384

# Fast Open
net.ipv4.tcp_fastopen = 3

# Keepalive
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5

# Timeouts
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
EOF

# 3. Применить
sysctl -p /etc/sysctl.d/99-vpn-optimization.conf

# 4. Увеличить ulimit для Docker
mkdir -p /etc/systemd/system/docker.service.d
cat > /etc/systemd/system/docker.service.d/limits.conf << 'EOF'
[Service]
LimitNOFILE=65535
LimitNPROC=65535
EOF

systemctl daemon-reload
systemctl restart docker

echo "Готово! Проверьте:"
echo "sysctl net.ipv4.tcp_congestion_control"
echo "sysctl net.core.rmem_max"