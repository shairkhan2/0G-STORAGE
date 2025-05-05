Hardware Requirements
Component	Storage Node	Storage KV
Memory	32 GB RAM	32 GB RAM
CPU	8 cores	8 cores
Disk	500GB / 1TB NVMe SSD	Size matches the KV streams it maintains
Bandwidth	100 Mbps (Download / Upload)	-




Install Dependencies

<pre><code>sudo apt-get install clang cmake build-essential pkg-config libssl-dev</code></pre>

INSTALL RUST

<pre><code>curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh </code></pre>
<pre><code>. "$HOME/.cargo/env"</code></pre>


CLONE 0G-LAB REPO

<pre><code>git clone -b v1.0.0 https://github.com/0glabs/0g-storage-node.git</code></pre>

Build the Source Code

<pre><code>cd 0g-storage-node

# Build in release mode
cargo build --release </code></pre>

Download config file

<pre><code>curl -o $HOME/0g-storage-node/run/config.toml https://raw.githubusercontent.com/shairkhan2/0G-STORAGE/main/v3_config.toml</code></pre>

#edit config.toml

<pre><code>cd run
  nano config.toml</code></pre>

make sure to adjust these
 add miner key your wallet pvt key new wallet
 
log_config_file = "your-log-file-path" i set defoult path to /root/0g-storage-node/run/log_config

 #NOW START THE NODE 

<pre><code>../target/release/zgs_node --config config.toml --miner-key your_private_key </code></pre>

NOW CHECK BLOCK ITS RUNNING OR NOT

<pre><code>while true; do
    response=$(curl -s -X POST http://localhost:5678 -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"zgs_getStatus","params":[],"id":1}')
    logSyncHeight=$(echo $response | jq '.result.logSyncHeight')
    connectedPeers=$(echo $response | jq '.result.connectedPeers')
    echo -e "logSyncHeight: \033[32m$logSyncHeight\033[0m, connectedPeers: \033[34m$connectedPeers\033[0m"
    sleep 5;
done</code></pre>
