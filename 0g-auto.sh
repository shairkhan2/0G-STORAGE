#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}👋 SHAIR: Starting 0G Node Setup Script...${NC}"

### ───────────────────────────────
### 0. Ask refresh interval
### ───────────────────────────────
read -rp "⏱️  Days between auto-refreshes? [2] " INTERVAL_DAYS
INTERVAL_DAYS=${INTERVAL_DAYS:-2}
echo -e "${GREEN}✓ Refresh interval set: $INTERVAL_DAYS day(s)${NC}"

### ───────────────────────────────
### 1. Define paths
### ───────────────────────────────
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
  sudo apt install curl iptables build-essential git wget lz4 jq make protobuf-compiler cmake gcc nano automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip libleveldb-dev screen ufw -y

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
### 8. Stop, download, and restore snapshot
### ───────────────────────────────
echo -e "${GREEN}🧊 Seeding snapshot...${NC}"
sleep 15
sudo systemctl stop zgs

SNAP_URL="https://github.com/Mayankgg01/0G-Storage-Node-Guide/releases/download/v1.0/flow_db.tar.xz"
DB_DIR="$RUN_DIR/db"
rm -rf "$DB_DIR/flow_db"
mkdir -p "$DB_DIR"
wget -q "$SNAP_URL" -O "$DB_DIR/flow_db.tar.xz"
tar -xJvf "$DB_DIR/flow_db.tar.xz" -C "$DB_DIR"
rm "$DB_DIR/flow_db.tar.xz"
echo -e "${GREEN}✅ Snapshot loaded${NC}"

sudo systemctl restart zgs
echo -e "${GREEN}🔁 Node restarted with snapshot${NC}"

### ───────────────────────────────
### 9. Setup systemd auto-refresh timer
### ───────────────────────────────
echo -e "${GREEN}⏳ Setting up auto-refresh timer...${NC}"
SCRIPT_PATH="$(readlink -f "$0")"

sudo tee /etc/systemd/system/zgs-refresh.service >/dev/null <<EOF
[Unit]
Description=Refresh ZGS node + snapshot
After=network.target
[Service]
Type=oneshot
ExecStart=$SCRIPT_PATH
EOF

sudo tee /etc/systemd/system/zgs-refresh.timer >/dev/null <<EOF
[Unit]
Description=Run ZGS refresh every $INTERVAL_DAYS day(s)
[Timer]
OnUnitActiveSec=${INTERVAL_DAYS}d
Persistent=true
[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now zgs-refresh.timer
echo -e "${GREEN}✅ Timer enabled – check: sudo systemctl list-timers zgs-refresh*${NC}"

### ───────────────────────────────
### 10. Done!
### ───────────────────────────────
echo -e "\n${RED}🎉 SHAIR: Node setup complete!${NC} ${GREEN}Auto-refresh every $INTERVAL_DAYS day(s). You're all set!${NC}"
