# 🚀 0G Storage Node Setup Guide

This repository helps you set up and run a 0G Storage Node using a custom configuration file maintained in this repo.

---

## 📁 Folder Structure


---

## ⚙️ Requirements

- Ubuntu 20.04/22.04 LTS
- Minimum 4 CPU cores & 8GB RAM
- Docker & Docker Compose installed
- Ports 8600-8799 open

---

## 🧱 Step-by-Step Installation

### 1. Update Your System

```bash
sudo apt update && sudo apt upgrade -y

2. Install Dependencies

sudo apt install curl wget git dos2unix -y

3. Install Docker

curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker

4. Install Docker Compose

DOCKER_COMPOSE_VERSION="2.24.6"

curl -SL https://github.com/docker/compose/releases/download/v$DOCKER_COMPOSE_VERSION/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
docker-compose --version

5. Download 0G Storage Node

cd ~
git clone https://github.com/0glabs/0g-storage-node.git
cd 0g-storage-node

6. Download Custom Config

curl -o $HOME/0g-storage-node/run/config.toml https://raw.githubusercontent.com/shairkhan2/0G-STORAGE/main/v3_config.toml


