#!/bin/bash

# sysadmin.sh
# Usage:
#   ./sysadmin.sh install   - Installs Apache, Node.js, MariaDB with required configurations
#   ./sysadmin.sh uninstall - Uninstalls the above components (safe, no data loss)
#   Log file: log.txt

LOG_FILE="log.txt"
VHOST_DOMAIN="unilab.au"
VHOST_DIR="/var/www/html/${VHOST_DOMAIN}"
NODE_APP="/opt/hellonode"
NODE_SERVICE="/etc/systemd/system/nodeapp.service"

function log_action() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $USER - $1" >> "$LOG_FILE"
}

function install_apache() {
    echo "[*] Installing Apache Web Server..."
    apt-get update -y
    apt-get install apache2 -y

    mkdir -p "${VHOST_DIR}"
    echo "Hello World from Apache!" > "${VHOST_DIR}/index.html"

    # Apache virtual host configuration
    cat <<EOF > /etc/apache2/sites-available/${VHOST_DOMAIN}.conf
<VirtualHost *:3001>
    ServerName ${VHOST_DOMAIN}
    DocumentRoot ${VHOST_DIR}
    ErrorLog \${APACHE_LOG_DIR}/${VHOST_DOMAIN}_error.log
    CustomLog \${APACHE_LOG_DIR}/${VHOST_DOMAIN}_access.log combined
</VirtualHost>
EOF

    echo "[*] Updating /etc/hosts..."
    grep -q "${VHOST_DOMAIN}" /etc/hosts || echo "127.0.0.1 ${VHOST_DOMAIN}" >> /etc/hosts

    echo "[*] Configuring Apache to listen on port 3001..."
    grep -q "Listen 3001" /etc/apache2/ports.conf || echo "Listen 3001" >> /etc/apache2/ports.conf

    a2ensite "${VHOST_DOMAIN}.conf"
    systemctl reload apache2
    systemctl enable apache2
    systemctl restart apache2
    log_action "Apache installed and configured"
}

function install_nodejs() {
    echo "[*] Installing Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
    apt-get install -y nodejs

    mkdir -p "$NODE_APP"
    cat <<EOF > "$NODE_APP/server.js"
const http = require('http');
const hostname = '0.0.0.0';
const port = 8080;
const server = http.createServer((req, res) => {
  res.statusCode = 200;
  res.setHeader('Content-Type', 'text/plain');
  res.end('Hello World from Node.js\\n');
});
server.listen(port, hostname, () => {
  console.log(\`Server running at http://\${hostname}:\${port}/\`);
});
EOF

    npm install -g

    cat <<EOF > "$NODE_SERVICE"
[Unit]
Description=Node.js Hello World Server
After=network.target

[Service]
ExecStart=/usr/bin/node $NODE_APP/server.js
Restart=always
User=nobody
Group=nogroup
Environment=PATH=/usr/bin:/usr/local/bin
Environment=NODE_ENV=production
WorkingDirectory=$NODE_APP

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reexec
    systemctl daemon-reload
    systemctl enable nodeapp
    systemctl start nodeapp
    log_action "Node.js installed with sample app"
}

function install_mariadb() {
    echo "[*] Installing MariaDB..."
    apt-get install mariadb-server -y
    systemctl enable mariadb
    systemctl start mariadb
    log_action "MariaDB installed"
}

function uninstall_all() {
    echo "[*] Uninstalling Apache..."
    a2dissite "${VHOST_DOMAIN}.conf"
    rm -f "/etc/apache2/sites-available/${VHOST_DOMAIN}.conf"
    sed -i "/Listen 3001/d" /etc/apache2/ports.conf
    systemctl reload apache2
    apt-get remove --purge apache2 -y
    apt-get autoremove -y
    rm -rf "$VHOST_DIR"
    sed -i "/${VHOST_DOMAIN}/d" /etc/hosts

    echo "[*] Uninstalling Node.js..."
    systemctl stop nodeapp
    systemctl disable nodeapp
    rm -f "$NODE_SERVICE"
    rm -rf "$NODE_APP"
    apt-get remove --purge nodejs -y
    apt-get autoremove -y

    echo "[*] Uninstalling MariaDB..."
    systemctl stop mariadb
    systemctl disable mariadb
    apt-get remove --purge mariadb-server -y
    apt-get autoremove -y

    log_action "All components uninstalled"
}

function main() {
    if [[ $EUID -ne 0 ]]; then
        echo "Please run as root."
        exit 1
    fi

    if [[ "$1" == "install" ]]; then
        log_action "Starting installation..."
        install_apache
        install_nodejs
        install_mariadb
        echo "Installation complete."
    elif [[ "$1" == "uninstall" ]]; then
        log_action "Starting uninstallation..."
        uninstall_all
        echo "Uninstallation complete."
    else
        echo "Usage: $0 install|uninstall"
        exit 1
    fi
}

main "$@"
