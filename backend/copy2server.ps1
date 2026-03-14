scp -r *.json *.js *.cjs parsers/ public/ root@192.168.1.118:/data/www/umaovd/
ssh root@192.168.1.118 "pm2 restart umao-vd"