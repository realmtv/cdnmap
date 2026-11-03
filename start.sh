#!/bin/bash

echo "=========================================="
echo "   cdnmap Production Setup & Deployment   "
echo "=========================================="

ENV_FILE=".env"
SSH_KEY="/root/.ssh/id_rsa"
PUB_KEY="${SSH_KEY}.pub"

# 1. Check & Install Docker / Docker Compose if missing
if ! command -v docker &> /dev/null || ! docker compose version &> /dev/null; then
    echo "[*] Docker or Docker Compose not found. Attempting automatic installation..."
    if [ -f /etc/debian_version ]; then
        sudo apt-get update
        sudo apt-get install -y ca-certificates curl gnupg lsb-release
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://docker.com | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://docker.com $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        sudo systemctl start docker
        sudo systemctl enable docker
        echo "[+] Docker environment successfully installed!"
    else
        echo "[-] Error: Unsupported OS. Please install Docker & Docker Compose manually."
        exit 1
    fi
fi

# 2. Check & Generate Automated SSH Keys
if [ ! -f "$SSH_KEY" ]; then
    echo "[*] Private SSH key not found. Generating an automated key pair..."
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    ssh-keygen -t rsa -b 2048 -f "$SSH_KEY" -N "" -q
    chmod 600 "$SSH_KEY"
    echo "[+] SSH key pair successfully generated."
    
    echo "--------------------------------------------------------"
    echo "⚠️  CRITICAL STEP REQUIRED FOR MIKROTIK AUTHENTICATION:"
    echo "Please run the following command on your MikroTik terminal"
    echo "to import the public key for userless authentication:"
    echo "--------------------------------------------------------"
    echo "/file print file=cdnmap_key.pub; /file set cdnmap_key.pub contents=\"$(cat $PUB_KEY)\"; /user ssh-keys import file=cdnmap_key.pub user=YOUR_MIKROTIK_USER"
    echo "--------------------------------------------------------"
    read -p "Press [Enter] once you have noted or applied the key import..."
fi

# 3. Interactive Credentials Setup
if [ ! -f "$ENV_FILE" ]; then
    echo "[*] Creating new local environment config..."
    
    read -p "Enter your MikroTik IP Address [e.g. 192.168.88.1]: " m_ip
    read -p "Enter your MikroTik SSH Username [e.g. admin]: " m_user
    
    if [ -z "$m_ip" ] || [ -z "$m_user" ]; then
        echo "[-] Error: Credentials cannot be empty!"
        exit 1
    fi
    
    cat << EOF > "$ENV_FILE"
MIKROTIK_IP=$m_ip
MIKROTIK_USER=$m_user
EOF
    echo "[+] Configuration saved locally to $ENV_FILE"
else
    echo "[+] Existing configuration found in $ENV_FILE"
fi

echo "[+] Preparing deployment environment..."

# 4. Fix Windows line endings (CRLF -> LF) for deployment scripts
if [ -f "entrypoint.sh" ]; then
    sed -i 's/\r$//' entrypoint.sh
    chmod +x entrypoint.sh
    echo "[+] entrypoint.sh optimized and made executable."
else
    echo "[-] Error: entrypoint.sh not found!"
    exit 1
fi

# 5. Launch or rebuild the Docker infrastructure
echo "[+] Launching cdnmap production daemon via Docker Compose..."
docker compose up -d --build

echo "[+] Deployment triggered successfully!"
echo "[+] To view live logs in real time, run: docker compose logs -f"
echo "=========================================="