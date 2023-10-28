# 简介
这是一个登录到HUST\_WIRELESS的脚本，理论上也适用于其他采用锐捷网络认证系统的学校。
# 依赖
bash, curl, xxd, openssl, jq  
对于大多数发行版来说只有jq需要单独安装，其他依赖已经由系统自带  
jq可考虑使用发行版的包管理器安装。如果发行版的仓库中不包含该软件，可考虑前往[jq的release页面](https://github.com/jqlang/jq/releases)直接下载静态编译的二进制程序。
# 用法
见`./login -h`
# License
GPL-2.0-or-later
