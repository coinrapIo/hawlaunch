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
```
过程如果发生错误随时反馈。 可以在自己的代码和逻辑问题点，声明event, 然后在相关代码行emit事件查看。有必要时使用 dapp debug out/xxxxx.t.sol.json 进行调试。