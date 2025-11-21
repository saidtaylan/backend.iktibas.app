#!/bin/bash
sudo dnf update -y
sudo dnf install epel-release make -y

BASE_DIRECTORY=/opt/backend.iktibas.app
DOMAIN=api.iktibas.app

rm -f /etc/nginx/nginx.conf
ln -s $BASE_DIRECTORY/nginx/nginx.conf /etc/nginx/nginx.conf
ln -s $BASE_DIRECTORY/nginx/api.iktibas.app.conf /etc/nginx/conf.d/
semanage port -a -t http_port_t -p tcp 8080

sudo dnf install certbot python3-certbot-nginx -y
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo certbot --nginx -d $DOMAIN
sudo setsebool -P httpd_can_network_connect 1

echo "Port 2001" > /etc/ssh/sshd_config.d/51-custom.conf
firewall-cmd --permanent --add-port=2001/tcp
firewall-cmd --permanent --remove-port=22/tcp
systemctl restart sshd


echo "0 3 * * * $BASE_DIRECTORY/scripts/db-backup.sh >> /var/log/supabase/db-backup.log 2>&1" > /etc/cron.d/supabase-db-backup
