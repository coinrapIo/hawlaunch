##  环境配置
本项目采用了[dapptools](https://github.com/dapphub)及其所提供一套合约库。目前觉得主要优势是：

* 命令行兼容： 编译，测试，部署都基于dapptools工具，能够方便地基于源代码和命令行完成。对外部环境依赖极少。
* 测试环境友好：更符合传统程序开的测试方法和模式。
* 配制和定制性强： 无论是集成dappsys提供的库，还是自己的合约库，目前都以`.gitmodules`的方式集成到项目。
* 支单步调试： `dapp debug out/C2CMkt.t.sol.json`， 即可以对指定的合约或测试方式进行跟踪和调试。

相关的合约库： https://dappsys.readthedocs.io/en/latest/

#### 安装dapptools

* 参考： https://github.com/dapphub/dapptools

```
nix-env -if https://github.com/cachix/cachix/tarball/master --substituters https://cachix.cachix.org --trusted-public-keys cachix.cachix.org-1:eWNHQldwUO7G2VkjpnjDbWwy4KQ/HNxht7H4SSoMckM=

git clone --recursive https://github.com/dapphub/dapptools $HOME/.dapp/dapptools
nix-env -f $HOME/.dapp/dapptools -iA dapp seth solc hevm ethsign
```

安装完成后，可以使用 `dapp, seth, ethsign`等命令行工具。对于本项目，在`git clone`之后，使用`git update --recursive` 下截全部依赖库。

#### 编译

```
dapp build
```

#### 测试

```
cd c2c_contract
dapp test

dapp create C2CMkt 0x897eeaF88F2541Df86D61065e34e7Ba13C111CB8 1000000 --gas=7400000
dapp create CoinRapGateway --gas=7400000
```
过程如果发生错误随时反馈。 可以在自己的代码和逻辑问题点，声明event, 然后在相关代码行emit事件查看。有必要时使用 dapp debug out/xxxxx.t.sol.json 进行调试。


#### 部署kovan后的基本设置

~/.sethrc 文件配置如下

```
export SETH_CHAIN=kovan
export ETH_FROM=897eeaF88F2541Df86D61065e34e7Ba13C111CB8
export ETH_KEYSTORE=/home/dust/.ethereum/keystore
export ETH_KEYSTORE=/home/dust/.ethereum/pwd/testnet.pwd
export ETH_RPC_URL=https://kovan.infura.io/v3/7f64cd98c4f14db1bd868b7e1a57649e
```

其中keystore文件可以使用` keystore.tar.gz `中的keystore文件放到`ETH_KEYSTORE`目录． **虽然是测试环境，也需要注意keystore文件的安全**

```
RAP=0xA3d472DDE15D4c8e4CdFAA90baaAa4384E7D5f7F
T8=0xcE76efc1d64580b0fdfBAcA2960B7522D6129bf3
SMT=0xa03d360215c62afd2d324aabda422b92d78b7684

# send 10^7 rap to 0x0fc7ebf20B23437E359Bba1D214a4ED0ad72f577
seth send $RAP 'transfer(address,uint256)' 0x0fc7ebf20B23437E359Bba1D214a4ED0ad72f577 $(seth --to-uint256 $(seth --to-wei 10000000 ether))
# send 10^7 smt to 0x0fc7ebf20B23437E359Bba1D214a4ED0ad72f577
seth send $SMT 'transfer(address,uint256)' 0x0fc7ebf20B23437E359Bba1D214a4ED0ad72f577 $(seth --to-uint256 $(seth --to-wei 10000000 ether))
# send 10^7 t8 to 0x0fc7ebf20B23437E359Bba1D214a4ED0ad72f577, the decimal is 8．
seth send $T8 'transfer(address,uint256)' 0x0fc7ebf20B23437E359Bba1D214a4ED0ad72f577 $(seth --to-uint256 $(seth --to-wei  0.001 ether))
```

kovan:

```
dapp create OfferData 1000000 --gas 6000000
OFFER=0x5e78f5125bb080b20283fb70f160bc888baacfba
dapp create C2CMkt $OFFER --gas 6000000
dapp create CoinRapGateway --gas 6000000

C2C=0x98ee49e6c35a229d924edddbaea232d0290c9265
GATEWAY=0xe35f8f0c2c6cd81fef5d260eae7fb3b95fc3c33e

# set c2c.gateway
seth send $C2C "setCoinRapGateway(address)" $GATEWAY

seth send $OFFER 'set_c2c_mkt(address)' $C2C

# set c2c.listed tokens
SMT=0xa03D360215C62afD2d324aaBda422B92d78b7684
seth send $C2C "setToken(address,bool)" $SMT true
seth send $C2C "setToken(address,bool)" $RAP true
seth send $C2C "setToken(address,bool)" $T8 true



# set gateway.c2c
seth send $GATEWAY "set_c2c_mkt(address)" $C2C
seth send $GATEWAY "set_offer_data(address)" $OFFER


```

mainnet:

```
dapp create OfferData 1000000 --gas 6000000
OFFER=0xa57C4C75c0023202D919C6200baaF1A4166f19c4
dapp create C2CMkt $OFFER --gas 6000000


C2C=0x06417ebef8f73a16b050f12aa31d77027f6d49a5
GATEWAY=0xf7c809fcf18318e7a13866868b9e74a3b532de9d
seth send $C2C "setCoinRapGateway(address)" $GATEWAY
seth send $OFFER 'set_c2c_mkt(address)' $C2C

AE=0x5ca9a71b1d01849c0a95490cc00559717fcf0d1d
SNT=0x744d70fdbe2ba4cf95131626614a1763df805b9e
OMG=0xd26114cd6EE289AccF82350c8d8487fedB8A0C07
BNB=0xB8c77482e45F1F44dE1745F52C74426C631bDD52
LINK=0x514910771af9ca656af840dff83e8264ecf986ca
KNC=0xdd974d5c2e2928dea5f71b9825b8b646686bd200
SMT=0x55f93985431fc9304077687a35a1ba103dc1e081
DAI=0x89d24a6b4ccb1b6faa2625fe562bdd9a23260359
IOST=0xfa1a856cfa3409cfa145fa4e20eb270df3eb21ab
ZIL=0x05f4a42e251f2d52b8ed15e9fedaacfcef1fad27
TUSD=0x8dd5fbce2f6a956c3022ba3663759011dd51e73e
TAC=0xca694eb79eF355eA0999485d211E68F39aE98493
GUSD=0x056Fd409E1d7A124BD7017459dFEa2F387b6d5Cd

seth send $C2C "setToken(address,bool)" $AE true
seth send $C2C "setToken(address,bool)" $SNT true
seth send $C2C "setToken(address,bool)" $OMG true
seth send $C2C "setToken(address,bool)" $BNB true
seth send $C2C "setToken(address,bool)" $LINK true
seth send $C2C "setToken(address,bool)" $KNC true
seth send $C2C "setToken(address,bool)" $SMT true
seth send $C2C "setToken(address,bool)" $DAI true
seth send $C2C "setToken(address,bool)" $IOST true
seth send $C2C "setToken(address,bool)" $ZIL true
seth send $C2C "setToken(address,bool)" $TUSD true
seth send $C2C "setToken(address,bool)" $TAC true
seth send $C2C "setToken(address,bool)" $GUSD true


seth send $GATEWAY "set_c2c_mkt(address)" $C2C

```