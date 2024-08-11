#!/bin/bash

# 设置版本号
current_version=20240811001

update_script() {
    # 指定URL
    update_url="https://raw.githubusercontent.com/breaddog100/0gai/main/0gai.sh"
    file_name=$(basename "$update_url")

    # 下载脚本文件
    tmp=$(date +%s)
    timeout 10s curl -s -o "$HOME/$tmp" -H "Cache-Control: no-cache" "$update_url?$tmp"
    exit_code=$?
    if [[ $exit_code -eq 124 ]]; then
        echo "命令超时"
        return 1
    elif [[ $exit_code -ne 0 ]]; then
        echo "下载失败"
        return 1
    fi

    # 检查是否有新版本可用
    latest_version=$(grep -oP 'current_version=([0-9]+)' $HOME/$tmp | sed -n 's/.*=//p')

    if [[ "$latest_version" -gt "$current_version" ]]; then
        clear
        echo ""
        # 提示需要更新脚本
        printf "\033[31m脚本有新版本可用！当前版本：%s，最新版本：%s\033[0m\n" "$current_version" "$latest_version"
        echo "正在更新..."
        sleep 3
        mv $HOME/$tmp $HOME/$file_name
        chmod +x $HOME/$file_name
        exec "$HOME/$file_name"
    else
        # 脚本是最新的
        rm -f $tmp
    fi

}

# 节点安装功能
function install_node() {

    read -r -p "节点名称: " NODE_MONIKER

    if command -v node > /dev/null 2>&1; then
        echo "Node.js 已安装"
    else
        echo "Node.js 未安装，正在安装..."
        curl -fsSL https://deb.nodesource.com/setup_16.x | sudo -E bash -
        sudo apt-get install -y nodejs
    fi
    if command -v npm > /dev/null 2>&1; then
        echo "npm 已安装"
    else
        echo "npm 未安装，正在安装..."
        sudo apt-get install -y npm
    fi
    
	# 更新系统
	sudo apt update
	sudo apt install -y curl git wget htop tmux build-essential jq make lz4 gcc unzip liblz4-tool clang cmake build-essential screen cargo
	
    # 安装Go
    sudo rm -rf /usr/local/go
    curl -L https://go.dev/dl/go1.22.0.linux-amd64.tar.gz | sudo tar -xzf - -C /usr/local
    echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> $HOME/.bash_profile
    export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
    source $HOME/.bash_profile
    
    # 下载代码
    git clone -b v0.2.3 https://github.com/0glabs/0g-chain.git
    ./0g-chain/networks/testnet/install.sh
    source ~/.profile
    
    0gchaind init $NODE_MONIKER --chain-id zgtendermint_16600-2
    0gchaind config chain-id zgtendermint_16600-2
    
    rm ~/.0gchain/config/genesis.json
    wget -P ~/.0gchain/config https://github.com/0glabs/0g-chain/releases/download/v0.2.3/genesis.json
    0gchaind validate-genesis
    wget -O $HOME/.0gchain/config/addrbook.json https://snapshots-testnet.nodejumper.io/0g-testnet/addrbook.json
    
    # 配置种子
    SEEDS="265120a9bb170cf21198aabf88f7908c9944897c@54.241.167.190:26656,497f865d8a0f6c830e2b73009a01b3edefb22577@54.176.175.48:26656,ffc49903241a4e442465ec78b8f421c56b3ae3d4@54.193.250.204:26656,f37bc8623bfa4d8e519207b965a24a288f3213d8@18.166.164.232:26656"
    PEERS="4d98cf3cb2a61238a0b1557596cdc4b306472cb9@95.216.228.91:13456,c44baa3836d07f9ed9a832f819bcf19fda67cc5d@95.216.42.217:13456,81987895a11f6689ada254c6b57932ab7ed909b6@54.241.167.190:26656,010fb4de28667725a4fef26cdc7f9452cc34b16d@54.176.175.48:26656,e9b4bc203197b62cc7e6a80a64742e752f4210d5@54.193.250.204:26656,68b9145889e7576b652ca68d985826abd46ad660@18.166.164.232:26656"
    sed -i "s/seeds = \"\"/seeds = \"$SEEDS\"/" $HOME/.0gchain/config/config.toml
    sed -i "s/persistent_peers = \"\"/persistent_peers = \"$PEERS\"/" $HOME/.0gchain/config/config.toml
    
    sudo tee /etc/systemd/system/0gchaind.service > /dev/null <<EOF
[Unit]
Description=0gchain daemon
After=network-online.target

[Service]
User=$USER
ExecStart=$(which 0gchaind) start
Restart=always
RestartSec=3
LimitNOFILE=infinity

Environment="DAEMON_NAME=0gchaind"
Environment="DAEMON_HOME=${HOME}/.0gchaind"
Environment="DAEMON_RESTART_AFTER_UPGRADE=true"
Environment="DAEMON_ALLOW_DOWNLOAD_BINARIES=false"

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable 0gchaind
    sudo systemctl start 0gchaind
    
    echo '部署完成...'
}

# 查看0gai服务状态
function check_service_status() {
    sudo systemctl status 0gchaind
}

# 0gai 节点日志查询
function view_logs() {
    sudo journalctl -u 0gchaind.service -f -o cat
}

# 卸载验证节点功能
function uninstall_node() {
    echo "确定要卸载0gAI验证节点吗？[Y/N]"
    read -r -p "请确认: " response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            echo "开始卸载验证节点..."
            sudo systemctl stop 0gchaind
            sudo rm -f /etc/systemd/system/0gchaind.service
            rm -rf $HOME/0g-chain $HOME/0g-chain $(which 0gchaind)
            echo "验证节点卸载完成。"
            ;;
        *)
            echo "取消卸载操作。"
            ;;
    esac
}

# 创建钱包
function add_wallet() {
    source $HOME/.bash_profile
	read -p "请输入钱包名称: " wallet_name
    0gchaind keys add $wallet_name --eth
    echo "输入钱包密码，生成0x开头的钱包地址："
    echo "0x$(0gchaind debug addr $(0gchaind keys show $wallet_name -a) | grep hex | awk '{print $3}')"
}

# 导入钱包
function import_wallet() {
    source $HOME/.bash_profile
	read -p "请输入钱包名称: " wallet_name
    0gchaind keys add $wallet_name --recover --eth
    echo "0x$(0gchaind debug addr $(0gchaind keys show $wallet_name -a) | grep hex | awk '{print $3}')"
}

# 查询余额
function check_balances() {
    source $HOME/.bash_profile
    read -p "请输入钱包地址: " wallet_address
    0gchaind query bank balances "$wallet_address"
}

# 查看节点同步状态
function check_sync_status() {
    source $HOME/.bash_profile
    0gchaind status 2>&1 | jq .sync_info
}

# 创建验证者
function add_validator() {
	source $HOME/.bash_profile
	read -p "钱包名称: " wallet_name
	read -p "验证者名字: " validator_name
	
	evmosd tx staking create-validator \
	  --amount=1000000ua0gi \
	  --pubkey=$(0gchaind tendermint show-validator) \
	  --moniker=$validator_name \
	  --chain-id=zgtendermint_16600-2 \
	  --commission-rate=0.10 \
	  --commission-max-rate=0.20 \
	  --commission-max-change-rate=0.01 \
	  --min-self-delegation=1 \
	  --from=$wallet_name \
	  --identity="" \
	  --website="" \
	  --details="Support by breaddog" \
	  --gas=auto \
	  --gas-prices=1.4

	  
}

# 停止验证节点
function stop_node(){
	sudo systemctl stop 0gchaind
	echo "节点已停止..."
}

# 启动验证节点
function start_node(){
	sudo systemctl start 0gchaind
	echo "节点已启动..."
}

# 质押代币
function delegate_aevmos(){
    source $HOME/.bash_profile
    read -p "请输入钱包名称: " wallet_name
    read -p "请输入质押代币数量: " math
    0gchaind tx staking delegate $(0gchaind keys show $wallet_name --bech val -a)  ${math}ua0gi --from $wallet_name  --gas=auto --gas-adjustment=1.4 -y
}

# 代币转账
function send_aevmos(){
    source $HOME/.bash_profile
    read -p "转出钱包名: " out_wallet_name
    read -p "转账代币数量: " math
    read -p "接收钱包地址: " in_wallet_name
    0gchaind tx bank send $out_wallet_name $in_wallet_name ${math}ua0gi --from $out_wallet_name --gas=auto --gas-prices=1.4 -y

}
# 更新种子
function update_peers(){
    
    read -p "请输入种子地址，多个地址用 , 隔开: " PEERS
    sed -i "s/persistent_peers = \"\"/persistent_peers = \"$PEERS\"/" $HOME/.0gchain/config/config.toml
    sudo systemctl restart 0gchaind
}

# 提取秘钥
function show_validator_key() {
    echo "请备份秘钥文件，路径："
    echo "$HOME/.0gchaind/config/priv_validator_key.json"
}

# 申请出狱
function unjail(){
    source $HOME/.bash_profile
	read -p "钱包名称: " wallet_name
	# 查看入狱
	#0gchaind tx slashing unjail --from <key_name> --gas=500000 --gas-prices=99999neuron -y
	0gchaind tx slashing unjail --from $wallet_name --gas=auto --gas-prices=1.4 -y
}

# 下载快照
function download_snap(){
    echo "快照下载根据网速不同时间不同，请耐心等待"
    stop_node
    cp $HOME/.0gchain/data/priv_validator_state.json $HOME/priv_validator_state.json-0gai.bak
    curl -L https://testnet.anatolianteam.com/0g/zgtendermint_16600-2.tar.lz4 | tar -I lz4 -xf - -C $HOME/.0gchain/
    cp $HOME/priv_validator_state.json-0gai.bak $HOME/.0gchain/data/priv_validator_state.json 
    echo "快照下载完成，请查看同步状态"
    start_node
    sleep 3
    check_sync_status
}

#####################################################################################

# 部署存储节点
function install_storage_node() {
    read -p "存储节点名称: " storage_node_name
    read -p "EVM钱包私钥(不含0x): " minerkey

    if command -v node > /dev/null 2>&1; then
        echo "Node.js 已安装"
    else
        echo "Node.js 未安装，正在安装..."
        curl -fsSL https://deb.nodesource.com/setup_16.x | sudo -E bash -
        sudo apt-get install -y nodejs
    fi
    if command -v npm > /dev/null 2>&1; then
        echo "npm 已安装"
    else
        echo "npm 未安装，正在安装..."
        sudo apt-get install -y npm
    fi

	# 更新系统
	sudo apt update
	sudo apt install -y curl git wget htop tmux build-essential jq make lz4 gcc unzip liblz4-tool clang cmake build-essential screen cargo
	
	# 安装 rustup
	curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
	
    # 安装Go
    if command -v go > /dev/null 2>&1; then
        echo "Go 已安装"
    else
        echo "Go 未安装，正在安装..."
        curl -L https://go.dev/dl/go1.22.0.linux-amd64.tar.gz | sudo tar -xzf - -C /usr/local
        echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> $HOME/.bash_profile
        export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
        source $HOME/.bash_profile
    fi
    
    # 克隆仓库
    git clone https://github.com/0glabs/0g-storage-node.git
	#进入对应目录构建
	cd 0g-storage-node
	git submodule update --init
	# 构建存储节点代码
	cargo build --release

	RPC_ADDR="https://jsonrpc.0g-test.paknodesarmy.xyz/"
    RPC_ADDR="https://og-testnet-jsonrpc.itrocket.net"
    RPC_ADDR="https://t0g.brightlystake.com/evm"
	PUBLIC_IP=$(curl -s ifconfig.me)
	sed -i "s|^# *miner_key = \".*\"|miner_key = \"$minerkey\"|" $HOME/0g-storage-node/run/config.toml
    sed -i "s|^# *rpc_listen_address = \".*\"|rpc_listen_address = \"0.0.0.0:5678\"|" $HOME/0g-storage-node/run/config.toml
    sed -i "s|^# *network_boot_nodes = \[\]|network_boot_nodes = \[\"/ip4/54.219.26.22/udp/1234/p2p/16Uiu2HAmTVDGNhkHD98zDnJxQWu3i1FL1aFYeh9wiQTNu4pDCgps\",\"/ip4/52.52.127.117/udp/1234/p2p/16Uiu2HAkzRjxK2gorngB1Xq84qDrT4hSVznYDHj6BkbaE4SGx9oS\",\"/ip4/18.167.69.68/udp/1234/p2p/16Uiu2HAm2k6ua2mGgvZ8rTMV8GhpW71aVzkQWy7D37TTDuLCpgmX\"\]|" $HOME/0g-storage-node/run/config.toml
    sed -i "s|^# *log_sync_start_block_number = 0|log_sync_start_block_number = 401178|" $HOME/0g-storage-node/run/config.toml
	sed -i "s|^# *log_contract_address = \".*\"|log_contract_address = \"0xB7e39604f47c0e4a6Ad092a281c1A8429c2440d3\"|" $HOME/0g-storage-node/run/config.toml
    sed -i "s|^# *mine_contract_address = \".*\"|mine_contract_address = \"0x6176AA095C47A7F79deE2ea473B77ebf50035421\"|" $HOME/0g-storage-node/run/config.toml
    sed -i "s|^# *network_enr_address = \".*\"|network_enr_address = \"$PUBLIC_IP\"|" $HOME/0g-storage-node/run/config.toml
    sed -i "s|^# *blockchain_rpc_endpoint = \".*\"|blockchain_rpc_endpoint = \"$RPC_ADDR\"|" $HOME/0g-storage-node/run/config.toml
	#后台运行
	cd run
    screen -dmS zgs_$storage_node_name $HOME/0g-storage-node/target/release/zgs_node --config config.toml
	echo "部署完成..."
	#view_storage_logs
}

# 修改存储节点RPC
function update_storage_rpc(){
    read -p "存储节点名称: " storage_node_name
    read -p "RPC地址：" RPC_ADDR
    sed -i "s|^ *blockchain_rpc_endpoint = \".*\"|blockchain_rpc_endpoint = \"$RPC_ADDR\"|" $HOME/0g-storage-node/run/config.toml
    screen -dmS zgs_$storage_node_name $HOME/0g-storage-node/target/release/zgs_node --config $HOME/0g-storage-node/run/config.toml
    view_storage_logs
}

# 停止存储节点
function stop_storage_node(){
    read -p "存储节点名称: " storage_node_name
	screen -S zgs_$storage_node_name -X quit
	echo "节点已停止..."
}

# 启动存储节点
function start_storage_node(){
    read -p "存储节点名称: " storage_node_name
    read -p "EVM钱包私钥(不含0x): " minerkey
    sed -i "s/miner_key = \"\"/miner_key = \"$minerkey\"/" $HOME/0g-storage-node/run/config.toml
    #RPC_ADDR=$(grep 'blockchain_rpc_endpoint' $HOME/0g-storage-node/run/config.toml | cut -d '"' -f 2)
	cd 0g-storage-node/run
	screen -dmS zgs_$storage_node_name $HOME/0g-storage-node/target/release/zgs_node --config config.toml
	echo "节点已启动..."
}

# 查看存储节点日志
function view_storage_logs(){
	current_date=$(date +%Y-%m-%d)
	tail -f $HOME/0g-storage-node/run/log/zgs.log.$current_date
}

# 卸载存储节点
function uninstall_storage_node(){
    echo "确定要卸载0gAI存储节点吗？[Y/N]"
    read -r -p "请确认: " response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            echo "开始卸载存储节点..."
            screen -ls | grep 'zgs_' | cut -d. -f1 | awk '{print $1}' | xargs -I {} screen -X -S {} quit
            rm -rf $HOME/0g-storage-node
            echo "存储节点卸载完成。"
            ;;
        *)
            echo "取消卸载操作。"
            ;;
    esac
}

# 修改端口
function service_ports(){
    # 检测端口
    local start_port=9000
    local needed_ports=7
    local count=0
    local ports=()
    while [ "$count" -lt "$needed_ports" ]; do
        if ! ss -tuln | grep -q ":$start_port " ; then
            ports+=($start_port)
            ((count++))
        fi
        ((start_port++))
    done
    echo "可用端口："
    for port in "${ports[@]}"; do
        echo -e "\033[0;32m$port\033[0m"
    done
    
    # 提示用户输入端口配置，允许使用默认值
    read -p "L2 HTTP端口 [默认: 8547]: " port_l2_execution_engine_http
    port_l2_execution_engine_http=${port_l2_execution_engine_http:-8547}
    read -p "L2 WS端口 [默认: 8548]: " port_l2_execution_engine_ws
    port_l2_execution_engine_ws=${port_l2_execution_engine_ws:-8548}
    read -p "请输入L2执行引擎Metrics端口 [默认: 6060]: " port_l2_execution_engine_metrics
    port_l2_execution_engine_metrics=${port_l2_execution_engine_metrics:-6060}
    read -p "请输入L2执行引擎P2P端口 [默认: 30306]: " port_l2_execution_engine_p2p
    port_l2_execution_engine_p2p=${port_l2_execution_engine_p2p:-30306}
    read -p "请输入证明者服务器端口 [默认: 9876]: " port_prover_server
    port_prover_server=${port_prover_server:-9876}
    read -p "请输入Prometheus端口 [默认: 9091]: " port_prometheus
    port_prometheus=${port_prometheus:-9091}
    read -p "请输入Grafana端口 [默认: 3001]: " port_grafana
    port_grafana=${port_grafana:-3001}
    
    # 配置文件
    sed -i "s|PORT_L2_EXECUTION_ENGINE_HTTP=.*|PORT_L2_EXECUTION_ENGINE_HTTP=${port_l2_execution_engine_http}|" .env
    sed -i "s|PORT_L2_EXECUTION_ENGINE_WS=.*|PORT_L2_EXECUTION_ENGINE_WS=${port_l2_execution_engine_ws}|" .env
    sed -i "s|PORT_L2_EXECUTION_ENGINE_METRICS=.*|PORT_L2_EXECUTION_ENGINE_METRICS=${port_l2_execution_engine_metrics}|" .env
    sed -i "s|PORT_L2_EXECUTION_ENGINE_P2P=.*|PORT_L2_EXECUTION_ENGINE_P2P=${port_l2_execution_engine_p2p}|" .env
    sed -i "s|PORT_PROVER_SERVER=.*|PORT_PROVER_SERVER=${port_prover_server}|" .env
    sed -i "s|PORT_PROMETHEUS=.*|PORT_PROMETHEUS=${port_prometheus}|" .env
    sed -i "s|PORT_GRAFANA=.*|PORT_GRAFANA=${port_grafana}|" .env
    sed -i "s|BLOCK_PROPOSAL_FEE=.*|BLOCK_PROPOSAL_FEE=30|" .env
}

# 更新存储节点合约
function update_storage_contract(){
    sed -i "s|^# *log_contract_address = \".*\"|log_contract_address = \"0xB7e39604f47c0e4a6Ad092a281c1A8429c2440d3\"|" $HOME/0g-storage-node/run/config.toml
    sed -i "s|^# *mine_contract_address = \".*\"|mine_contract_address = \"0x6176AA095C47A7F79deE2ea473B77ebf50035421\"|" $HOME/0g-storage-node/run/config.toml
    sed -i "s|^# *log_sync_start_block_number = 0|log_sync_start_block_number = 401178|" $HOME/0g-storage-node/run/config.toml
    sed -i "s| *log_contract_address = \".*\"|log_contract_address = \"0xB7e39604f47c0e4a6Ad092a281c1A8429c2440d3\"|" $HOME/0g-storage-node/run/config.toml
    sed -i "s| *mine_contract_address = \".*\"|mine_contract_address = \"0x6176AA095C47A7F79deE2ea473B77ebf50035421\"|" $HOME/0g-storage-node/run/config.toml
    sed -i "s| *log_sync_start_block_number = 0|log_sync_start_block_number = 401178|" $HOME/0g-storage-node/run/config.toml
    stop_storage_node
    mv $HOME/0g-storage-node/run/db $HOME/0g-storage-node/run/db.bak.$(date +%Y%m%d)
    echo "已将db目录修改为db.bak，如果启动正常可以删除该目录，命令为：rm -rf $HOME/0g-storage-node/run/db.bak"
    start_storage_node
    echo "节点已启动，如下为日志："
    view_storage_logs
}

function check_and_upgrade {
    # 进入项目目录
    project_folder="0g-storage-node"

    cd ~/$project_folder || { echo "Directory ~/project_folder does not exist."; exit 1; }

    # 获取本地版本
    local_version=$(git describe --tags --abbrev=0)

    # 获取远程版本
    git fetch --tags
    remote_version=$(git describe --tags `git rev-list --tags --max-count=1`)

    echo "本地程序版本: $local_version"
    echo "官方程序版本: $remote_version"

    # 比较版本，如果本地版本低于远程版本，则询问用户是否进行升级
    if [ "$local_version" != "$remote_version" ]; then
        read -p "发现官方发布了新的程序版本，是否要升级到： $remote_version? (y/n): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            echo "正在升级..."
            stop_storage_node
            git checkout $remote_version
            git submodule update --init --recursive
            cargo build --release
            start_storage_node
            echo "升级完成，当前本地程序版本： $remote_version."
        else
            echo "取消升级，当前本地程序版本： $local_version."
        fi
    else
        echo "已经是最新版本: $local_version."
    fi
}

# 卸载老节点功能
function uninstall_old_node() {
    echo "本功能是卸载之前的0gAI节点，请先备份好钱包等资产数据！如果没有参与上一期的0gAI测试，无需运行。"
    echo "你确定要卸载0g ai 节点程序吗？这将会删除所有相关的数据。[Y/N]"
    read -r -p "请确认: " response
    
    case "$response" in
        [yY][eE][sS]|[yY]) 
            echo "开始卸载节点程序..."
            pm2 stop evmosd && pm2 delete evmosd
            rm -rf $HOME/.evmosd $HOME/0g-evmos $(which evmosd) 
            echo "节点程序卸载完成。"
            ;;
        *)
            echo "取消卸载操作。"
            ;;
    esac
}

# 主菜单
function main_menu() {
    while true; do
        clear
        echo "=================0gAI 一键部署脚本================="
        echo "当前版本：$current_version"
    	echo "沟通电报群：https://t.me/lumaogogogo"
    	echo "验证者节点：8C64G1T，存储节点：4C16G1T"
    	echo "感谢以下无私的分享者："
    	echo "草边河 发现并验证了卸载老节点的bug"
        echo "Jack Putin 帮助解决拼写错误"
    	echo "==========桃花潭水深千尺，不及汪伦送我情============"
        echo "请选择要执行的操作:"
        echo "---------------验证节点相关选项----------------"
        echo "1. 部署节点 install_node"
        echo "2. 创建钱包 add_wallet"
        echo "3. 导入钱包 import_wallet"
        echo "4. 查看余额 check_balances"
        echo "5. 创建验证者 add_validator"
        echo "6. 查看服务状态 check_service_status"
        echo "7. 查看同步状态 check_sync_status"
        echo "8. 查看日志 view_logs"
        echo "9. 申请出狱 unjail"
        echo "10. 停止节点 stop_node"
        echo "11. 启动节点 start_node"
        echo "12. 质押代币 delegate_aevmos"
        echo "13. 更新PEERS update_peers"
        echo "14. 提取秘钥 show_validator_key"
        echo "15. 下载快照 download_snap"
        echo "11618. 卸载节点"
        echo "---------------存储节点相关选项---------------"
        echo "21. 部署存储节点 install_storage_node"
        echo "22. 查看存储节点日志 view_storage_logs"
        echo "23. 停止存储节点 stop_storage_node"
        echo "24. 启动存储节点 start_storage_node"
        echo "25. 修改存储节点RPC update_storage_rpc"
        echo "26. 更新存储节点合约 update_storage_contract"
        echo "27. 升级存储节点 check_and_upgrade"
        echo "21618. 卸载存储节点 uninstall_storage_node"
        echo "--------------------其他--------------------"
        echo "51618. 卸载老节点 uninstall_old_node"
        echo "0. 退出脚本exit"
        read -p "请输入选项: " OPTION

        case $OPTION in
        1) install_node ;;
        2) add_wallet ;;
        3) import_wallet ;;
        4) check_balances ;;
        5) add_validator ;;
        6) check_service_status ;;
        7) check_sync_status ;;
        8) view_logs ;;
        9) unjail ;;
        10) stop_node ;;
        11) start_node ;;
        12) delegate_aevmos ;;
        13) update_peers ;;
        14) show_validator_key ;;
        15) download_snap ;;
        11618) uninstall_node ;;
        
        21) install_storage_node ;;
        22) view_storage_logs ;;
        23) stop_storage_node ;;
        24) start_storage_node ;;
        25) update_storage_rpc ;;
        26) update_storage_contract ;;
        27) check_and_upgrade ;;
        21618) uninstall_storage_node ;;

        51618) uninstall_old_node ;;
        
        0) echo "退出脚本。"; exit 0 ;;
	    *) echo "无效选项，请重新输入。"; sleep 3 ;;
	    esac
	    echo "按任意键返回主菜单..."
        read -n 1
    done
}

# 检查更新
update_script

# 显示主菜单
main_menu