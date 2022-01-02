# HUST_WIRELESS登陆脚本
- 每次登录时会自动从接口处动态获取最新的公钥进行加密，再也不怕学校突然换密钥了
- 依赖jq curl openssl bash sed. 其中需要单独安装的只有jq

# 用法
- `./login.sh -u [UserId] -p [password]`
