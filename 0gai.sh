#!/bin/bash

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
    
    0gchaind init $NODE_MONIKER --chain-id zgtendermint_16600-1
    0gchaind config chain-id zgtendermint_16600-1
    
    rm ~/.0gchain/config/genesis.json
    wget -P ~/.0gchain/config https://github.com/0glabs/0g-chain/releases/download/v0.2.3/genesis.json
    0gchaind validate-genesis
    wget -O $HOME/.0gchain/config/addrbook.json https://snapshots-testnet.nodejumper.io/0g-testnet/addrbook.json
    
    # 配置种子
    SEEDS="265120a9bb170cf21198aabf88f7908c9944897c@54.241.167.190:26656,497f865d8a0f6c830e2b73009a01b3edefb22577@54.176.175.48:26656,ffc49903241a4e442465ec78b8f421c56b3ae3d4@54.193.250.204:26656,f37bc8623bfa4d8e519207b965a24a288f3213d8@18.166.164.232:26656"
    sed -i "s/seeds = \"\"/seeds = \"$SEEDS\"/" $HOME/.0gchain/config/config.toml
    
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
    sudo journalctl -f -u 0gchaind.service
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
	read -p "请输入钱包名称: " wallet_name
    0gchaind keys add $wallet_name --eth
    echo "输入钱包密码，生成0x开头的钱包地址："
    echo "0x$(0gchaind debug addr $(0gchaind keys show $wallet_name -a) | grep hex | awk '{print $3}')"
}

# 导入钱包
function import_wallet() {
	read -p "请输入钱包名称: " wallet_name
    0gchaind keys add $wallet_name --recover --eth
    echo "0x$(0gchaind debug addr $(0gchaind keys show $wallet_name -a) | grep hex | awk '{print $3}')"
}

# 查询余额
function check_balances() {
    read -p "请输入钱包地址: " wallet_address
    0gchaind query bank balances "$wallet_address"
}

# 查看节点同步状态
function check_sync_status() {
    0gchaind status 2>&1 | jq .SyncInfo
}

# 创建验证者
function add_validator() {
	
	read -p "钱包名称: " wallet_name
	read -p "验证者名字: " validator_name
	
	evmosd tx staking create-validator \
	  --amount=1000000ua0gi \
	  --pubkey=$(0gchaind tendermint show-validator) \
	  --moniker=$validator_name \
	  --chain-id=zgtendermint_16600-1 \
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
    read -p "请输入钱包名称: " wallet_name
    read -p "请输入质押代币数量: " math
    0gchaind tx staking delegate $(0gchaind keys show $wallet_name --bech val -a)  ${math}ua0gi --from $wallet_name  --gas=auto --gas-adjustment=1.4 -y
}

# 代币转账
function send_aevmos(){

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
	read -p "钱包名称: " wallet_name
	# 查看入狱
	#0gchaind tx slashing unjail --from <key_name> --gas=500000 --gas-prices=99999neuron -y
	0gchaind tx slashing unjail --from $wallet_name --gas=auto --gas-prices=1.4 -y
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
	miner_id=$(openssl rand -hex 32)
	RPC_ADDR="https://jsonrpc.0g-test.paknodesarmy.xyz/"
	PUBLIC_IP=$(curl -s ifconfig.me)
	sed -i "s|^# *miner_key = \".*\"|miner_key = \"$minerkey\"|" $HOME/0g-storage-node/run/config.toml
	sed -i "s|^# *miner_id = \".*\"|miner_id = \"$miner_id\"|" $HOME/0g-storage-node/run/config.toml
	sed -i "s|^# *log_contract_address = \".*\"|log_contract_address = \"0x8873cc79c5b3b5666535C825205C9a128B1D75F1\"|" $HOME/0g-storage-node/run/config.toml
    sed -i "s|^# *mine_contract_address = \".*\"|mine_contract_address = \"0x85F6722319538A805ED5733c5F4882d96F1C7384\"|" $HOME/0g-storage-node/run/config.toml
    sed -i "s|^# *network_enr_address = \".*\"|network_enr_address = \"$PUBLIC_IP\"|" $HOME/0g-storage-node/run/config.toml
    sed -i "s|^# *blockchain_rpc_endpoint = \".*\"|blockchain_rpc_endpoint = \"$RPC_ADDR\"|" $HOME/0g-storage-node/run/config.toml
	#后台运行
	cd run
    screen -dmS zgs_$storage_node_name $HOME/0g-storage-node/target/release/zgs_node --config config.toml
	echo "部署完成..."
	#view_storage_logs
}

# 修改RPC
function update_rpc(){
    read -p "存储节点名称: " storage_node_name
    read -p "RPC地址：" RPC_ADDR
    sed -i 's/blockchain_rpc_endpoint = ".*"/blockchain_rpc_endpoint = "$RPC_ADDR"/' $HOME/0g-storage-node/run/config.toml
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
    	echo "沟通电报群：https://t.me/lumaogogogo"
    	echo "验证者节点：8C64G1T，存储节点：4C16G1T"
    	echo "感谢以下无私的分享者："
    	echo "草边河 发现并验证了卸载老节点的bug"
    	echo "===========桃花潭水深千尺，不及汪伦送我情============="
        echo "请选择要执行的操作:"
        echo "---------------验证节点相关选项----------------"
        echo "1. 部署节点"
        echo "2. 创建钱包"
        echo "3. 导入钱包"
        echo "4. 查看余额"
        echo "5. 创建验证者"
        echo "6. 查看服务状态"
        echo "7. 查看同步状态"
        echo "8. 查看日志"
        echo "9. 申请出狱"
        echo "10. 停止节点"
        echo "11. 启动节点"
        echo "13. 质押代币"
        echo "14. 更新PEERS"
        echo "15. 代币转账"
        echo "16. 提取秘钥"
        echo "11618. 卸载节点"
        echo "---------------存储节点相关选项---------------"
        echo "21. 部署存储节点"
        echo "22. 查看存储节点日志"
        echo "23. 停止存储节点"
        echo "24. 启动存储节点"
        echo "25. 修改RPC"
        echo "21618. 卸载存储节点"
        echo "--------------------其他--------------------"
        echo "51618. 卸载老节点"
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
        14) send_aevmos ;;
        15) show_validator_key ;;
        11618) uninstall_node ;;
        
        21) install_storage_node ;;
        22) view_storage_logs ;;
        23) stop_storage_node ;;
        24) start_storage_node ;;
        25) update_rpc ;;
        21618) uninstall_storage_node ;;

        51618) uninstall_old_node ;;
        
        0) echo "退出脚本。"; exit 0 ;;
	    *) echo "无效选项，请重新输入。"; sleep 3 ;;
	    esac
	    echo "按任意键返回主菜单..."
        read -n 1
    done
}

# 显示主菜单
main_menu