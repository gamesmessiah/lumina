#!/bin/sh

# ==============================================================================
# Lumina Server Deployment & Setup Script
# Strategy 1: Multi-Platform Pre-compiled Binaries via GitHub Releases
# ==============================================================================

# --- Configuration ---
VERSION="v2.0.0"  # Update this to match your GitHub Release tag
REPO_URL="https://github.com/example-user/lumina-server/releases/download/${VERSION}"
DEFAULT_PORT=1918

# --- Internal Flags ---
AUTO_START=""
QUIET=false

# Root check
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root (or via sudo)." >&2
    exit 1
fi

# Parse command line flags for automation/headless setups
while [ "$#" -gt 0 ]; do
    case "$1" in
        --auto-start=*) AUTO_START="${1#*=}" ;;
        --quiet) QUIET=true ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

# 1. Detect Operating System
OS=$(uname -s)
echo "Detecting operating system... Found $OS"

# 2. Configure Domain and Settings (/etc/lumina/server.conf)
echo "--------------------------------------------------"
echo "Configuring Lumina Server Settings"
echo "--------------------------------------------------"

CONFIG_DIR="/etc/lumina"
mkdir -p "$CONFIG_DIR"

if [ "$QUIET" = true ]; then
    DOMAIN="localhost"
else
    echo -n "Enter the domain name for this server (e.g., example.com): "
    read DOMAIN
    if [ -z "$DOMAIN" ]; then
        DOMAIN="localhost"
    fi
fi

# Write out the clean INI configuration file
cat <<EOF > "${CONFIG_DIR}/server.conf"
[server]
domain = ${DOMAIN}
root_dir = /var/Lumina/${DOMAIN}
port = ${DEFAULT_PORT}
EOF

# Ensure the root directory for serving files exists
mkdir -p "/var/Lumina/${DOMAIN}"
echo "Configuration saved to ${CONFIG_DIR}/server.conf"
echo "Server root directory established at /var/Lumina/${DOMAIN}"

# 3. Dynamic prompt function helper for startup configuration
prompt_auto_start() {
    if [ -n "$AUTO_START" ]; then
        return 0
    fi
    if [ "$QUIET" = true ]; then
        AUTO_START="false"
        return 0
    fi

    echo -n "Do you want Lumina Server to start automatically on boot? [Y/n]: "
    read response
    case "$response" in
        [nN][oO]|[nN]) AUTO_START="false" ;;
        *) AUTO_START="true" ;;
    esac
}

# 4. Platform Execution Block
case "$OS" in
    Linux)
        echo "Downloading Linux binary from GitHub..."
        if command -v curl >/dev/null 2>&1; then
            curl -L -sSF -o /usr/local/bin/lumina-server "${REPO_URL}/lumina-server-linux"
        elif command -v wget >/dev/null 2>&1; then
            wget -q -O /usr/local/bin/lumina-server "${REPO_URL}/lumina-server-linux"
        else
            echo "Error: Neither curl nor wget found. Cannot download binary." >&2
            exit 1
        fi
        
        chmod +x /usr/local/bin/lumina-server
        echo "Successfully installed executable to /usr/local/bin/lumina-server"

        # Check for systemd presence
        if [ -d /run/systemd/system ] || [ -x /bin/systemctl ] || [ -x /sbin/init ]; then
            prompt_auto_start
            
            if [ "$AUTO_START" = "true" ]; then
                echo "Configuring systemd service..."
                
                cat <<EOF > /etc/systemd/system/lumina-server.service
[Unit]
Description=Lumina Mirror Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/lumina-server
Restart=on-failure
User=nobody

[Install]
WantedBy=multi-user.target
EOF

                systemctl daemon-reload
                systemctl enable lumina-server
                echo "systemd service created and enabled successfully."
            else
                echo "Skipping systemd service registration."
            fi
        else
            echo "Linux detected, but systemd environment wasn't verified. Skipping init setup."
        fi
        ;;

    FreeBSD)
        echo "Downloading FreeBSD binary from GitHub..."
        if fetch -q -o /usr/local/bin/lumina-server "${REPO_URL}/lumina-server-freebsd"; then
            chmod +x /usr/local/bin/lumina-server
            echo "Successfully installed executable to /usr/local/bin/lumina-server"
        else
            echo "Error: Failed to fetch the FreeBSD binary from GitHub." >&2
            exit 1
        fi

        prompt_auto_start
        
        if [ "$AUTO_START" = "true" ]; then
            echo "Configuring FreeBSD rc.d service loop..."
            
            # Write a POSIX compliant rc.d daemon block
            cat <<'EOF' > /usr/local/etc/rc.d/lumina_server
#!/bin/sh
#
# PROVIDE: lumina_server
# REQUIRE: NETWORKING
# KEYWORD: shutdown

. /etc/rc.subr

name="lumina_server"
rcvar="lumina_server_enable"
command="/usr/local/bin/lumina-server"
pidfile="/var/run/${name}.pid"
command_args="-P ${pidfile} -r"

load_rc_config ${name}
run_rc_command "$1"
EOF

            chmod +x /usr/local/etc/rc.d/lumina_server
            
            # Use sysrc natively if present, safely append otherwise
            if command -v sysrc >/dev/null 2>&1; then
                sysrc lumina_server_enable="YES"
            else
                echo 'lumina_server_enable="YES"' >> /etc/rc.conf
            fi
            echo "rc.d block created and enabled in rc.conf successfully."
        else
            echo "Skipping rc.conf modifications."
        fi
        ;;

    *)
        echo "Unsupported Operating System: $OS" >&2
        echo "Lumina setup only supports precompiled target binaries for Linux and FreeBSD." >&2
        exit 1
        ;;
esac

echo "--------------------------------------------------"
echo "Lumina Server Installation Complete!"
echo "--------------------------------------------------"