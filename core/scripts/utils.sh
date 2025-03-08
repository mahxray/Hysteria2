source /etc/hysteria/core/scripts/path.sh
# source /etc/hysteria/core/scripts/services_status.sh

# Function to define colors
define_colors() {
    green='\033[0;32m'
    cyan='\033[0;36m'
    red='\033[0;31m'
    yellow='\033[0;33m'
    LPurple='\033[1;35m'
    NC='\033[0m' # No Color
}

get_system_info() {
    OS=$(lsb_release -d | awk -F'\t' '{print $2}')
    ARCH=$(uname -m)
    IP_API_DATA=$(curl -s https://ipapi.co/json/ -4)
    ISP=$(echo "$IP_API_DATA" | jq -r '.org')
    IP=$(echo "$IP_API_DATA" | jq -r '.ip')
    CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4 "%"}')
    RAM=$(free -m | awk 'NR==2{printf "%.2f%%", $3*100/$2 }')
}

version_greater_equal() {
    IFS='.' read -r -a local_version_parts <<< "$1"
    IFS='.' read -r -a latest_version_parts <<< "$2"

    for ((i=0; i<${#local_version_parts[@]}; i++)); do
        if [[ -z ${latest_version_parts[i]} ]]; then
            latest_version_parts[i]=0
        fi

        if ((10#${local_version_parts[i]} > 10#${latest_version_parts[i]})); then
            return 0
        elif ((10#${local_version_parts[i]} < 10#${latest_version_parts[i]})); then
            return 1
        fi
    done

    return 0
}

check_core_version() {
    if systemctl is-active --quiet hysteria-server.service; then
        HCVERSION=$(hysteria version | grep "^Version:" | awk '{print $2}')
        echo -e "Hysteria2 Core Version: ${cyan}$HCVERSION${NC}"
    fi
}

check_version() {
    local_version=$(cat $LOCALVERSION)
    latest_version=$(curl -s $LATESTVERSION)
    latest_changelog=$(curl -s $LASTESTCHANGE)

    if version_greater_equal "$local_version" "$latest_version"; then
        echo -e "Panel Version: ${cyan}$local_version${NC}"
    else
        echo -e "Panel Version: ${cyan}$local_version${NC}"
        echo -e "Latest Version: ${cyan}$latest_version${NC}"
        echo -e "${yellow}$latest_version Version Change Log:${NC}"
        echo -e "${cyan}$latest_changelog ${NC}"
    fi
}


load_hysteria2_env() {
    if [ -f "$CONFIG_ENV" ]; then
        export $(grep -v '^#' "$CONFIG_ENV" | xargs)
    else
        echo "Error: configs.env file not found. Using default SNI 'bts.com'."
        SNI="bts.com"
    fi
}

load_hysteria2_ips() {
    if [ -f "$CONFIG_ENV" ]; then
        export $(grep -v '^#' "$CONFIG_ENV" | xargs)

        if [[ -z "$IP4" || -z "$IP6" ]]; then
            echo "Warning: IP4 or IP6 is not set in configs.env. Fetching from system..."
            default_interface=$(ip route | grep default | awk '{print $5}')
            IP4=$(ip addr show "$default_interface" | grep "inet " | awk '{print $2}' | cut -d '/' -f 1 | head -n 1)
            IP6=$(ip addr show "$default_interface" | grep "inet6 " | awk '{print $2}' | grep -v "^fe80::" | cut -d '/' -f 1 | head -n 1)
        fi
    else
        echo "Error: configs.env file not found. Fetching IPs from system..."
        default_interface=$(ip route | grep default | awk '{print $5}')
        IP4=$(ip addr show "$default_interface" | grep "inet " | awk '{print $2}' | cut -d '/' -f 1 | head -n 1)
        IP6=$(ip addr show "$default_interface" | grep "inet6 " | awk '{print $2}' | grep -v "^fe80::" | cut -d '/' -f 1 | head -n 1)
    fi

    echo "IP4=$IP4" > "$CONFIG_ENV"
    echo "IP6=$IP6" >> "$CONFIG_ENV"
}


# check_services() {
#     # source /etc/hysteria/core/scripts/services_status.sh
#     for service in "${services[@]}"; do
#         service_base_name=$(basename "$service" .service)

#         display_name=$(echo "$service_base_name" | sed -E 's/([^-]+)-?/\u\1/g') 

#         if systemctl is-active --quiet "$service"; then
#             echo -e "${NC}${display_name}:${green} Active${NC}"
#         else
#             echo -e "${NC}${display_name}:${red} Inactive${NC}"
#         fi
#     done
# }
