#!/bin/bash

set -e

# 脚本保存路径
SCRIPT_PATH="$HOME/0gai.sh"

# 节点安装功能
function install_node() {

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

	# 检查并安装 PM2
    if command -v pm2 > /dev/null 2>&1; then
        echo "PM2 已安装"
    else
        echo "PM2 未安装，正在安装..."
        sudo npm install pm2@latest -g
    fi

	# 更新系统
	sudo apt update && sudo apt install -y curl git wget htop tmux build-essential jq make lz4 gcc unzip liblz4-tool clang cmake build-essential screen cargo

    # 安装Go
    sudo rm -rf /usr/local/go
    curl -L https://go.dev/dl/go1.22.0.linux-amd64.tar.gz | sudo tar -xzf - -C /usr/local
    echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> $HOME/.bash_profile
    export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
    source $HOME/.bash_profile

    # 安装所有二进制文件
    git clone https://github.com/0glabs/0g-evmos.git
    cd 0g-evmos
    git checkout v1.0.0-testnet
    make install
    evmosd version

	# 设置变量
    read -r -p "节点名称: " NODE_MONIKER
    export NODE_MONIKER=$NODE_MONIKER
    # 配置evmosd
    echo 'export MONIKER="$NODE_MONIKER"' >> ~/.bash_profile
    # 可以放到创建钱包的时候创建
    #echo 'export WALLET_NAME="wallet"' >> ~/.bash_profile

    source $HOME/.bash_profile

    # 获取初始文件和地址簿
    cd $HOME
    evmosd init $NODE_MONIKER --chain-id zgtendermint_9000-1
    evmosd config chain-id zgtendermint_9000-1
    evmosd config node tcp://localhost:26657
    evmosd config keyring-backend os 

    # 配置节点
    wget https://github.com/0glabs/0g-evmos/releases/download/v1.0.0-testnet/genesis.json -O $HOME/.evmosd/config/genesis.json

    # 下载快照
    PEERS="1248487ea585730cdf5d3c32e0c2a43ad0cda973@peer-zero-gravity-testnet.trusted-point.com:26326" && \
    SEEDS="8c01665f88896bca44e8902a30e4278bed08033f@54.241.167.190:26656,b288e8b37f4b0dbd9a03e8ce926cd9c801aacf27@54.176.175.48:26656,8e20e8e88d504e67c7a3a58c2ea31d965aa2a890@54.193.250.204:26656,e50ac888b35175bfd4f999697bdeb5b7b52bfc06@54.215.187.94:26656" && \
    sed -i -e "s/^seeds *=.*/seeds = \"$SEEDS\"/; s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" $HOME/.evmosd/config/config.toml

    # 设置gas
    sed -i "s/^minimum-gas-prices *=.*/minimum-gas-prices = \"0.00252aevmos\"/" $HOME/.evmosd/config/app.toml

    # 使用 PM2 启动节点进程
    pm2 start evmosd -- start && pm2 save && pm2 startup

    # 使用 pm2 停止 ogd 服务
    pm2 stop evmosd

    # 下载最新的快照
    wget https://rpc-zero-gravity-testnet.trusted-point.com/latest_snapshot.tar.lz4

    # 备份当前的验证者状态文件
    cp $HOME/.evmosd/data/priv_validator_state.json $HOME/.evmosd/priv_validator_state.json.backup

    # 重置数据目录同时保留地址簿
    evmosd tendermint unsafe-reset-all --home $HOME/.evmosd --keep-addr-book

    # 将快照解压直接到 .evmosd 目录
    lz4 -d -c ./latest_snapshot.tar.lz4 | tar -xf - -C $HOME/.evmosd

    # 恢复验证者状态文件的备份
    mv $HOME/.evmosd/priv_validator_state.json.backup $HOME/.evmosd/data/priv_validator_state.json

    # 使用 pm2 重启 evmosd 服务并跟踪日志
    pm2 start evmosd -- start
    pm2 logs evmosd

    # 检查节点的同步状态
    evmosd status | jq .SyncInfo
    echo '====================== 安装完成 ==========================='

}

# 查看0gai 服务状态
function check_service_status() {
    pm2 list
}

# 0gai 节点日志查询
function view_logs() {
    pm2 logs evmosd
}

# 卸载节点功能
function uninstall_node() {
    echo "你确定要卸载0g ai 节点程序吗？这将会删除所有相关的数据。[Y/N]"
    read -r -p "请确认: " response

    case "$response" in
        [yY][eE][sS]|[yY]) 
            echo "开始卸载节点程序..."
            pm2 stop evmosd && pm2 delete evmosd
            rm -rf $HOME/.evmosd $HOME/evmos $(which evmosd)
            echo "节点程序卸载完成。"
            ;;
        *)
            echo "取消卸载操作。"
            ;;
    esac
}

# 创建钱包
function add_wallet() {
	read -p "请输入钱包名称: " wallet_name
    evmosd keys add "$wallet_name"
    echo "EVM钱包地址，用于领水："
    echo "0x$(evmosd debug addr $(evmosd keys show $wallet_name -a) | grep hex | awk '{print $3}')"
}

# 导入钱包
function import_wallet() {
	read -p "请输入钱包名称: " wallet_name
    evmosd keys add "$wallet_name" --recover
}

# 查询余额
function check_balances() {
    read -p "请输入钱包地址: " wallet_address
    evmosd query bank balances "$wallet_address" 
}

# 查看节点同步状态
function check_sync_status() {
    evmosd status 2>&1 | jq .SyncInfo
}

# 创建验证者
function add_validator() {
	
	read -p "钱包名称: " wallet_name
	read -p "验证者名字: " validator_name
	
	evmosd tx staking create-validator \
	  --amount=10000000000000000aevmos \
	  --pubkey=$(evmosd tendermint show-validator) \
	  --moniker=$validator_name \
	  --chain-id=zgtendermint_9000-1 \
	  --commission-rate=0.05 \
	  --commission-max-rate=0.10 \
	  --commission-max-change-rate=0.01 \
	  --min-self-delegation=1 \
	  --from=$wallet_name \
	  --identity="" \
	  --website="" \
	  --details="Support by breaddog" \
	  --gas=500000 \
	  --gas-prices=99999aevmos \
	  -y

}

function stop_node(){
	pm2 stop evmosd
}

function start_node(){
	pm2 start evmosd -- start
}

function install_storage_node() {
 
	# 克隆仓库
	git clone https://github.com/0glabs/0g-storage-node.git
	
	#进入对应目录构建
	cd 0g-storage-node
	git submodule update --init
	
	# 构建代码
	cargo build --release
	
	#后台运行
	cd run
	screen -dmS zgs_node_session ../target/release/zgs_node --config config.toml
	echo '====================== 安装完成 ==========================='
	
}

function stop_storage_node(){
	screen -S zgs_node_session -X quit
}

function start_storage_node(){
	cd 0g-storage-node/run
	screen -dmS zgs_node_session ../target/release/zgs_node --config config.toml
}

function view_storage_logs(){
	current_date=$(date +%Y-%m-%d)
	tail -f $HOME/0g-storage-node/run/log/zgs.log.$current_date
}

# 出狱代码
function unjail(){
	read -p "钱包名称: " wallet_name
	evmosd tx slashing unjail --from $wallet_name --gas=500000 --gas-prices=99999aevmos -y
}


# 主菜单
function main_menu() {
    while true; do
        clear
        echo "===============0gAI一键部署脚本==============="
    	echo "BreadDog出品，电报：https://t.me/breaddog"
    	echo "最低配置：2C8G300G，推荐配置：8C16G500G"
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
        echo "9. 停止节点"
        echo "10. 启动节点"
        echo "---------------存储节点相关选项---------------"
        echo "11. 部署存储节点"
        echo "12. 查看存储节点日志"
        echo "13. 停止存储节点"
        echo "14. 启动存储节点"
        echo "--------------------其他--------------------"
        echo "15. 卸载节点"
        echo "16. 申请出狱"
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
        9) stop_node ;;
        10) start_node ;;
        11) install_storage_node ;;
        12) view_storage_logs ;;
        13) stop_storage_node ;;
        14) start_storage_node ;;
        15) uninstall_node ;;
        16) unjail ;;
        0) echo "退出脚本。"; exit 0 ;;
	    *) echo "无效选项，请重新输入。"; sleep 3 ;;
	    esac
	    echo "按任意键返回主菜单..."
        read -n 1
    done
}

# 显示主菜单
main_menu