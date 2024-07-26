#!/bin/bash

config_file="/etc/haproxy/haproxy.cfg"
backup_file="/etc/haproxy/haproxy.cfg.bak"

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root"
        exit 1
    fi
}

install_haproxy() {
    echo "Installing HAProxy..."
    sudo apt-get update
    sudo apt-get install -y haproxy
    echo "HAProxy installed."
    default_config
}

default_config() {
    cat <<EOL > $config_file
global
    # log /dev/log    local0
    # log /dev/log    local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    # log     global
    mode    tcp
    # option  tcplog
    option  dontlognull
    timeout connect 5000
    timeout client  50000
    timeout server  50000
EOL
}

generate_haproxy_config() {
    local ports=($1)
    local target_ips=($2)
    local config_file="/etc/haproxy/haproxy.cfg"

    echo "Generating HAProxy configuration..."

    for port in "${ports[@]}"; do
        cat <<EOL >> $config_file

frontend frontend_$port
    bind *:$port
    default_backend backend_$port

backend backend_$port
EOL
        for i in "${!target_ips[@]}"; do
            if [ $i -eq 0 ]; then
                cat <<EOL >> $config_file
    server server$(($i+1)) ${target_ips[$i]}:$port check
EOL
            else
                cat <<EOL >> $config_file
    server server$(($i+1)) ${target_ips[$i]}:$port check backup
EOL
            fi
        done
    done

    echo "HAProxy configuration generated at $config_file"
}

add_ip_ports() {
    read -p "Enter the IPs to forward to (use comma , to separate multiple IPs): " user_ips
    IFS=',' read -r -a ips_array <<< "$user_ips"
    read -p "Enter the ports (use comma , to separate): " user_ports
    IFS=',' read -r -a ports_array <<< "$user_ports"
    generate_haproxy_config "${ports_array[*]}" "${ips_array[*]}"

    if haproxy -c -f /etc/haproxy/haproxy.cfg; then
        echo "Restarting HAProxy service..."
        service haproxy restart
        echo "HAProxy configuration updated and service restarted."
    else
        echo "HAProxy configuration is invalid. Please check the configuration file."
    fi
}

clear_configs() {
    echo "Creating a backup of the HAProxy configuration..."
    cp $config_file $backup_file

    if [ $? -ne 0 ]; then
        echo "Failed to create a backup. Aborting."
        return
    fi

    echo "Clearing IP and port configurations from HAProxy configuration..."

    awk '
    /^frontend frontend_/ {skip = 1}
    /^backend backend_/ {skip = 1}
    skip {if (/^$/) {skip = 0}; next}
    {print}
    ' $backup_file > $config_file

    echo "Clearing IP and port configurations from $config_file."
    
    echo "Stopping HAProxy service..."
    sudo service haproxy stop
    
    if [ $? -eq 0 ]; then
        echo "HAProxy service stopped."
    else
        echo "Failed to stop HAProxy service."
    fi

    echo "Done!"
}

remove_haproxy() {
    echo "Removing HAProxy..."
    sudo apt-get remove --purge -y haproxy
    sudo apt-get autoremove -y
    echo "HAProxy removed."
}

check_root

while true; do
    sleep 1.5
    echo "Select an option:"
    echo "1) Install HAProxy"
    echo "2) Add IPs and Ports to Forward"
    echo "3) Clear Configurations"
    echo "4) Remove HAProxy Completely"
    echo "9) Back"
    read -p "Select a Number : " choice

    case $choice in
        1)
            install_haproxy
            ;;
        2)
            add_ip_ports
            ;;
        3)
            clear_configs
            ;;
        4)
            remove_haproxy
            ;;
        9)
            echo "Exiting..."
            break
            ;;
        *)
            echo "Invalid option. Please try again."
            ;;
    esac
done