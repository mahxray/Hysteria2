#!/bin/bash

# Function to define colors
define_colors() {
    green='\033[0;32m'
    cyan='\033[0;36m'
    red='\033[0;31m'
    yellow='\033[0;33m'
    LPurple='\033[1;35m'
    NC='\033[0m' # No Color
}

# Ensure necessary packages are installed
clear
if ! command -v jq &> /dev/null || ! command -v qrencode &> /dev/null || ! command -v curl &> /dev/null; then
    echo "${yellow}Necessary packages are not installed. Please wait while they are being installed..."
    sleep 3
    echo 
    apt update && apt upgrade -y && apt install jq qrencode curl pwgen uuid-runtime python3 python3-pip -y
fi

# Add alias 'hys2' for Hysteria2
if ! grep -q "alias hys2='bash <(curl https://raw.githubusercontent.com/H-Return/Hysteria2/main/menu.sh)'" ~/.bashrc; then
    echo "alias hys2='bash <(curl https://raw.githubusercontent.com/H-Return/Hysteria2/main/menu.sh)'" >> ~/.bashrc
    source ~/.bashrc
fi

# Function to get system information
get_system_info() {
    OS=$(lsb_release -d | awk -F'\t' '{print $2}')
    ARCH=$(uname -m)
    # Fetching detailed IP information in JSON format
    IP_API_DATA=$(curl -s https://ipapi.co/json/ -4)
    ISP=$(echo "$IP_API_DATA" | jq -r '.org')
    IP=$(echo "$IP_API_DATA" | jq -r '.ip')
    CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4 "%"}')
    RAM=$(free -m | awk 'NR==2{printf "%.2f%%", $3*100/$2 }')
}

# Function to install and configure Hysteria2
install_and_configure() {
    if systemctl is-active --quiet hysteria-server.service; then
        echo -e "${red}Error:${NC} Hysteria2 is already installed and running."
        echo
        echo "If you need to update the core, please use the 'Update Core' option."
    else
        echo "Installing and configuring Hysteria2..."
        bash <(curl -s https://raw.githubusercontent.com/ReturnFI/Hysteria2/main/install.sh)
        echo -e "\n"

        if systemctl is-active --quiet hysteria-server.service; then
            echo "Installation and configuration complete."
        else
            echo -e "${red}Error:${NC} Hysteria2 service is not active. Please check the logs for more details."
        fi
    fi
}

# TODO: remove
# Function to update Hysteria2
update_core() {
    echo "Starting the update process for Hysteria2..." 
    echo "Backing up the current configuration..."
    cp /etc/hysteria/config.json /etc/hysteria/config_backup.json
    if [ $? -ne 0 ]; then
        echo "${red}Error:${NC} Failed to back up configuration. Aborting update."
        return 1
    fi

    echo "Downloading and installing the latest version of Hysteria2..."
    bash <(curl -fsSL https://get.hy2.sh/) >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "${red}Error:${NC} Failed to download or install the latest version. Restoring backup configuration."
        mv /etc/hysteria/config_backup.json /etc/hysteria/config.json
        restart_hysteria_service >/dev/null 2>&1
        return 1
    fi

    echo "Restoring configuration from backup..."
    mv /etc/hysteria/config_backup.json /etc/hysteria/config.json
    if [ $? -ne 0 ]; then
        echo "${red}Error:${NC} Failed to restore configuration from backup."
        return 1
    fi

    echo "Modifying systemd service to use config.json..."
    sed -i 's|/etc/hysteria/config.yaml|/etc/hysteria/config.json|' /etc/systemd/system/hysteria-server.service
    if [ $? -ne 0 ]; then
        echo "${red}Error:${NC} Failed to modify systemd service."
        return 1
    fi

    rm /etc/hysteria/config.yaml
    systemctl daemon-reload >/dev/null 2>&1
    restart_hysteria_service >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "${red}Error:${NC} Failed to restart Hysteria2 service."
        return 1
    fi

    echo "Hysteria2 has been successfully updated."
    echo ""
    return 0
}

# Function to change port
change_port() {
    while true; do
        read -p "Enter the new port number you want to use: " port
        if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
            echo "Invalid port number. Please enter a number between 1 and 65535."
        else
            break
        fi
    done

    if [ -f "/etc/hysteria/config.json" ]; then
        jq --arg port "$port" '.listen = ":" + $port' /etc/hysteria/config.json > /etc/hysteria/config_temp.json && mv /etc/hysteria/config_temp.json /etc/hysteria/config.json
        restart_hysteria_service >/dev/null 2>&1
        echo "Port changed successfully to $port."
    else
        echo "${red}Error:${NC} Config file /etc/hysteria/config.json not found."
    fi
}

# Function to show URI if Hysteria2 is installed and active
show_uri() {
    if [ -f "/etc/hysteria/users/users.json" ]; then
        if systemctl is-active --quiet hysteria-server.service; then
            # Get the list of configured usernames
            usernames=$(jq -r 'keys_unsorted[]' /etc/hysteria/users/users.json)
            
            # Prompt the user to select a username
            PS3="Select a username: "
            select username in $usernames; do
                if [ -n "$username" ]; then
                    # Get the selected user's details
                    authpassword=$(jq -r ".\"$username\".password" /etc/hysteria/users/users.json)
                    port=$(jq -r '.listen' /etc/hysteria/config.json | cut -d':' -f2)
                    sha256=$(jq -r '.tls.pinSHA256' /etc/hysteria/config.json)
                    obfspassword=$(jq -r '.obfs.salamander.password' /etc/hysteria/config.json)

                    # Get IP addresses
                    IP=$(curl -s -4 ip.gs)
                    IP6=$(curl -s -6 ip.gs)

                    # Construct URI
                    URI="hy2://$username%3A$authpassword@$IP:$port?obfs=salamander&obfs-password=$obfspassword&pinSHA256=$sha256&insecure=1&sni=bts.com#$username-IPv4"
                    URI6="hy2://$username%3A$authpassword@[$IP6]:$port?obfs=salamander&obfs-password=$obfspassword&pinSHA256=$sha256&insecure=1&sni=bts.com#$username-IPv6"

                    # Generate QR codes
                    qr1=$(echo -n "$URI" | qrencode -t UTF8 -s 3 -m 2)
                    qr2=$(echo -n "$URI6" | qrencode -t UTF8 -s 3 -m 2)

                    # Display QR codes and URIs
                    cols=$(tput cols)
                    echo -e "\nIPv4:\n"
                    echo "$qr1" | while IFS= read -r line; do
                        printf "%*s\n" $(( (${#line} + cols) / 2)) "$line"
                    done

                    echo -e "\nIPv6:\n"
                    echo "$qr2" | while IFS= read -r line; do
                        printf "%*s\n" $(( (${#line} + cols) / 2)) "$line"
                    done

                    echo
                    echo "IPv4: $URI"
                    echo
                    echo "IPv6: $URI6"
                    echo
                    break
                else
                    echo "Invalid selection. Please try again."
                fi
            done
        else
            echo -e "\033[0;31mError:\033[0m Hysteria2 is not active."
        fi
    else
        echo -e "\033[0;31mError:\033[0m Config file /etc/hysteria/users/users.json not found."
    fi
}

# Function to check traffic status for each user
traffic_status() {
    if [ -f "/etc/hysteria/traffic.py" ]; then
        python3 /etc/hysteria/traffic.py >/dev/null 2>&1
    else
        echo "Error: /etc/hysteria/traffic.py not found."
        return 1
    fi

    if [ ! -f "/etc/hysteria/traffic_data.json" ]; then
        echo "Error: /etc/hysteria/traffic_data.json not found."
        return 1
    fi

    data=$(cat /etc/hysteria/traffic_data.json)
    echo "Traffic Data:"
    echo "---------------------------------------------------------------------------"
    echo -e "User       Upload (TX)     Download (RX)          Status"
    echo "---------------------------------------------------------------------------"

    echo "$data" | jq -r 'to_entries[] | [.key, .value.upload_bytes, .value.download_bytes, .value.status] | @tsv' | while IFS=$'\t' read -r user upload_bytes download_bytes status; do
        if [ $(echo "$upload_bytes < 1073741824" | bc -l) -eq 1 ]; then
            upload=$(echo "scale=2; $upload_bytes / 1024 / 1024" | bc)
            upload_unit="MB"
        else
            upload=$(echo "scale=2; $upload_bytes / 1024 / 1024 / 1024" | bc)
            upload_unit="GB"
        fi

        if [ $(echo "$download_bytes < 1073741824" | bc -l) -eq 1 ]; then
            download=$(echo "scale=2; $download_bytes / 1024 / 1024" | bc)
            download_unit="MB"
        else
            download=$(echo "scale=2; $download_bytes / 1024 / 1024 / 1024" | bc)
            download_unit="GB"
        fi

        printf "${yellow}%-15s ${cyan}%-15s ${green}%-15s ${NC}%-10s\n" "$user" "$(printf "%.2f%s" "$upload" "$upload_unit")" "$(printf "%.2f%s" "$download" "$download_unit")" "$status"
        echo "---------------------------------------------------------------------------"
    done
}

# TODO: remove 
# Function to restart Hysteria2 service
restart_hysteria_service() {
    python3 /etc/hysteria/traffic.py >/dev/null 2>&1
    systemctl restart hysteria-server.service
}

# Function to modify users
modify_users() {
    modify_script="/etc/hysteria/users/modify.py"
    github_raw_url="https://raw.githubusercontent.com/ReturnFI/Hysteria2/main/modify.py"

    [ -f "$modify_script" ] || wget "$github_raw_url" -O "$modify_script" >/dev/null 2>&1

    python3 "$modify_script"
}

# Function to add a new user to the configuration
add_user() {
    while true; do
        read -p "Enter the username: " username

        if [[ "$username" =~ ^[a-z0-9]+$ ]]; then
            break
        else
            echo -e "\033[0;31mError:\033[0m Username can only contain lowercase letters and numbers."
        fi
    done

    read -p "Enter the traffic limit (in GB): " traffic_gb
    # Convert GB to bytes (1 GB = 1073741824 bytes)
    traffic=$((traffic_gb * 1073741824))

    read -p "Enter the expiration days: " expiration_days
    password=$(pwgen -s 32 1)
    creation_date=$(date +%Y-%m-%d)

    if [ ! -f "/etc/hysteria/users/users.json" ]; then
        echo "{}" > /etc/hysteria/users/users.json
    fi

    jq --arg username "$username" --arg password "$password" --argjson traffic "$traffic" --argjson expiration_days "$expiration_days" --arg creation_date "$creation_date" \
    '.[$username] = {password: $password, max_download_bytes: $traffic, expiration_days: $expiration_days, account_creation_date: $creation_date, blocked: false}' \
    /etc/hysteria/users/users.json > /etc/hysteria/users/users_temp.json && mv /etc/hysteria/users/users_temp.json /etc/hysteria/users/users.json

    restart_hysteria_service >/dev/null 2>&1

    echo -e "\033[0;32mUser $username added successfully.\033[0m"
}


# Function to remove a user from the configuration
remove_user() {
    if [ -f "/etc/hysteria/users/users.json" ]; then
        # Extract current users from the users.json file
        users=$(jq -r 'keys[]' /etc/hysteria/users/users.json)

        if [ -z "$users" ]; then
            echo "No users found."
            return
        fi

        # Display current users with numbering
        echo "Current users:"
        echo "-----------------"
        i=1
        for user in $users; do
            echo "$i. $user"
            ((i++))
        done
        echo "-----------------"

        read -p "Enter the number of the user to remove: " selected_number

        if ! [[ "$selected_number" =~ ^[0-9]+$ ]]; then
            echo "${red}Error:${NC} Invalid input. Please enter a number."
            return
        fi

        if [ "$selected_number" -lt 1 ] || [ "$selected_number" -gt "$i" ]; then
            echo "${red}Error:${NC} Invalid selection. Please enter a number within the range."
            return
        fi

        selected_user=$(echo "$users" | sed -n "${selected_number}p")

        jq --arg selected_user "$selected_user" 'del(.[$selected_user])' /etc/hysteria/users/users.json > /etc/hysteria/users/users_temp.json && mv /etc/hysteria/users/users_temp.json /etc/hysteria/users/users.json
        
        if [ -f "/etc/hysteria/traffic_data.json" ]; then
            jq --arg selected_user "$selected_user" 'del(.[$selected_user])' /etc/hysteria/traffic_data.json > /etc/hysteria/traffic_data_temp.json && mv /etc/hysteria/traffic_data_temp.json /etc/hysteria/traffic_data.json
        fi
        
        restart_hysteria_service >/dev/null 2>&1
        echo "User $selected_user removed successfully."
    else
        echo "${red}Error:${NC} Config file /etc/hysteria/traffic_data.json not found."
    fi
}
# Function to display the main menu
display_main_menu() {
    clear
    tput setaf 7 ; tput setab 4 ; tput bold ; printf '%40s%s%-12s\n' "◇───────────ㅤ🚀ㅤWelcome To Hysteria2 Managementㅤ🚀ㅤ───────────◇" ; tput sgr0
    echo -e "${LPurple}◇──────────────────────────────────────────────────────────────────────◇${NC}"

    echo -e "${green}• OS: ${NC}$OS           ${green}• ARCH: ${NC}$ARCH"
    echo -e "${green}• ISP: ${NC}$ISP         ${green}• CPU: ${NC}$CPU"
    echo -e "${green}• IP: ${NC}$IP                ${green}• RAM: ${NC}$RAM"

    echo -e "${LPurple}◇──────────────────────────────────────────────────────────────────────◇${NC}"

    echo -e "${yellow}                   ☼ Main Menu ☼                   ${NC}"

    echo -e "${LPurple}◇──────────────────────────────────────────────────────────────────────◇${NC}"
    echo -e "${green}[1] ${NC}↝ Hysteria2 Menu"
    echo -e "${cyan}[2] ${NC}↝ Advance Menu"
    echo -e "${red}[0] ${NC}↝ Exit"
    echo -e "${LPurple}◇──────────────────────────────────────────────────────────────────────◇${NC}"
    echo -ne "${yellow}➜ Enter your option: ${NC}"
}

# Function to handle main menu options
main_menu() {
    clear
    local choice
    while true; do
        define_colors
        get_system_info
        display_main_menu
        read -r choice
        case $choice in
            1) hysteria2_menu ;;
            2) advance_menu ;;
            0) exit 0 ;;
            *) echo "Invalid option. Please try again." ;;
        esac
        echo
        read -rp "Press Enter to continue..."
    done
}

# Function to display the Hysteria2 menu
display_hysteria2_menu() {
    clear
    echo -e "${LPurple}◇──────────────────────────────────────────────────────────────────────◇${NC}"

    echo -e "${yellow}                   ☼ Hysteria2 Menu ☼                   ${NC}"

    echo -e "${LPurple}◇──────────────────────────────────────────────────────────────────────◇${NC}"

    echo -e "${green}[1] ${NC}↝ Install and Configure Hysteria2"
    echo -e "${cyan}[2] ${NC}↝ Add User"
    echo -e "${cyan}[3] ${NC}↝ Modify User"
    echo -e "${cyan}[4] ${NC}↝ Show URI"
    echo -e "${cyan}[5] ${NC}↝ Check Traffic Status"
    echo -e "${cyan}[6] ${NC}↝ Remove User"

    echo -e "${red}[0] ${NC}↝ Back to Main Menu"

    echo -e "${LPurple}◇──────────────────────────────────────────────────────────────────────◇${NC}"

    echo -ne "${yellow}➜ Enter your option: ${NC}"
}

# Function to handle Hysteria2 menu options
hysteria2_menu() {
    clear
    local choice
    while true; do
        define_colors
        get_system_info
        display_hysteria2_menu
        read -r choice
        case $choice in
            1) install_and_configure ;;
            2) add_user ;;
            3) modify_users ;;
            4) show_uri ;;
            5) traffic_status ;;
            6) remove_user ;;
            0) return ;;
            *) echo "Invalid option. Please try again." ;;
        esac
        echo
        read -rp "Press Enter to continue..."
    done
}

# Function to handle Advance menu options
advance_menu() {
    clear
    local choice
    while true; do
        define_colors
        display_advance_menu
        read -r choice
        case $choice in
            1) install_tcp_brutal ;;
            2) install_warp ;;
            3) configure_warp ;;
            4) uninstall_warp ;;
            5) change_port ;;
            6) update_core ;;
            7) uninstall_hysteria ;;
            0) return ;;
            *) echo "Invalid option. Please try again." ;;
        esac
        echo
        read -rp "Press Enter to continue..."
    done
}

# Function to get Advance menu
display_advance_menu() {
    clear
    echo -e "${LPurple}◇──────────────────────────────────────────────────────────────────────◇${NC}"
    echo -e "${yellow}                   ☼ Advance Menu ☼                   ${NC}"
    echo -e "${LPurple}◇──────────────────────────────────────────────────────────────────────◇${NC}"
    echo -e "${green}[1] ${NC}↝ Install TCP Brutal"
    echo -e "${green}[2] ${NC}↝ Install WARP"
    echo -e "${cyan}[3] ${NC}↝ Configure WARP"
    echo -e "${red}[4] ${NC}↝ Uninstall WARP"
    echo -e "${cyan}[5] ${NC}↝ Change Port Hysteria2"
    echo -e "${cyan}[6] ${NC}↝ Update Core Hysteria2"
    echo -e "${red}[7] ${NC}↝ Uninstall Hysteria2"
    echo -e "${red}[0] ${NC}↝ Back to Main Menu"
    echo -e "${LPurple}◇──────────────────────────────────────────────────────────────────────◇${NC}"
    echo -ne "${yellow}➜ Enter your option: ${NC}"
}

# Main function to run the script
main() {
    main_menu
}

# Run the main function
main
