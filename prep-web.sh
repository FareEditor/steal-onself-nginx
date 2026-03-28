#!/bin/bash

# Exit on any error
set -e

echo -e "\n========================================================================"
echo "This script is part of the article: https://docs.fareeditor.com/vless-steal-onself"
echo "For the full profit and complete understanding, please read it first."
echo -e "========================================================================\n"

echo "Detecting external IP address..."
SERVER_IP=$(curl -s https://api.ipify.org || curl -s https://ifconfig.me)

if [ -z "$SERVER_IP" ]; then
    echo "Error: Failed to determine external IP address."
    exit 1
fi

echo -e "\nCurrent external server IP: \033[1;32m$SERVER_IP\033[0m\n"

read -p "Enter the domain to be used (e.g., example.com): " DOMAIN

if [ -z "$DOMAIN" ]; then
    echo "Domain cannot be empty. Exiting."
    exit 1
fi

read -p "Is the A record for $DOMAIN pointing to IP $SERVER_IP? (y/n): " A_RECORD_CONFIRM

if [[ "$A_RECORD_CONFIRM" != "y" && "$A_RECORD_CONFIRM" != "Y" ]]; then
    echo "Please configure the A record with your DNS provider, wait for DNS propagation, and run the script again."
    exit 1
fi

echo -e "\nStarting package installation and configuration...\n"

# Step 1: Update and install packages
apt update && apt upgrade -y
apt install curl nginx certbot python3-certbot-nginx -y

# Create webroot directory if it doesn't exist and set permissions
mkdir -p /var/www/html
chown -R www-data:www-data /var/www/html

# Temporary Nginx config for Certbot (HTTP-01) challenge
cat <<EOF > /etc/nginx/sites-available/default
server {
    listen 80 default_server;
    server_name $DOMAIN;
    root /var/www/html;
    index index.html;
}
EOF

systemctl restart nginx

# Request certificate in non-interactive mode
certbot certonly --webroot -w /var/www/html -d $DOMAIN --register-unsafely-without-email --agree-tos --non-interactive

# Step 2: Final Nginx config (Steal Oneself)
# Note the escaping of Nginx variables (\$host, \$request_uri, \$uri)
cat <<EOF > /etc/nginx/sites-available/default
server {
    listen 80;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 127.0.0.1:8443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    root /var/www/html;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

# Test Nginx syntax and restart
nginx -t
systemctl restart nginx

echo -e "\n\033[1;32mDone! Nginx and certificates have been successfully configured.\033[0m"