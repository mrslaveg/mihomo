#!/bin/sh
# Универсальный Mihomo Config Updater для OpenWrt + Keenetic (Xkeen)
# Автоматический выбор шаблона под платформу

CONFIG_PATH="/etc/mihomo/config.yaml"
SUBSCRIPTION_FILE="/etc/mihomo/subscription.txt"
HWID_FILE="/etc/mihomo/hwid.txt"
TEMPLATE_PATH="/etc/mihomo/template.yaml"
BACKUP_PATH="${CONFIG_PATH}.bak"

# === GitHub шаблоны ===
TEMPLATE_URL_OPENWRT="https://raw.githubusercontent.com/USER/REPO/main/templates/template_openwrt.yaml"
TEMPLATE_URL_KEENETIC="https://raw.githubusercontent.com/USER/REPO/main/templates/template_keenetic.yaml"

echo "=== Mihomo Universal Updater ==="

mkdir -p /etc/mihomo

# === Проверка curl ===
command -v curl >/dev/null 2>&1 || {
  echo "❌ curl не установлен"
  exit 1
}

# === Определение платформы ===
if command -v ndmc >/dev/null 2>&1; then
  PLATFORM="keenetic"
  TEMPLATE_URL="$TEMPLATE_URL_KEENETIC"
else
  PLATFORM="openwrt"
  TEMPLATE_URL="$TEMPLATE_URL_OPENWRT"
fi

echo "📦 Платформа: $PLATFORM"

# === Скачивание шаблона ===
echo "📥 Загружаем шаблон..."
if ! curl -fsSL "$TEMPLATE_URL" -o "$TEMPLATE_PATH"; then
  echo "❌ Не удалось скачать шаблон для $PLATFORM"
  exit 1
fi

# === Проверка подписки ===
if [ ! -f "$SUBSCRIPTION_FILE" ]; then
  echo "❌ Создайте $SUBSCRIPTION_FILE с URL подписки"
  exit 1
fi

SUB_URL=$(head -n1 "$SUBSCRIPTION_FILE" | tr -d '\r\n ')

echo "$SUB_URL" | grep -qE '^https?://' || {
  echo "❌ Неверная ссылка подписки"
  exit 1
}

# === HWID ===
if [ ! -f "$HWID_FILE" ]; then
  if command -v uuidgen >/dev/null 2>&1; then
    HWID=$(uuidgen | tr '[:upper:]' '[:lower:]')
  else
    HWID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '\n' || echo "hwid-$(date +%s)")
  fi
  echo "$HWID" > "$HWID_FILE"
else
  HWID=$(cat "$HWID_FILE" | tr -d '\r\n ')
fi

# === mihomo version ===
if command -v mihomo >/dev/null 2>&1; then
  MIHOMO_VER=$(mihomo -v 2>/dev/null | head -n1 | grep -oE 'v[0-9]+(\.[0-9]+){1,2}')
else
  MIHOMO_VER="unknown"
fi

# === Device info ===
if [ "$PLATFORM" = "keenetic" ]; then
  NDM_INFO=$(ndmc -c 'show version' 2>/dev/null)

  DEVICE_MODEL=$(echo "$NDM_INFO" | awk -F': ' '/model:/ {print $2}' | sed 's/[-_()]/ /g' | xargs)
  DEVICE_OS="Keenetic OS"
  X_VER_OS=$(echo "$NDM_INFO" | awk '/title:/ {print $2}' || echo "NDMS")

  USER_AGENT="mihomo/$MIHOMO_VER (Keenetic; like Clash Meta)"

else
  DEVICE_MODEL=$(cat /tmp/sysinfo/model 2>/dev/null | sed 's/[-_()]/ /g' | xargs)
  DEVICE_MODEL=${DEVICE_MODEL:-OpenWrt Router}

  OS_VER=$(grep DISTRIB_RELEASE /etc/openwrt_release 2>/dev/null | cut -d'"' -f2)
  DEVICE_OS="OpenWrt ${OS_VER:-unknown}"

  SSCLASH_VER=$(opkg list-installed luci-app-ssclash 2>/dev/null | awk '{print $2}')
  X_VER_OS=${SSCLASH_VER:+SSClash $SSCLASH_VER}
  X_VER_OS=${X_VER_OS:-SSClash}

  USER_AGENT="mihomo/$MIHOMO_VER (OpenWrt; like Clash Meta)"
fi

# === Backup ===
[ -f "$CONFIG_PATH" ] && cp "$CONFIG_PATH" "$BACKUP_PATH"

# === Build config ===
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

# === Append rest of template ===
if grep -q '^proxy-groups:' "$TEMPLATE_PATH"; then
  sed -n '/^proxy-groups:/,$p' "$TEMPLATE_PATH" >> "$CONFIG_PATH"
fi

echo "✅ Готово!"
echo "   Platform       : $PLATFORM"
echo "   Device OS      : $DEVICE_OS"
echo "   HWID           : $HWID"
echo "   Device Model   : $DEVICE_MODEL"
echo "   Version OS     : $X_VER_OS"
echo "   User-Agent     : $USER_AGENT"
echo "   Backup         : $BACKUP_PATH"

echo ""
echo "▶ Restart mihomo: systemctl restart mihomo"
