#!/bin/bash

# Exit on any error
set -e

echo -e "\n========================================================================"
echo "This script is part of the article: https://docs.fareeditor.com/vless-steal-onself"
echo "For the full profit and complete understanding, please read it first."
echo -e "========================================================================\n"

# Install dnsutils if dig is missing
if ! command -v dig &> /dev/null; then
    echo "Installing dnsutils for DNS verification..."
    apt update -y && apt install -y dnsutils
fi

echo "Detecting external IP address..."
SERVER_IP=$(curl -s https://api.ipify.org || curl -s https://ifconfig.me)

if [ -z "$SERVER_IP" ]; then
    echo "Error: Failed to determine external IP address."
    exit 1
fi

echo -e "Current server IP: \033[1;32m$SERVER_IP\033[0m"

read -p "Enter your domain (e.g., example.com): " DOMAIN

if [ -z "$DOMAIN" ]; then
    echo "Domain cannot be empty. Exiting."
    exit 1
fi

echo "Verifying DNS records for $DOMAIN..."

# Perform DNS lookup
RESOLVED_IP=$(dig +short "$DOMAIN" | tail -n1)

if [ -z "$RESOLVED_IP" ]; then
    echo -e "\033[1;31mError: Could not resolve domain $DOMAIN. Check your DNS settings.\033[0m"
    exit 1
fi

if [ "$RESOLVED_IP" != "$SERVER_IP" ]; then
    echo -e "\033[1;31mIP Mismatch!\033[0m"
    echo "Domain $DOMAIN resolves to: $RESOLVED_IP"
    echo "But your server IP is: $SERVER_IP"
    echo "Please update your A record and wait for DNS propagation."
    exit 1
else
    echo -e "\033[1;32mSuccess! Domain $DOMAIN correctly points to $SERVER_IP.\033[0m\n"
fi

echo "Starting package installation and configuration..."

# Step 1: Install Nginx and Certbot
apt update && apt upgrade -y
apt install -y curl nginx certbot python3-certbot-nginx

mkdir -p /var/www/html
chown -R www-data:www-data /var/www/html

# Temporary Nginx config for Certbot
cat <<EOF > /etc/nginx/sites-available/default
server {
    listen 80 default_server;
    server_name $DOMAIN;
    root /var/www/html;
    index index.html;
}
EOF

systemctl restart nginx

# Request certificate
certbot certonly --webroot -w /var/www/html -d $DOMAIN --register-unsafely-without-email --agree-tos --non-interactive

# Step 2: Final Nginx config (Steal Oneself)
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

nginx -t
systemctl restart nginx

echo -e "\n\033[1;32mDone! Web server and SSL certificates are ready for REALITY.\033[0m"