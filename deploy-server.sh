#!/usr/bin/env bash

# This script sets the shell to exit immediately if any command fails.
set -e

# =================================================================
# Usage Information Function:
# Displays script usage instructions and available parameters
# Called when -h flag is used or when required parameters are missing
# =================================================================
usage() {
    echo "Usage: $0 -u username -k ssh_public_key [-h] [-p port]"
    echo "  -u : Username to create (main admin user, SSH key access only)"
    echo "  -k : SSH public key for the admin user"
    echo "  -p : SSH port (default: 22)"
    echo "  -h : Display this help message"
    exit 1
}

# =================================================================
# Print Box Function:
# Prints a box around the provided text
# =================================================================
BOX_WIDTH=50

start_box() {
    local text="$1"
    local BOX_WIDTH=${#text}
    local border=$(printf '%*s' "$BOX_WIDTH" | tr ' ' '*')
    echo -e "\n$border\n\n$text\n"
}

end_box() {
    local border=$(printf '%*s' "$BOX_WIDTH" | tr ' ' '*')
    echo -e "$border\n"
}

# =================================================================
# Wait for user input:
# Waits for user to press Enter before proceeding
# =================================================================
wait_for_user() {
    local question="$1"
    if [[ -z "$question" ]]; then
        question="Press any key to continue..."
    fi

    echo -e "\n$question\n"

    local confirm_key="${2-y}"
    local abort_key="${3-n}"

    echo "Press the '$confirm_key' key proceed..."
    echo "Press '$abort_key' to exit the program."
    while true; do
    # Read a single character from the input
    read -n 1 key
    # Check if the pressed key is 'q'
    if [[ $key == "y" ]]; then
        echo "\nProceeding..."
        break
    elif [[ $key == "$abort_key" ]]; then
        echo -e "\nExiting..."
        exit 1
    else
        echo -e "\nInvalid key. Please press '$confirm_key' to proceed or '$abort_key' to exit."
        continue
    fi
    done
}

SSH_PORT=22

# =================================================================
# Default Values:
# Sets default values for optional parameters
# =================================================================
while getopts u:k:h: option
do
    case "${option}"
        in
        u) USERNAME=${OPTARG};;
        k) SSH_PUBLIC_KEY=${OPTARG};;
        p) SSH_PORT=${OPTARG};;
        h) usage;;
        *) usage;;
    esac
done

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    start_box "This script must be run as root or with sudo."
    end_box
    exit 1
fi

# update package list and upgrade installed packages
# apt update && apt upgrade -y

# # Installing necessary packages
# start_box "Installing necessary packages..."
# apt install -y \
#     vim \
#     curl  \
#     wget  \
#     git  \
#     htop  \
#     unzip  \
#     net-tools \
#     fail2ban \
#     ufw

# end_box

# add admin user with SSH key access
start_box "Creating user $USERNAME..."

adduser --disabled-password --gecos "" "$USERNAME"
mkdir -p "/home/$USERNAME/.ssh"
echo "$SSH_PUBLIC_KEY" > "/home/$USERNAME/.ssh/authorized_keys"
chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.ssh"
chmod 700 "/home/$USERNAME/.ssh"
chmod 600 "/home/$USERNAME/.ssh/authorized_keys"

# add user to sudo group
usermod -aG sudo "$USERNAME"

echo "User $USERNAME created and configured with SSH key access."
end_box

wait_for_user "Can you login with the new user? (y/n)" "y" "n"

# Configure sshd_config
start_box "Configuring SSH daemon..."

# Backup the original sshd_config file
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bu

sed -i.bu "s/#Port 22/Port $SSH_PORT/" /etc/ssh/sshd_config
sed -i.bu -E 's/^#?PermitRootLogin (yes|no)/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sed -i.bu "s/#PasswordAuthentication yes/PasswordAuthentication no/" /etc/ssh/sshd_config
sed -i.bu "s/#PubkeyAuthentication yes/PubkeyAuthentication yes/" /etc/ssh/sshd_config
sed -i.bu "s/#PermitEmptyPasswords no/PermitEmptyPasswords no/" /etc/ssh/sshd_config

# set AllowTcpForwarding
sed -i.bu "s/#AllowAgentForwarding yes/AllowAgentForwarding no/" /etc/ssh/sshd_config
sed -i.bu "s/#AllowTcpForwarding yes/AllowTcpForwarding no/" /etc/ssh/sshd_config
sed -i.bu "s/#X11Forwarding yes/X11Forwarding no/" /etc/ssh/sshd_config

echo "SSH daemon configured. Restarting SSH service..."
systemctl restart ssh
end_box

# Configure UFW
start_box "Configuring UFW..."

# Enable UFW and set default policies
ufw default deny incoming
ufw default allow outgoing

# Allow SSH connections
ufw allow "$SSH_PORT"/tcp

# Allow HTTP and HTTPS connections
ufw allow 80/tcp
ufw allow 443/tcp

ufw enable
ufw status

echo "UFW configured and enabled."
end_box

# install necessary packages
start_box "Configuring fail2ban..."

cat > /etc/fail2ban/jail.local << EOF
[sshd]
enabled = true
port = $SSH_PORT
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 600
EOF

# Install fail2ban
systemctl restart fail2ban
echo "Fail2ban installed and configured."

end_box

# Install auto security updates

start_box "Installing and configuring unattended-upgrades..."

sudo apt install -y unattended-upgrades

sudo dpkg-reconfigure --priority=low unattended-upgrades
cat /etc/apt/apt.conf.d/20auto-upgrades

echo "Unattended upgrades installed and configured."
end_box
