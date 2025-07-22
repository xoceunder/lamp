#!/bin/bash
# Auto Install and Setup LEMP Example: sudo bash Lemp_Stack_20.04.sh -p MyPassword
# By XoceUnder - https://github.com/xoceunder
# -*- coding: utf-8 -*-

# Defining Colors for text output
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
CYAN=$(tput setaf 6)
NORMAL=$(tput sgr0)
REVERSE=$(tput smso)
UNDERLINE=$(tput smul)
Version=$(lsb_release -sd)

# prints colored text
printc() {
    limit=0
    if [ "$3" ]; then limit=$3; fi
    printf "%s ┌──────────────────────────────────────────┐ %s\n" "$2" "${NORMAL}"
    for i in $(seq 1 $limit); do printf "%s │                                          │ %s\n" "$2" "${NORMAL}"; done
	readarray -t array < <(IFS=,; eval "printf '%s\n' "$1" | fmt -w 40")
	for i in "${array[@]}"; do
	  n=`expr length "${i}"`
          printf "%s │ %*s%s%*s │ %s\n"  "$2" $((20-($n/2))) " " "$i" $((40-(20-($n/2))-$n)) " " "${NORMAL}"
	done
    for i in $(seq 1 $limit); do printf "%s │                                          │ %s\n" "$2" "${NORMAL}"; done
    printf "%s └──────────────────────────────────────────┘ %s" "$2" "${NORMAL}"
    echo " "
}

printc "Auto Install LEMP Stack as Nginx MariaDB PHP Sistem ${Version}" ${GREEN} 2
echo -n "Installation System? [Y/n]? "
read -n1 type
echo -en "\ec"
if [[ "$type" = "Y" || "$type" = "y" ]]; then
 printc "Update System" ${YELLOW}
 sudo apt update > /dev/null 2>&1
 sudo apt full-upgrade -y > /dev/null 2>&1

 if [ $? -eq 0 ]; then
  echo -en "\ec"
  printc "Configuring MySQL" ${YELLOW}
  read -p "Enter MySQL Root Password:? " pass
  
  if [ -n "${pass}" ] && [[ ! "$pass" =~ ^[[:digit:]]+$ ]]; then
    echo -en "\ec"
    printc "Installing Nginx v1.25 " ${YELLOW}
	sudo apt install curl gnupg2 ca-certificates apt-transport-https software-properties-common lsb-release -y > /dev/null 2>&1
	curl -fsSL https://nginx.org/keys/nginx_signing.key  | sudo gpg --dearmor -o /usr/share/keyrings/nginx-keyring.gpg > /dev/null 2>&1
	echo "deb [arch=amd64 signed-by=/usr/share/keyrings/nginx-keyring.gpg] https://nginx.org/packages/ubuntu `lsb_release -cs` nginx" | sudo tee /etc/apt/sources.list.d/nginx.list > /dev/null 2>&1
    sudo apt update > /dev/null 2>&1	
    sudo apt install nginx -y > /dev/null 2>&1
    sudo systemctl enable nginx > /dev/null 2>&1
    sudo systemctl start nginx > /dev/null 2>&1
	
    printc "Configure the Firewall Add the SSH and HTTP" ${YELLOW}
    sudo ufw allow ssh > /dev/null 2>&1
    sudo ufw allow http > /dev/null 2>&1
    sudo ufw allow https > /dev/null 2>&1
    sudo ufw enable -y > /dev/null 2>&1
	
    printc "Installing MariaDB v10.3 " ${YELLOW}
	sudo apt install mariadb-server -y > /dev/null 2>&1
    systemctl start mariadb > /dev/null 2>&1
    systemctl enable mariadb > /dev/null 2>&1
	mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$pass'; flush privileges;" > /dev/null 2>&1
    sudo apt purge expect -y > /dev/null 2>&1
	sudo apt autoremove -y > /dev/null 2>&1
	
    printc "Installing PHP v8.2" ${YELLOW}
	sudo add-apt-repository ppa:ondrej/php -y > /dev/null 2>&1
	sudo apt update > /dev/null 2>&1
	sudo apt install php8.2 php8.2-{cli,fpm,curl,mysql,mysqlnd,gd,opcache,zip,intl,common,bcmath,imagick,xmlrpc,readline,memcached,redis,mbstring,apcu,xml,dom,memcache,fileinfo} php-pear -y > /dev/null 2>&1
    systemctl start php8.2-fpm > /dev/null 2>&1
    systemctl enable php8.2-fpm > /dev/null 2>&1
	
    printc "Install PhpMyAdmin" ${YELLOW}
    sudo apt install zip -y > /dev/null 2>&1
    DATA="$(wget https://www.phpmyadmin.net/home_page/version.txt -q -O-)"
    URL="$(echo "$DATA" | tail +3 | cut -d# -f2)"
    OUTPUT_FILE_NAME="phpMyAdmin.zip"
    wget -O "$OUTPUT_FILE_NAME" "$URL" > /dev/null 2>&1
    DOWNLOADED_FILE_NAME="$(basename "$URL")"
    EXTRACT_FOLDER_NAME="${DOWNLOADED_FILE_NAME%.zip}"
    unzip "$OUTPUT_FILE_NAME" > /dev/null 2>&1
    rm $OUTPUT_FILE_NAME > /dev/null 2>&1
    sudo rm -rf /usr/share/phpmyadmin/ > /dev/null 2>&1
    sudo mv "$EXTRACT_FOLDER_NAME/" /usr/share/phpmyadmin
	
    printc "Configuring System" ${YELLOW}
    mkdir /home/www > /dev/null 2>&1
    sudo chown -R www-data:www-data /home/www > /dev/null 2>&1
    sudo sed -i '2,$ s/keepalive_timeout 65;/keepalive_timeout 2;/' /etc/nginx/nginx.conf
    sudo sed -i '2,$ s/# server_tokens off;/server_tokens off;/' /etc/nginx/nginx.conf
    sudo sed -i '2,$ s/max_execution_time = 30/max_execution_time = 300/' /etc/php/8.2/fpm/php.ini
    sudo sed -i '2,$ s/upload_max_filesize = 2M/upload_max_filesize = 200M/' /etc/php/8.2/fpm/php.ini
    sudo sed -i '2,$ s/display_errors = Off/display_errors = On/' /etc/php/8.2/fpm/php.ini
	
    printc "Restart Nginx - MariaDB - Php  " ${YELLOW}
    sudo systemctl restart php8.2-fpm > /dev/null 2>&1
    sudo systemctl restart nginx > /dev/null 2>&1
    sudo systemctl restart mariadb > /dev/null 2>&1

    printc "Installation completed!" ${GREEN} 2
	
  else
  
    printc "Invalid password! Try again" ${RED}
	
  fi
  
 fi

else

 printc "Cancel updated!" ${RED}
	
fi
exit 0
