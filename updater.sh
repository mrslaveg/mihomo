#!/bin/sh
# Mihomo Config Updater (OpenWrt + Keenetic / Xkeen + SSClash)

CONFIG_PATH="/etc/mihomo/config.yaml"
SUBSCRIPTION_FILE="/etc/mihomo/subscription.txt"
HWID_FILE="/etc/mihomo/hwid.txt"
TEMPLATE_PATH="/etc/mihomo/template.yaml"
BACKUP_PATH="${CONFIG_PATH}.bak"

TEMPLATE_URL_OPENWRT="https://raw.githubusercontent.com/USER/REPO/main/templates/template_openwrt.yaml"
TEMPLATE_URL_KEENETIC="https://raw.githubusercontent.com/USER/REPO/main/templates/template_keenetic.yaml"

echo "=== Mihomo Config Updater ==="

mkdir -p /etc/mihomo

# =========================
# INSTALL MODE (ONE TIME)
# =========================
if [ "$1" = "--install" ]; then

  echo "=== Initial cron setup ==="
  echo "1) Каждый день"
  echo "2) Раз в неделю"
  echo "3) Каждые 6 часов"
  read -p "Выбор: " MODE

  if [ "$MODE" = "1" ]; then
    read -p "Час (0-23): " H
    read -p "Минута (0-59): " M
    CRON="$M $H * * *"
  fi

  if [ "$MODE" = "2" ]; then
    read -p "День недели (0-6): " D
    read -p "Час: " H
    read -p "Минута: " M
    CRON="$M $H * * $D"
  fi

  if [ "$MODE" = "3" ]; then
    CRON="0 */6 * * *"
  fi

  ( crontab -l 2>/dev/null; echo "$CRON /etc/mihomo/updater.sh" ) | crontab -

  echo "✔ Cron установлен: $CRON"
  exit 0
fi

# =========================
# BASIC CHECKS
# =========================
command -v curl >/dev/null 2>&1 || {
  echo "❌ curl не установлен"
  exit 1
}

# =========================
# PLATFORM DETECTION
# =========================
if command -v ndmc >/dev/null 2>&1; then
  PLATFORM="keenetic"
  TEMPLATE_URL="$TEMPLATE_URL_KEENETIC"
else
  PLATFORM="openwrt"
  TEMPLATE_URL="$TEMPLATE_URL_OPENWRT"
fi

echo "📦 Platform: $PLATFORM"

# =========================
# DOWNLOAD TEMPLATE
# =========================
echo "📥 Download template..."

if ! curl -fsSL "$TEMPLATE_URL" -o "$TEMPLATE_PATH"; then
  echo "❌ Template download failed"
  exit 1
fi

# =========================
# SUBSCRIPTION
# =========================
if [ ! -f "$SUBSCRIPTION_FILE" ]; then
  echo "❌ Missing subscription file"
  exit 1
fi

SUB_URL=$(head -n1 "$SUBSCRIPTION_FILE" | tr -d '\r\n ')

echo "$SUB_URL" | grep -qE '^https?://' || {
  echo "❌ Invalid subscription URL"
  exit 1
}

# =========================
# HWID
# =========================
if [ ! -f "$HWID_FILE" ]; then
  if command -v uuidgen >/dev/null 2>&1; then
    HWID=$(uuidgen | tr '[:upper:]' '[:lower:]')
  else
    HWID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "hwid-$(date +%s)")
  fi
  echo "$HWID" > "$HWID_FILE"
else
  HWID=$(cat "$HWID_FILE" | tr -d '\r\n ')
fi

# =========================
# DEVICE INFO
# =========================
if [ "$PLATFORM" = "keenetic" ]; then
  NDM_INFO=$(ndmc -c 'show version' 2>/dev/null)

  DEVICE_MODEL=$(echo "$NDM_INFO" | awk -F': ' '/model:/ {print $2}' | sed 's/[-_()]/ /g' | xargs)
  DEVICE_OS="Keenetic OS"
  X_VER_OS=$(echo "$NDM_INFO" | awk '/title:/ {print $2}' || echo "NDMS")

  USER_AGENT="mihomo/unknown (Keenetic)"

else
  DEVICE_MODEL=$(cat /tmp/sysinfo/model 2>/dev/null | sed 's/[-_()]/ /g' | xargs)
  DEVICE_MODEL=${DEVICE_MODEL:-OpenWrt Router}

  OS_VER=$(grep DISTRIB_RELEASE /etc/openwrt_release 2>/dev/null | cut -d'"' -f2)
  DEVICE_OS="OpenWrt ${OS_VER:-unknown}"

  SSCLASH_VER=$(opkg list-installed luci-app-ssclash 2>/dev/null | awk '{print $2}')
  X_VER_OS=${SSCLASH_VER:-SSClash}

  USER_AGENT="mihomo/unknown (OpenWrt)"
fi

# =========================
# BACKUP
# =========================
[ -f "$CONFIG_PATH" ] && cp "$CONFIG_PATH" "$BACKUP_PATH"

# =========================
# BUILD CONFIG
# =========================
awk '/proxy-providers:/ {exit} {print}' "$TEMPLATE_PATH" > "$CONFIG_PATH"

cat >> "$CONFIG_PATH" << EOF

proxy-providers:
  FastConnect:
    type: http
    url: "$SUB_URL"
    interval: 3600
    health-check:
      enable: true
      url: http://www.msftncsi.com/ncsi.txt
      interval: 300
    exclude-filter: "LTE"
    header:
      x-hwid:
        - "$HWID"
      x-device-os:
        - "$DEVICE_OS"
      x-ver-os:
        - "$X_VER_OS"
      x-device-model:
        - "$DEVICE_MODEL"
      User-Agent:
        - "$USER_AGENT"

proxies: []
EOF

# =========================
# APPEND TEMPLATE PART
# =========================
if grep -q '^proxy-groups:' "$TEMPLATE_PATH"; then
  sed -n '/^proxy-groups:/,$p' "$TEMPLATE_PATH" >> "$CONFIG_PATH"
fi

echo "✔ Config generated"

# =========================
# RESTART NOTE
# =========================
echo "▶ Restart mihomo manually or via service"
