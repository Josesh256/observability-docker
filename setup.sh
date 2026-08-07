#!/bin/bash
# Bash Automated Setup for Observability & VPN Stack
# Designed to run unattended and auto-configure

set -e

echo -e "\033[36m=============================================\033[0m"
echo -e "\033[36m   Observability & VPN Stack Initializer     \033[0m"
echo -e "\033[36m=============================================\033[0m"

# 1. Check for Docker
if ! command -v docker &> /dev/null; then
    echo -e "\033[31mError: Docker is not installed or not in PATH.\033[0m"
    exit 1
fi

# 2. Check and Load .env
ENV_FILE=".env"
if [ ! -f "$ENV_FILE" ]; then
    echo -e "\033[33mCreating default .env file...\033[0m"
    cat <<EOF > "$ENV_FILE"
PROJECT_NAME=observability-stack
NGINX_PORT=8080
GRAFANA_PORT=3000
PROMETHEUS_PORT=9090
WIREGUARD_PORT=51820
GF_SECURITY_ADMIN_PASSWORD=admin
WG_SERVERURL=127.0.0.1
WG_PEERS=laptop,phone
WG_PEER_DNS=1.1.1.1
WG_INTERNAL_SUBNET=10.13.13.0/24
EOF
fi

# Helper to read .env
get_env_var() {
    local key=$1
    local default=$2
    local value=$(grep -E "^${key}=" "$ENV_FILE" | cut -d= -f2- | tr -d '\r')
    echo "${value:-$default}"
}

# Helper to update .env
set_env_var() {
    local key=$1
    local value=$2
    if grep -q "^${key}=" "$ENV_FILE"; then
        sed -i.bak "s|^${key}=.*|${key}=${value}|" "$ENV_FILE" && rm -f "${ENV_FILE}.bak"
    else
        echo "${key}=${value}" >> "$ENV_FILE"
    fi
}

NGINX_PORT=$(get_env_var "NGINX_PORT" "8080")
GRAFANA_PORT=$(get_env_var "GRAFANA_PORT" "3000")
PROMETHEUS_PORT=$(get_env_var "PROMETHEUS_PORT" "9090")
WIREGUARD_PORT=$(get_env_var "WIREGUARD_PORT" "51820")
WG_UI_PORT=$(get_env_var "WG_UI_PORT" "51821")


# Helper to check if a TCP port is occupied
is_tcp_port_busy() {
    local port=$1
    if command -v lsof &> /dev/null; then
        lsof -iTCP:${port} -sTCP:LISTEN &>/dev/null
    elif command -v netstat &> /dev/null; then
        netstat -tuln | grep -q ":${port} "
    else
        (echo >/dev/tcp/127.0.0.1/${port}) &>/dev/null
    fi
}

# Helper to check if a UDP port is occupied
is_udp_port_busy() {
    local port=$1
    if command -v lsof &> /dev/null; then
        lsof -iUDP:${port} &>/dev/null
    elif command -v netstat &> /dev/null; then
        netstat -tuln | grep -q ":${port} "
    else
        false
    fi
}

echo -e "\033[37mValidating port availability...\033[0m"

# Nginx
while is_tcp_port_busy "$NGINX_PORT"; do
    echo -e "\033[33mPort $NGINX_PORT is occupied. Trying next...\033[0m"
    NGINX_PORT=$((NGINX_PORT + 1))
done
set_env_var "NGINX_PORT" "$NGINX_PORT"

# Grafana
while is_tcp_port_busy "$GRAFANA_PORT"; do
    echo -e "\033[33mPort $GRAFANA_PORT is occupied. Trying next...\033[0m"
    GRAFANA_PORT=$((GRAFANA_PORT + 1))
done
set_env_var "GRAFANA_PORT" "$GRAFANA_PORT"

# Prometheus
while is_tcp_port_busy "$PROMETHEUS_PORT"; do
    echo -e "\033[33mPort $PROMETHEUS_PORT is occupied. Trying next...\033[0m"
    PROMETHEUS_PORT=$((PROMETHEUS_PORT + 1))
done
set_env_var "PROMETHEUS_PORT" "$PROMETHEUS_PORT"

# WireGuard (UDP)
while is_udp_port_busy "$WIREGUARD_PORT"; do
    echo -e "\033[33mUDP Port $WIREGUARD_PORT is occupied. Trying next...\033[0m"
    WIREGUARD_PORT=$((WIREGUARD_PORT + 1))
done
set_env_var "WIREGUARD_PORT" "$WIREGUARD_PORT"

# WireGuard UI (TCP)
while is_tcp_port_busy "$WG_UI_PORT"; do
    echo -e "\033[33mPort $WG_UI_PORT is occupied. Trying next...\033[0m"
    WG_UI_PORT=$((WG_UI_PORT + 1))
done
set_env_var "WG_UI_PORT" "$WG_UI_PORT"

PROJECT_NAME=$(get_env_var "PROJECT_NAME" "observability-stack")

echo -e "\n\033[32mConfiguration set:\033[0m"
echo "--------------------"
echo "Project Name:    $PROJECT_NAME"
echo "Nginx Port:      $NGINX_PORT"
echo "Grafana Port:    $GRAFANA_PORT"
echo "Prometheus Port: $PROMETHEUS_PORT"
echo "WireGuard Port:  $WIREGUARD_PORT (UDP)"
echo "WireGuard UI:    $WG_UI_PORT"
echo "--------------------"

# Create folders
mkdir -p vpn/config apps/web/html monitoring/prometheus monitoring/grafana/provisioning/datasources monitoring/grafana/provisioning/dashboards

# Start Stack
echo -e "\n\033[32mStarting docker containers...\033[0m"
docker compose -p "$PROJECT_NAME" up -d

echo -e "\n\033[32mStack deployed successfully! 🎉\033[0m"
echo "Access URLs:"
echo -e "- Web App:      \033[36mhttp://localhost:$NGINX_PORT\033[0m"
echo -e "- Grafana:      \033[36mhttp://localhost:$GRAFANA_PORT\033[0m"
echo -e "- Prometheus:   \033[36mhttp://localhost:$PROMETHEUS_PORT\033[0m"
echo -e "- WireGuard UI: \033[36mhttp://localhost:$WG_UI_PORT\033[0m"
echo -e "\n\033[33mWireGuard configurations can be managed via the Web UI!\033[0m"

