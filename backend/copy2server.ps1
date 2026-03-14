# 将本地代码同步到远程服务器并重启服务
# 用途：部署更新到生产环境

# 复制所有必要的文件到服务器
scp -r *.json *.js *.cjs parsers/ public/ root@192.168.1.118:/data/www/umaovd/

# 在服务器上安装依赖
ssh root@192.168.1.118 "npm install --prefix /data/www/umaovd/"

# 重启pm2服务
ssh root@192.168.1.118 "pm2 restart umao-vd"