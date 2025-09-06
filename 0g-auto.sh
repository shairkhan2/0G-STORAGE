#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}👋 SHAIR: Starting 0G Node Setup Script...${NC}"

### ───────────────────────────────
### 0. Ask storage threshold
### ───────────────────────────────
read -rp "📊 Storage threshold for auto-refresh? [95%] " STORAGE_THRESHOLD
STORAGE_THRESHOLD=${STORAGE_THRESHOLD:-95}
STORAGE_THRESHOLD=${STORAGE_THRESHOLD%\%}  # Remove % if present
echo -e "${GREEN}✓ Storage threshold set: ${STORAGE_THRESHOLD}%${NC}"

### ───────────────────────────────
### 1. Define paths (INCLUDING SCRIPT_PATH)
### ───────────────────────────────
SCRIPT_PATH="$(readlink -f "$0")"
NODE_DIR="$HOME/0g-storage-node"
RUN_DIR="$NODE_DIR/run"
CFG_REL="config.toml"
CFG_SRC="$RUN_DIR/$CFG_REL"
BACKUP_DIR="$HOME/zgs_backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_CFG="$BACKUP_DIR/$TIMESTAMP-$CFG_REL"
IS_OLD=false

### ───────────────────────────────
### 2. Backup config.toml if old user
### ───────────────────────────────
mkdir -p "$BACKUP_DIR"
if [[ -f "$CFG_SRC" ]]; then
  cp "$CFG_SRC" "$BACKUP_CFG"
  IS_OLD=true
  echo -e "${GREEN}🗂️  Found existing config.toml, backed up to $BACKUP_CFG${NC}"
fi

### ───────────────────────────────
### 3. Install dependencies (new users only)
### ───────────────────────────────
if [[ "$IS_OLD" = false && ! -d "$NODE_DIR" ]]; then
  echo -e "${RED}📦 New user detected – installing dependencies...${NC}"
  sudo apt-get update && sudo apt-get upgrade -y
  sudo apt install curl iptables build-essential git wget lz4 jq make protobuf-compiler cmake gcc nano automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils -y

  # Check Rust
  if command -v rustc >/dev/null 2>&1; then
    echo -e "${GREEN}🦀 Rust is already installed: $(rustc --version)${NC}"
  else
    echo -e "${GREEN}🦀 Installing Rust...${NC}"
    curl https://sh.rustup.rs -sSf | sh -s -- -y
    source "$HOME/.cargo/env"
  fi

  # Check Go
  if command -v go >/dev/null 2>&1; then
    echo -e "${GREEN}🐹 Go is already installed: $(go version)${NC}"
  else
    echo -e "${GREEN}🐹 Installing Go 1.24.3...${NC}"
    wget https://go.dev/dl/go1.24.3.linux-amd64.tar.gz
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf go1.24.3.linux-amd64.tar.gz
    rm go1.24.3.linux-amd64.tar.gz
    if ! grep -q '/usr/local/go/bin' ~/.bashrc; then
      echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
    fi
    # Do not source .bashrc in script, print instructions instead:
    echo -e "${GREEN}Go installed. Please restart your shell or run: source ~/.bashrc${NC}"
  fi
fi

### ───────────────────────────────
### 4. Remove old node & service
### ───────────────────────────────
echo -e "${RED}🧹 Removing old service/node (if any)...${NC}"
sudo systemctl stop zgs || true
sudo systemctl disable zgs || true
sudo rm -f /etc/systemd/system/zgs.service
rm -rf "$NODE_DIR"

### ───────────────────────────────
### 5. Clone & build 0G code
### ───────────────────────────────
echo -e "${GREEN}📥 Cloning fresh repo...${NC}"
git clone https://github.com/0glabs/0g-storage-node.git "$NODE_DIR"
cd "$NODE_DIR"
git checkout v1.1.0
git submodule update --init --recursive
echo -e "${GREEN}⚙️  Building node... (takes time)${NC}"
cargo build --release

### ───────────────────────────────
### 6. Config restore or setup
### ───────────────────────────────
mkdir -p "$RUN_DIR"
if [[ -f "$BACKUP_CFG" ]]; then
  cp "$BACKUP_CFG" "$CFG_SRC"
  echo -e "${GREEN}✅ Restored config.toml from backup${NC}"
else
  echo -e "${RED}⬇️  No config found – downloading default${NC}"
  curl -fsSL -o "$CFG_SRC" https://raw.githubusercontent.com/shairkhan2/0G-STORAGE/refs/heads/main/config.toml

  read -e -p "🔐 Enter PRIVATE KEY (with or without 0x): " k
  k=${k#0x}
  printf "\033[A\033[K"
  if [[ ${#k} -eq 64 && "$k" =~ ^[0-9a-fA-F]+$ ]]; then
    sed -i "s|miner_key = .*|miner_key = \"$k\"|" "$CFG_SRC"
    echo -e "${GREEN}✅ Private key updated: ${k:0:4}****${k: -4}${NC}"
  else
    echo -e "${RED}❌ Invalid private key! Exiting.${NC}"
    exit 1
  fi

  read -e -p "🌐 Enter blockchain_rpc_endpoint [default: https://evmrpc-testnet.0g.ai]: " r
  r=${r:-https://evmrpc-testnet.0g.ai}
  sed -i "s|blockchain_rpc_endpoint = .*|blockchain_rpc_endpoint = \"$r\"|" "$CFG_SRC"
  echo -e "${GREEN}✅ RPC endpoint set to: $r${NC}"
fi

### ───────────────────────────────
### 7. Create systemd service
### ───────────────────────────────
echo -e "${GREEN}🧩 Creating systemd service...${NC}"
sudo tee /etc/systemd/system/zgs.service >/dev/null <<EOF
[Unit]
Description=ZGS Node
After=network.target

[Service]
User=$USER
WorkingDirectory=$RUN_DIR
ExecStart=$NODE_DIR/target/release/zgs_node --config $CFG_SRC
Restart=on-failure
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable zgs
sudo systemctl start zgs
echo -e "${GREEN}🚀 Node started (initial test)...${NC}"

### ───────────────────────────────
### 8. Stop, download, and restore snapshot (NEW METHOD)
### ───────────────────────────────
echo -e "${GREEN}🧊 Downloading and extracting snapshot using new method...${NC}"
sleep 15
sudo systemctl stop zgs

DB_DIR="$RUN_DIR/db"
rm -rf "$DB_DIR/flow_db"
mkdir -p "$DB_DIR"

echo -e "${GREEN}📥 Downloading multi-part snapshot archive...${NC}"
wget -q https://github.com/Mayankgg01/0G-Storage-Node-Guide/releases/download/v1.0/flow_db.tar.zst.part-aa -O "$DB_DIR/flow_db.tar.zst.part-aa"
wget -q https://github.com/Mayankgg01/0G-Storage-Node-Guide/releases/download/v1.0/flow_db.tar.zst.part-ab -O "$DB_DIR/flow_db.tar.zst.part-ab"

echo -e "${GREEN}🔗 Combining parts...${NC}"
cat "$DB_DIR/flow_db.tar.zst.part-aa" "$DB_DIR/flow_db.tar.zst.part-ab" > "$DB_DIR/flow_db.tar.zst"

echo -e "${GREEN}📦 Extracting with zstd compression...${NC}"
tar --use-compress-program=unzstd -xvf "$DB_DIR/flow_db.tar.zst" -C "$DB_DIR/"

echo -e "${GREEN}🧹 Cleaning up temporary files...${NC}"
rm "$DB_DIR/flow_db.tar.zst.part-aa" "$DB_DIR/flow_db.tar.zst.part-ab" "$DB_DIR/flow_db.tar.zst"

echo -e "${GREEN}✅ Snapshot loaded (syncing from block 5971353)${NC}"

sudo systemctl restart zgs
echo -e "${GREEN}🔁 Node restarted with snapshot${NC}"

### ───────────────────────────────
### 9. Create storage monitoring script
### ───────────────────────────────
echo -e "${GREEN}📊 Creating storage monitoring script...${NC}"
MONITOR_SCRIPT="/usr/local/bin/zgs-storage-monitor.sh"

sudo tee "$MONITOR_SCRIPT" >/dev/null <<EOF
#!/usr/bin/env bash
set -euo pipefail

# Get the disk usage percentage for the filesystem containing the node directory
NODE_DIR="$HOME/0g-storage-node"
USAGE=\$(df "\$NODE_DIR" | awk 'NR==2 {print \$5}' | sed 's/%//')
THRESHOLD=$STORAGE_THRESHOLD

echo "\$(date): Checking storage usage: \${USAGE}% (threshold: \${THRESHOLD}%)"

if [[ \$USAGE -ge \$THRESHOLD ]]; then
    echo "\$(date): Storage usage (\${USAGE}%) exceeded threshold (\${THRESHOLD}%). Triggering refresh..."
    # Run the main script to refresh the node
    $SCRIPT_PATH
else
    echo "\$(date): Storage usage (\${USAGE}%) is below threshold (\${THRESHOLD}%). No action needed."
fi
EOF

sudo chmod +x "$MONITOR_SCRIPT"

### ───────────────────────────────
### 10. Setup systemd storage monitoring timer
### ───────────────────────────────
echo -e "${GREEN}⏳ Setting up storage monitoring timer...${NC}"

sudo tee /etc/systemd/system/zgs-storage-monitor.service >/dev/null <<EOF
[Unit]
Description=Monitor ZGS node storage usage
After=network.target

[Service]
Type=oneshot
User=$USER
ExecStart=$MONITOR_SCRIPT
EOF

sudo tee /etc/systemd/system/zgs-storage-monitor.timer >/dev/null <<EOF
[Unit]
Description=Check ZGS storage usage every 30 minutes

[Timer]
OnBootSec=30min
OnUnitActiveSec=30min
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now zgs-storage-monitor.timer
echo -e "${GREEN}✅ Storage monitor enabled – check: sudo systemctl list-timers zgs-storage-monitor*${NC}"

### ───────────────────────────────
### 11. Create storage check command
### ───────────────────────────────
echo -e "${GREEN}🔧 Creating manual storage check command...${NC}"
sudo tee /usr/local/bin/check-zgs-storage >/dev/null <<EOF
#!/usr/bin/env bash
NODE_DIR="$HOME/0g-storage-node"
USAGE=\$(df "\$NODE_DIR" | awk 'NR==2 {print \$5}' | sed 's/%//')
echo "Current storage usage: \${USAGE}%"
echo "Configured threshold: ${STORAGE_THRESHOLD}%"
if [[ \$USAGE -ge ${STORAGE_THRESHOLD} ]]; then
    echo "⚠️  Storage usage is above threshold!"
else
    echo "✅ Storage usage is within limits"
fi
EOF

sudo chmod +x /usr/local/bin/check-zgs-storage

### ───────────────────────────────
### 12. Done!
### ───────────────────────────────
echo -e "\n${RED}🎉 SHAIR: Node setup complete!${NC} ${GREEN}Auto-refresh when storage reaches ${STORAGE_THRESHOLD}%. You're all set!${NC}"
echo -e "${GREEN}📊 Use 'check-zgs-storage' to manually check storage usage${NC}"
echo -e "${GREEN}🔍 Monitor logs: sudo journalctl -u zgs-storage-monitor -f${NC}"
