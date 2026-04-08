#!/bin/bash
# setup-ap.sh — Configure simultaneous WiFi AP + STA on Raspberry Pi Zero 2W (Raspbian Buster)
#
# Creates a virtual AP interface (uap0) on top of the existing wlan0 WiFi client.
# AP SSID: zbitx  |  Password: zbitx12345  |  Gateway: 192.168.4.1
#
# Run as root or with sudo:
#   sudo bash setup-ap.sh

set -e

AP_SSID="zbitx"
AP_PASS="zbitx12345"
AP_IP="192.168.4.1"
AP_DHCP_START="192.168.4.2"
AP_DHCP_END="192.168.4.20"
AP_IFACE="uap0"
STA_IFACE="wlan0"

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()   { error "$*"; exit 1; }

# ── Sanity checks ─────────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || die "Please run as root: sudo bash $0"
command -v iw >/dev/null || die "'iw' not found. Is this a Raspberry Pi?"
ip link show "$STA_IFACE" &>/dev/null || die "Interface $STA_IFACE not found."

# ── Step 1: Detect current WiFi channel ───────────────────────────────────────
info "Detecting current WiFi channel on $STA_IFACE..."
CHANNEL=$(iw dev "$STA_IFACE" info 2>/dev/null | awk '/channel/{print $2}')
if [[ -z "$CHANNEL" ]]; then
    warn "  Could not detect channel; defaulting to 6."
    CHANNEL=6
else
    info "  Using channel $CHANNEL (matches connected AP)."
fi

# ── Step 2: Fix apt sources for EOL Buster ────────────────────────────────────
info "Checking apt sources..."
NEED_UPDATE=0

if ! grep -q "archive.debian.org" /etc/apt/sources.list 2>/dev/null; then
    info "  Updating /etc/apt/sources.list to use Debian/Raspbian archives..."
    cat > /etc/apt/sources.list <<'EOF'
deb [trusted=yes] http://archive.debian.org/debian buster main contrib non-free
deb [trusted=yes] http://archive.raspbian.org/raspbian buster main contrib non-free rpi
EOF
    NEED_UPDATE=1
fi

if [[ ! -f /etc/apt/apt.conf.d/99no-check-valid ]]; then
    echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid
    NEED_UPDATE=1
fi

if [[ $NEED_UPDATE -eq 1 ]]; then
    info "  Running apt-get update..."
    apt-get update -q 2>&1 | grep -v "^W:" | tail -5 || true
else
    info "  Sources already configured, skipping update."
fi

# ── Step 3: Install hostapd and dnsmasq ───────────────────────────────────────
info "Installing hostapd and dnsmasq..."
DEBIAN_FRONTEND=noninteractive apt-get install -y hostapd dnsmasq 2>&1 | tail -5
command -v hostapd >/dev/null || die "hostapd installation failed."
command -v dnsmasq >/dev/null || die "dnsmasq installation failed."
info "  Packages installed."

# ── Step 4: Write hostapd configuration ──────────────────────────────────────
info "Writing /etc/hostapd/hostapd.conf..."
cat > /etc/hostapd/hostapd.conf <<EOF
interface=${AP_IFACE}
driver=nl80211
ssid=${AP_SSID}
hw_mode=g
channel=${CHANNEL}
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=${AP_PASS}
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
EOF

cat > /etc/default/hostapd <<'EOF'
DAEMON_CONF="/etc/hostapd/hostapd.conf"
EOF

# ── Step 5: Write dnsmasq configuration ──────────────────────────────────────
info "Writing /etc/dnsmasq.d/uap0.conf..."
cat > /etc/dnsmasq.d/uap0.conf <<EOF
interface=${AP_IFACE}
dhcp-range=${AP_DHCP_START},${AP_DHCP_END},255.255.255.0,24h
domain-needed
bogus-priv
EOF

# ── Step 6: Configure dhcpcd for uap0 static IP ──────────────────────────────
info "Configuring dhcpcd for ${AP_IFACE} static IP..."
if grep -q "interface ${AP_IFACE}" /etc/dhcpcd.conf 2>/dev/null; then
    warn "  ${AP_IFACE} already in /etc/dhcpcd.conf — skipping."
else
    cat >> /etc/dhcpcd.conf <<EOF

# WiFi AP virtual interface — added by setup-ap.sh
interface ${AP_IFACE}
    static ip_address=${AP_IP}/24
    nohook wpa_supplicant
EOF
    info "  Added ${AP_IFACE} to /etc/dhcpcd.conf."
fi

# ── Step 7: Create uap0 systemd service ───────────────────────────────────────
info "Creating /etc/systemd/system/uap0.service..."
cat > /etc/systemd/system/uap0.service <<EOF
[Unit]
Description=Create ${AP_IFACE} virtual WiFi AP interface
Before=hostapd.service dnsmasq.service
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c '/sbin/iw dev ${STA_IFACE} interface add ${AP_IFACE} type __ap; ip link set ${AP_IFACE} up; ip addr add ${AP_IP}/24 dev ${AP_IFACE} 2>/dev/null || true'
ExecStop=/sbin/iw dev ${AP_IFACE} del

[Install]
WantedBy=multi-user.target
EOF

# ── Step 8: Enable services ───────────────────────────────────────────────────
info "Enabling services..."
systemctl daemon-reload
systemctl unmask hostapd 2>/dev/null || true
systemctl enable uap0 hostapd dnsmasq

# ── Step 9: Start everything ──────────────────────────────────────────────────
info "Starting services..."
iw dev "$AP_IFACE" del 2>/dev/null || true
systemctl start uap0
systemctl restart dhcpcd
sleep 2
systemctl restart hostapd
systemctl restart dnsmasq

# ── Step 10: Verify ───────────────────────────────────────────────────────────
echo ""
info "=== Verification ==="

UAP_IP=$(ip addr show "$AP_IFACE" 2>/dev/null | awk '/inet /{print $2}')
STA_IP=$(ip addr show "$STA_IFACE" 2>/dev/null | awk '/inet /{print $2}')
AP_CHANNEL=$(iw dev "$AP_IFACE" info 2>/dev/null | awk '/channel/{print $2}')
AP_SSID_CHK=$(iw dev "$AP_IFACE" info 2>/dev/null | awk '/ssid/{print $2}')
SVCS=$(systemctl is-active hostapd dnsmasq uap0 2>/dev/null | paste -sd,)

echo "  Services (hostapd,dnsmasq,uap0): $SVCS"
echo "  $STA_IFACE (client): ${STA_IP:-NOT ASSIGNED}"
echo "  $AP_IFACE  (AP):     ${UAP_IP:-NOT ASSIGNED}"
echo "  AP SSID:    ${AP_SSID_CHK:-unknown}"
echo "  AP channel: ${AP_CHANNEL:-unknown}"
echo ""

if [[ "$UAP_IP" == "${AP_IP}/24" ]] && systemctl is-active --quiet hostapd; then
    info "Setup complete. WiFi AP '${AP_SSID}' is broadcasting on ${AP_IP}"
    info "Clients connect with password '${AP_PASS}'"
    info "DHCP range: ${AP_DHCP_START} – ${AP_DHCP_END}"
else
    error "Something may not be working. Check logs with:"
    error "  journalctl -u hostapd -u dnsmasq -u uap0 -n 30"
    exit 1
fi
