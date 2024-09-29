#!/bin/bash

curl -s https://raw.githubusercontent.com/ziqing888/logo.sh/main/logo.sh | bash

sleep 3

ARCH=$(uname -m)

show() {
    echo -e "\033[1;35m$1\033[0m"
}

# 检查并安装 jq
if ! command -v jq &> /dev/null; then
    show "未找到 jq，正在安装..."
    sudo apt-get update
    sudo apt-get install -y jq > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        show "安装 jq 失败，请检查您的软件包管理器。"
        exit 1
    fi
fi

# 检查最新版本
check_latest_version() {
    for i in {1..3}; do
        LATEST_VERSION=$(curl -s https://api.github.com/repos/hemilabs/heminetwork/releases/latest | jq -r '.tag_name')
        if [ -n "$LATEST_VERSION" ]; then
            show "可用的最新版本：$LATEST_VERSION"
            return 0
        fi
        show "尝试 $i：获取最新版本失败。正在重试..."
        sleep 2
    done

    show "在尝试 3 次后仍未获取到最新版本。请检查您的互联网连接或 GitHub API 限制。"
    exit 1
}

check_latest_version

download_required=true

# 检查架构并决定是否下载
if [ "$ARCH" == "x86_64" ]; then
    if [ -d "heminetwork_${LATEST_VERSION}_linux_amd64" ]; then
        show "x86_64 的最新版本已下载，跳过下载。"
        cd "heminetwork_${LATEST_VERSION}_linux_amd64" || { show "无法更改目录。"; exit 1; }
        download_required=false  # 设置标志为 false
    fi
elif [ "$ARCH" == "arm64" ]; then
    if [ -d "heminetwork_${LATEST_VERSION}_linux_arm64" ]; then
        show "arm64 的最新版本已下载，跳过下载。"
        cd "heminetwork_${LATEST_VERSION}_linux_arm64" || { show "无法更改目录。"; exit 1; }
        download_required=false  # 设置标志为 false
    fi
fi

# 下载最新版本
if [ "$download_required" = true ]; then
    if [ "$ARCH" == "x86_64" ]; then
        show "正在下载 x86_64 架构版本..."
        wget --quiet --show-progress "https://github.com/hemilabs/heminetwork/releases/download/$LATEST_VERSION/heminetwork_${LATEST_VERSION}_linux_amd64.tar.gz" -O "heminetwork_${LATEST_VERSION}_linux_amd64.tar.gz"
        tar -xzf "heminetwork_${LATEST_VERSION}_linux_amd64.tar.gz" > /dev/null
        cd "heminetwork_${LATEST_VERSION}_linux_amd64" || { show "无法更改目录。"; exit 1; }
    elif [ "$ARCH" == "arm64" ]; then
        show "正在下载 arm64 架构版本..."
        wget --quiet --show-progress "https://github.com/hemilabs/heminetwork/releases/download/$LATEST_VERSION/heminetwork_${LATEST_VERSION}_linux_arm64.tar.gz" -O "heminetwork_${LATEST_VERSION}_linux_arm64.tar.gz"
        tar -xzf "heminetwork_${LATEST_VERSION}_linux_arm64.tar.gz" > /dev/null
        cd "heminetwork_${LATEST_VERSION}_linux_arm64" || { show "无法更改目录。"; exit 1; }
    else
        show "不支持的架构：$ARCH"
        exit 1
    fi
else
    show "跳过下载，因为最新版本已经存在。"
fi

echo
show "您想要创建多少个钱包？"
read -p "输入钱包数量： " wallet_count

# 验证用户输入的数量
if ! [[ "$wallet_count" =~ ^[0-9]+$ ]] || [ "$wallet_count" -le 0 ]; then
    show "无效的输入。请输入一个正整数。"
    exit 1
fi

> wallet.txt

# 生成钱包
for i in $(seq 1 $wallet_count); do
    echo
    show "正在生成钱包 $i..."
    ./keygen -secp256k1 -json -net="testnet" > "wallet_$i.json"

    if [ $? -ne 0 ]; then
        show "生成钱包 $i 失败。"
        exit 1
    fi

    pubkey_hash=$(jq -r '.pubkey_hash' "wallet_$i.json")
    priv_key=$(jq -r '.private_key' "wallet_$i.json")
    ethereum_address=$(jq -r '.ethereum_address' "wallet_$i.json")

    echo "钱包 $i - 以太坊地址：$ethereum_address" >> ~/PoP-Mining-Wallets.txt
    echo "钱包 $i - BTC 地址：$pubkey_hash" >> ~/PoP-Mining-Wallets.txt
    echo "钱包 $i - 私钥：$priv_key" >> ~/PoP-Mining-Wallets.txt
    echo "--------------------------------------" >> ~/PoP-Mining-Wallets.txt

    show "钱包 $i 的详细信息已保存到 wallet.txt"

    show "加入： https://discord.gg/hemixyz"
    show "从水龙头频道请求此地址的水龙头：$pubkey_hash"
    echo
    read -p "您是否已请求钱包 $i 的水龙头？(y/N): " faucet_requested
    if [[ ! "$faucet_requested" =~ ^[Yy]$ ]]; then
        show "请在继续之前请求水龙头。"
        exit 1
    fi
done
sleep 3
echo
read -p "输入静态费用（仅数字，推荐：100-200）： " static_fee
echo

for i in $(seq 1 $wallet_count); do
    priv_key=$(jq -r '.private_key' "wallet_$i.json")

    cat << EOF | sudo tee /etc/systemd/system/hemi_wallet_$i.service > /dev/null
[Unit]
Description=Hemi Network PoP 挖矿钱包 $i
After=network.target

[Service]
WorkingDirectory=$(pwd)
ExecStart=$(pwd)/popmd
Environment="POPM_BTC_PRIVKEY=$priv_key"
Environment="POPM_STATIC_FEE=$static_fee"
Environment="POPM_BFG_URL=wss://testnet.rpc.hemi.network/v1/ws/public"
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable hemi_wallet_$i.service
    sudo systemctl start hemi_wallet_$i.service
    show "钱包 $i 的 PoP 挖矿已启动。"
done

show "所有钱包的 PoP 挖矿已成功启动。"
