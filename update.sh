#!/bin/bash

# Resolve script directory
export TZ=Europe/Helsinki
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration from config.env file
source "$SCRIPT_DIR/config.env"

# Configuration
CONFIG_FILE="$SCRIPT_DIR/hosts.json"
SSH_KEYS_DIR="$SCRIPT_DIR/ssh_keys"
LOG_FILE="$SCRIPT_DIR/logs/update_log_$(date +%Y%m%d%H%M%S).log"

# Function to update a single host using SSH keys
update_host() {
    local host=$1
    local username=$2
    local ssh_key_file="$SSH_KEYS_DIR/$host"

    if [ ! -f "$ssh_key_file" ]; then
        # Try with .key and .pem extensions
        if [ -f "$ssh_key_file.key" ]; then
            ssh_key_file="$ssh_key_file.key"
        elif [ -f "$ssh_key_file.pem" ]; then
            ssh_key_file="$ssh_key_file.pem"
        else
            echo "No SSH key found for $host. Please run the key retrieval script first." | tee -a "$LOG_FILE"
            return 1
        fi
    fi

    echo "Using SSH key to update $host ($ssh_key_file)..." | tee -a "$LOG_FILE"
    ssh -n -i "$ssh_key_file" -o StrictHostKeyChecking=no $username@"$host" '
    # Determine if we need sudo
    if [ "$username" != "root" ]; then
        SUDO="sudo"
    else
        SUDO=""
    fi


    if command -v apt >/dev/null 2>&1; then
        echo "Using apt"
        $SUDO apt update -qq \
            && $SUDO apt full-upgrade -y -qq \
            && $SUDO apt autoremove -y -qq
    elif command -v paru >/dev/null 2>&1; then
        echo "Using paru"
        $SUDO paru -Syu --noconfirm
    elif command -v pacman >/dev/null 2>&1; then
        echo "Using pacman"
        $SUDO pacman -Syu --noconfirm
    elif command -v dnf >/dev/null 2>&1; then
        echo "Using dnf"
        $SUDO dnf upgrade --refresh -y
    elif command -v zypper >/dev/null 2>&1; then
        echo "Using zypper"
        $SUDO zypper refresh \
            && $SUDO zypper update -y
    elif command -v apk >/dev/null 2>&1; then
        echo "Using apk"
        $SUDO apk update \
            && $SUDO apk upgrade
    else
        echo "No known package manager found"
        exit 1
    fi
    ' | tee -a "$LOG_FILE"
}

update_minecraft_server(){
    local ssh_key="$SSH_KEYS_DIR/minecraft"
    local username="$Minecraft_username"

    echo "Updating Minecraft Server..." | tee -a "$LOG_FILE"
    echo "password:dijmCeOWTTZf6Q52a3l2"
    ssh -i "$ssh_key" -o StrictHostKeyChecking=no $username@10.10.69.15 '
    echo "dijmCeOWTTZf6Q52a3l2" | sudo -S systemctl stop crafty
    /var/opt/minecraft/crafty/update_crafty.sh
    echo "dijmCeOWTTZf6Q52a3l2" | sudo -S systemctl start crafty
    ' | tee -a "$LOG_FILE"
}

# Function to update the local host
update_local_host() {
    echo "Updating local host..." | tee -a "$LOG_FILE"
    if command -v apt >/dev/null 2>&1; then
        echo "Using apt" | tee -a "$LOG_FILE"
        sudo apt update && sudo apt full-upgrade -y && sudo apt autoremove -y | tee -a "$LOG_FILE"
    elif command -v paru >/dev/null 2>&1; then
        echo "Using paru" | tee -a "$LOG_FILE"
        paru -Syu --noconfirm | tee -a "$LOG_FILE"
    elif command -v pacman >/dev/null 2>&1; then
        echo "Using pacman" | tee -a "$LOG_FILE"
        sudo pacman -Syu --noconfirm | tee -a "$LOG_FILE"
    elif command -v dnf >/dev/null 2>&1; then
        echo "Using dnf" | tee -a "$LOG_FILE"
        sudo dnf upgrade --refresh -y | tee -a "$LOG_FILE"
    elif command -v zypper >/dev/null 2>&1; then
        echo "Using zypper" | tee -a "$LOG_FILE"
        sudo zypper refresh && sudo zypper update -y | tee -a "$LOG_FILE"
    elif command -v apk >/dev/null 2>&1; then
        echo "Using apk" | tee -a "$LOG_FILE"
        sudo apk update && sudo apk upgrade -y | tee -a "$LOG_FILE"
    else
        echo "No known package manager found" | tee -a "$LOG_FILE"
        exit 1
    fi
}

# Check if SSH keys directory exists and contains keys
if [ ! -d "$SSH_KEYS_DIR" ] || [ -z "$(ls -A "$SSH_KEYS_DIR")" ]; then
    echo "SSH keys directory does not exist or is empty. Please run the key retrieval script first." | tee -a "$LOG_FILE"
    exit 1
fi

# Update the local host
update_local_host

#update minecraft server
update_minecraft_server

# Read the JSON configuration file and update each host
jq -c '.[]' "$CONFIG_FILE" | while read -r host_config; do
    host=$(jq -r '.host' <<< "$host_config")
    username=$(jq -r '.username' <<< "$host_config")
    update_host "$host" "$username"
done

# Upload log to Pastebin and get URL
PASTE_URL=$(curl --silent --request POST \
    --data-urlencode "api_dev_key=$PASTEBIN_API_KEY" \
    --data-urlencode "api_option=paste" \
    --data-urlencode "api_paste_code=$(cat "$LOG_FILE")" \
    --data-urlencode "api_paste_private=1" \
    --data-urlencode "api_paste_format=bash" \
    --data-urlencode "api_user_key=$PASTEBIN_USER_KEY" \
    --data-urlencode "api_folder_key=updater" \
    --data-urlencode "api_paste_name=proxmox-update-log_$(date +%Y%m%d%H%M%S)" \
    --data-urlencode "api_paste_expire_date=1W" \
    https://pastebin.com/api/api_post.php)

# Send Discord webhook
MESSAGE="Proxmox update completed. Logs: $PASTE_URL"
curl -H "Content-Type: application/json" \
    -X POST \
    -d "{\"content\":\"$MESSAGE\"}" \
    "$DISCORD_WEBHOOK_URL"

echo "Update process completed and log sent to Discord."
