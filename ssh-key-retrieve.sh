#!/bin/bash

# Load configuration from config.env file
source config.env

# Configuration
CONFIG_FILE="hosts.json"
SSH_KEYS_DIR="ssh_keys"
LOG_FILE="setup_ssh_keys_log_$(date +%Y%m%d%H%M%S).log"

mkdir -p "$SSH_KEYS_DIR"

# Generate a private/public key pair per host locally if missing
generate_ssh_key_local() {
    local host=$1
    local priv_key="$SSH_KEYS_DIR/$host"
    local pub_key="$priv_key.pub"

    if [ ! -f "$priv_key" ]; then
        echo "Generating SSH key pair for $host locally..." | tee -a "$LOG_FILE"
        ssh-keygen -t rsa -b 2048 -N "" -f "$priv_key" -q
        chmod 600 "$priv_key"
    else
        echo "SSH key for $host already exists locally." | tee -a "$LOG_FILE"
    fi
}

# Copy public key to remote host's authorized_keys using sshpass
copy_public_key_to_host() {
    local host=$1
    local password=$2
    local pub_key_file="$SSH_KEYS_DIR/$host.pub"

    echo "Copying public key to $host..." | tee -a "$LOG_FILE"

    sshpass -p "$password" ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$host" bash -c "'
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh
        echo \"$(cat "$pub_key_file")\" >> ~/.ssh/authorized_keys
        chmod 600 ~/.ssh/authorized_keys
    '" 2>>"$LOG_FILE"

    if [ $? -eq 0 ]; then
        echo "Public key copied to $host successfully." | tee -a "$LOG_FILE"
        return 0
    else
        echo "Failed to copy public key to $host" | tee -a "$LOG_FILE"
        return 1
    fi
}

# Main process
count=0
while read -r host_config; do
    host=$(jq -r '.host' <<< "$host_config")
    password=$(jq -r '.password' <<< "$host_config")

    echo "Processing host $host..." | tee -a "$LOG_FILE"
    if [ -z "$host" ] || [ -z "$password" ]; then
        echo "Skipping host with empty host or password." | tee -a "$LOG_FILE"
        continue
    fi

    generate_ssh_key_local "$host"
    if copy_public_key_to_host "$host" "$password"; then
        ((count++))
    else
        echo "Error during public key setup on $host" | tee -a "$LOG_FILE"
    fi
done < <(jq -c '.[]' "$CONFIG_FILE")

echo "Done. Successfully set up SSH keys for $count host(s). See $LOG_FILE for details."
