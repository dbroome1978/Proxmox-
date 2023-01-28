#!/usr/bin/env bash
if [ "$VERBOSE" == "yes" ]; then set -x; fi
if [ "$DISABLEIPV6" == "yes" ]; then echo "net.ipv6.conf.all.disable_ipv6 = 1" >>/etc/sysctl.conf; fi
YW=$(echo "\033[33m")
RD=$(echo "\033[01;31m")
BL=$(echo "\033[36m")
GN=$(echo "\033[1;92m")
CL=$(echo "\033[m")
RETRY_NUM=10
RETRY_EVERY=3
NUM=$RETRY_NUM
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"
BFR="\\r\\033[K"
HOLD="-"
set -o errexit
set -o errtrace
set -o nounset
set -o pipefail
shopt -s expand_aliases
alias die='EXIT=$? LINE=$LINENO error_exit'
trap die ERR
silent() { "$@" > /dev/null 2>&1; }
function error_exit() {
  trap - ERR
  local reason="Unknown failure occurred."
  local msg="${1:-$reason}"
  local flag="${RD}‼ ERROR ${CL}$EXIT@$LINE"
  echo -e "$flag $msg" 1>&2
  exit $EXIT
}

function msg_info() {
  local msg="$1"
  echo -ne " ${HOLD} ${YW}${msg}..."
}

function msg_ok() {
  local msg="$1"
  echo -e "${BFR} ${CM} ${GN}${msg}${CL}"
}
function msg_error() {
  local msg="$1"
  echo -e "${BFR} ${CROSS} ${RD}${msg}${CL}"
}

msg_info "Setting up Container OS"
sed -i "/$LANG/ s/\(^# \)//" /etc/locale.gen
locale-gen >/dev/null
set -e

msg_info "Updating Container OS"
apt-get update
apt-get -y upgrade
msg_ok "Updated Container OS"

msg_info "Installing Dependencies"
$STD apt-get install -y curl
$STD apt-get install -y sudo
$STD apt-get install -y mc
$STD apt-get install -y python3
$STD apt-get install -y git
msg_ok "Installed Dependencies"

msg_info "Installing Premiumizer"
mkdir -p /var/lib/premiumizer/
chmod 775 /var/lib/premiumizer/
$STD git clone https://github.com/piejanssens/premiumizer.git premiumizer
cd premiumizer
$STD pip install -r requirements.txt
mv ../premiumizer /opt
chmod 775 /opt/premiumizer
msg_ok "Installed Premiumizer"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/premiumizer.service
[Unit]
Description=Radarr Daemon
After=syslog.target network.target
[Service]
UMask=0002
Type=simple
ExecStart=python premiumizer/premiumizer.py -nobrowser -data=/var/lib/premiumizer/
TimeoutStopSec=20
KillMode=process
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
systemctl -q daemon-reload
systemctl enable --now -q radarr
msg_ok "Created Service"

PASS=$(grep -w "root" /etc/shadow | cut -b6)
echo "export TERM='xterm-256color'" >>/root/.bashrc
if [[ $PASS != $ ]]; then
  msg_info "Customizing Container"
  chmod -x /etc/update-motd.d/*
  touch ~/.hushlogin
  GETTY_OVERRIDE="/etc/systemd/system/container-getty@1.service.d/override.conf"
  mkdir -p $(dirname $GETTY_OVERRIDE)
  cat <<EOF >$GETTY_OVERRIDE
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear --keep-baud tty%I 115200,38400,9600 \$TERM
EOF
  systemctl daemon-reload
  systemctl restart $(basename $(dirname $GETTY_OVERRIDE) | sed 's/\.d//')
  msg_ok "Customized Container"
fi
if [[ "${SSH_ROOT}" == "yes" ]]; then
  sed -i "s/#PermitRootLogin prohibit-password/PermitRootLogin yes/g" /etc/ssh/sshd_config
  systemctl restart sshd
fi

msg_info "Cleaning up"
rm -rf Radarr.master.*.tar.gz
$STD apt-get autoremove
$STD apt-get autoclean
msg_ok "Cleaned"
