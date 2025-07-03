#!/bin/bash

# Resolve script directory
export TZ=Europe/Helsinki
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration from config.env file
source "$SCRIPT_DIR/config.env"

# Configuration
CONFIG_FILE="$SCRIPT_DIR/hosts.json"
SSH_KEYS_DIR="$SCRIPT_DIR/ssh_keys"
LOG_FILE="$SCRIPT_DIR/update_log_$(date +%Y%m%d%H%M%S).log"

# Function to update a single host using SSH keys
update_host() {
    local host=$1
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
    ssh -n -i "$ssh_key_file" -o StrictHostKeyChecking=no root@"$host" '
    if command -v apt >/dev/null 2>&1; then
        echo "Using apt"
        apt update && apt full-upgrade -y
    elif command -v paru >/dev/null 2>&1; then
        echo "Using paru"
        paru -Syu --noconfirm
    elif command -v pacman >/dev/null 2>&1; then
        echo "Using pacman"
        pacman -Syu --noconfirm
    elif command -v dnf >/dev/null 2>&1; then
        echo "Using dnf"
        dnf upgrade --refresh -y
    elif command -v zypper >/dev/null 2>&1; then
        echo "Using zypper"
        zypper refresh && zypper update -y
    else
        echo "No known package manager found"
        exit 1
    fi
    ' | tee -a "$LOG_FILE"
}

# Function to update the local host
update_local_host() {
    echo "Updating local host..." | tee -a "$LOG_FILE"
    if command -v apt >/dev/null 2>&1; then
        echo "Using apt" | tee -a "$LOG_FILE"
        sudo apt update && sudo apt full-upgrade -y | tee -a "$LOG_FILE"
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

# Read the JSON configuration file and update each host
jq -c '.[]' "$CONFIG_FILE" | while read -r host_config; do
    host=$(jq -r '.host' <<< "$host_config")
    update_host "$host"
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
    https://pastebin.com/api/api_post.php)

# Send Discord webhook
MESSAGE="Proxmox update completed. Logs: $PASTE_URL"
curl -H "Content-Type: application/json" \
    -X POST \
    -d "{\"content\":\"$MESSAGE\"}" \
    "$DISCORD_WEBHOOK_URL"

echo "Update process completed and log sent to Discord."
