#!/bin/bash
set -e

# Default values
trans="tcp"
domain="www.google.com"
regenerate=false
uninstall=false
path="$HOME/reality"
safenet=false
image="teddysun/xray:1.8.0"

# Function to display help information
function show_help {
  echo "Usage: $0 [-t|--trans=h2|grpc|tcp] [-d|--domain=<domain>] [-r|--regenerate] [-p|--path=<path>] [-u|--uninstall]"
  echo "  -t, --trans         Transport protocol to use (default: tcp)"
  echo "  -d, --domain        Domain to use (default: www.google.com)"
  echo "  -r, --regenerate    Regenerate configuration (default: false)"
  echo "  -u, --uninstall     Uninstall reality (default: false)"
  echo "  -p, --path          Absolute path to configuration directory (default: $HOME/reality)"
  echo "  -s, --safenet       Block malware and adult content (default: false)"
  echo "  -h, --help          Display this help message"
}

# Regular expression for domain validation
domain_regex="^[a-zA-Z0-9]+([-.][a-zA-Z0-9]+)*\.[a-zA-Z]{2,}$"

# Regular expression for absolute path validation
path_regex="^/.*"

# Parse arguments
opts=$(getopt -o t:d:rup:sh --long trans:,domain:,regenerate,uninstall,path:,safenet,help -- "$@")
if [ $? -ne 0 ]; then
  show_help
  exit 1
fi
eval set -- "$opts"
while true; do
  case $1 in
    -t|--trans)
    trans="$2"
    case $trans in
      h2|grpc|tcp)
      shift 2
      ;;
      *)
      echo "Invalid transport protocol: $trans"
      show_help
      exit 1
      ;;
    esac
    ;;
    -d|--domain)
    domain="$2"
    if ! [[ $domain =~ $domain_regex ]]; then
      echo "Invalid domain: $domain"
      show_help
      exit 1
    fi
    shift 2
    ;;
    -r|--regenerate)
    regenerate=true
    shift
    ;;
    -u|--uninstall)
    uninstall=true
    shift
    ;;
    -p|--path)
    path="$2"
    if ! [[ $path =~ $path_regex ]]; then
      echo "Use absolute path: $path"
      show_help
      exit 1
    fi
    shift 2
    ;;
    -s|--safenet)
    safenet=true
    shift
    ;;
    -h|--help)
    show_help
    exit 0
    ;;
    --)
    shift
    break
    ;;
    *)
    echo "Unknown option: $1"
    show_help
    exit 1
    ;;
  esac
done

if $uninstall; then
  if command -v docker > /dev/null 2>&1; then
    sudo docker compose --project-directory "${path}" down
  fi 
  rm -rf "${path}"
  exit 0
fi

if $regenerate; then
  rm -rf "${path}"
fi

server=$(ip route get 1.1.1.1 | grep -oP '(?<=src )(\d{1,3}\.){3}\d{1,3}')

if ! command -v qrencode > /dev/null 2>&1; then
  echo "Updating repositories ..."
  sudo apt update
  echo "Installing qrencode ..."
  sudo apt install qrencode -y
fi
if ! command -v docker > /dev/null 2>&1; then
  echo "Installing docker ..."
  curl -fsSL https://get.docker.com | sudo bash
fi

mkdir -p "${path}"
if [[ ! -e "${path}/config" ]]; then
key_pair=$(sudo docker run -q --rm ${image} xray x25519)
cat >"${path}/config" <<EOF
uuid=$(cat /proc/sys/kernel/random/uuid)
public_key=$(echo "${key_pair}"|grep -oP '(?<=Public key: ).*')
private_key=$(echo "${key_pair}"|grep -oP '(?<=Private key: ).*')
short_id=$(openssl rand -hex 8)
EOF
fi

. "${path}/config"

cat >"${path}/docker-compose.yml" <<EOF
version: "3"
services:
  xray:
    image: ${image}
    ports:
    - 80:8080
    - 443:8443
    restart: always
    environment:
    - "TZ=Etc/UTC"
    volumes:
    - ./xray.conf:/etc/xray/config.json
EOF

cat >"${path}/xray.conf" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "dns": {
    "servers": [$($safenet && echo '"1.1.1.3","1.0.0.3"' || echo '"1.1.1.1","1.0.0.1"')]
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": 8080,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "${domain}",
        "port": 80,
        "network": "tcp"
      }
    },
    {
      "listen": "0.0.0.0",
      "port": 8443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "flow": "$([[ $trans == 'tcp' ]] && echo 'xtls-rprx-vision' || true)"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        $([[ $trans == 'grpc' ]] && echo '"grpcSettings": {"serviceName": "grpc"},' || true)
        "network": "${trans}",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${domain}:443",
          "xver": 0,
          "serverNames": [
            "${domain}"
          ],
          "privateKey": "${private_key}",
          "maxTimeDiff": 60000,
          "shortIds": [
            "${short_id}"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "ip": [
          "0.0.0.0/8",
          "10.0.0.0/8",
          "100.64.0.0/10",
          "127.0.0.0/8",
          "169.254.0.0/16",
          "172.16.0.0/12",
          "192.0.0.0/24",
          "192.0.2.0/24",
          "192.168.0.0/16",
          "198.18.0.0/15",
          "198.51.100.0/24",
          "203.0.113.0/24",
          "::1/128",
          "fc00::/7",
          "fe80::/10",
          "geoip:private",
          "geoip:ir"
        ],
        "outboundTag": "block"
      },
      {
        "type": "field",
        "port": "25, 587, 465, 2525",
        "network": "tcp",
        "outboundTag": "block"
      },
      {
        "type": "field",
        "protocol": ["bittorrent"],
        "outboundTag": "block"
      },
      {
        "type": "field",
        "outboundTag": "block",
        "domain": [
          $($safenet && echo '"geosite:category-porn",' || true)
          "geosite:category-ads-all",
          "domain:pushnotificationws.com",
          "domain:sunlight-leds.com",
          "domain:icecyber.org"
        ]
      }
    ]
  },
  "policy": {
    "levels": {
      "0": {
        "handshake": 2,
        "connIdle": 120
      }
    }
  }
}
EOF

sudo docker compose --project-directory "${path}" down
sudo docker compose --project-directory "${path}" up -d

config="vless://${uuid}@${server}:443?security=reality&encryption=none&alpn=h2,http/1.1&pbk=${public_key}&headerType=none&fp=chrome&type=${trans}&flow=$([[ $trans == 'tcp' ]] && echo 'xtls-rprx-vision' || true)&sni=${domain}&sid=${short_id}$([[ $trans == 'grpc' ]] && echo '&mode=multi&serviceName=grpc' || true)#reality"
echo ""
echo "=================================================="
echo "Client configuration:"
echo ""
echo "$config"
echo ""
echo "Or you can scan the QR code:"
echo ""
qrencode -t ansiutf8 $config