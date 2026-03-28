#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

echo -e "\n========================================================================"
echo "This script is part of the article: https://docs.fareeditor.com/vless-steal-onself"
echo "For the full profit and complete understanding, please read it first."
echo -e "========================================================================\n"

# 1. Install prerequisites for DNS verification
if ! command -v dig &> /dev/null; then
    echo "Installing dnsutils for DNS verification..."
    apt update -y && apt install -y dnsutils
fi

# 2. Detect External IP address
echo "Detecting external IP address..."
SERVER_IP=$(curl -s https://api.ipify.org || curl -s https://ifconfig.me)

if [ -z "$SERVER_IP" ]; then
    echo "Error: Failed to determine external IP address."
    exit 1
fi

echo -e "Current server IP: \033[1;32m$SERVER_IP\033[0m"

# 3. Request Domain and verify A-record
read -p "Enter your domain (e.g., paris.vps.private.fareeditor.com): " DOMAIN

if [ -z "$DOMAIN" ]; then
    echo "Domain cannot be empty. Exiting."
    exit 1
fi

echo "Verifying DNS records for $DOMAIN..."
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

# 4. Install Web Server and Certbot
echo "Installing Nginx and Certbot..."
apt update && apt upgrade -y
apt install -y curl nginx certbot python3-certbot-nginx

# Prepare webroot directory
mkdir -p /var/www/html
chown -R www-data:www-data /var/www/html

# 5. Configure temporary Nginx for Let's Encrypt HTTP-01 challenge
cat <<EOF > /etc/nginx/sites-available/default
server {
    listen 80 default_server;
    server_name $DOMAIN;
    root /var/www/html;
    index index.html;
}
EOF

systemctl restart nginx

# 6. Obtain SSL Certificate
echo "Obtaining SSL certificate via Certbot..."
certbot certonly --webroot -w /var/www/html -d $DOMAIN --register-unsafely-without-email --agree-tos --non-interactive

# 7. Final Nginx configuration (Steal Oneself approach)
# Nginx listens on local port 8443 with SSL to serve as a REALITY fallback
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

# Verify and apply Nginx config
nginx -t
systemctl restart nginx

# 8. Setup Automation: Systemd Timer for Auto-Renewal (every 75 days)
echo "Setting up Systemd Timer for SSL auto-renewal and Nginx reload..."

# Create the service unit
cat <<EOF > /etc/systemd/system/reality-renew.service
[Unit]
Description=Renew Certificates and Reload Nginx for REALITY
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/certbot renew --quiet
ExecStartPost=/usr/bin/systemctl reload nginx
EOF

# Create the timer unit
cat <<EOF > /etc/systemd/system/reality-renew.timer
[Unit]
Description=Run reality-renew.service every 75 days

[Timer]
OnUnitActiveSec=75d
OnBootSec=15min
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Enable and start the timer
systemctl daemon-reload
systemctl enable --now reality-renew.timer

echo -e "\n\033[1;32mDone! Web server and SSL certificates are ready.\033[0m"
echo -e "Internal verification check:"
curl -s -I --resolve $DOMAIN:8443:127.0.0.1 https://$DOMAIN:8443 | grep "HTTP/" || echo "Warning: Internal check failed, check Nginx logs."