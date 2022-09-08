#!/bin/bash
# Auto Install and Setup LEMP Example:sudo bash lemp18.4.sh -p MyPassword
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

printc "Auto Install LEMP as Nginx MySQL PHP Sistem ${Version}" ${GREEN} 2
echo -n "Installation System? [Y/n]? "
read -n1 type
echo -en "\ec"
if [[ "$type" = "Y" || "$type" = "y" ]]; then
printc "Update System" ${YELLOW}
apt-get update > /dev/null 2>&1
apt-get upgrade -y > /dev/null 2>&1

 if [ $? -eq 0 ]; then
  echo -en "\ec"
  printc "Configuring MySQL" ${YELLOW}
  read -p "Enter MySQL Root Password:? " pass
  
  if [ -n "${pass}" ] && [[ ! "$pass" =~ ^[[:digit:]]+$ ]]; then
    echo -en "\ec"
    printc "Installing Nginx " ${YELLOW}
    sudo apt-get install nginx -y > /dev/null 2>&1
    systemctl start nginx > /dev/null 2>&1
    systemctl enable nginx > /dev/null 2>&1
	
    printc "Configure the Firewall Add the SSH and HTTP" ${YELLOW}
    sudo ufw allow ssh > /dev/null 2>&1
    sudo ufw allow http > /dev/null 2>&1
    sudo ufw enable -y > /dev/null 2>&1
	
    printc "Installing MySQL 5.7 " ${YELLOW}
    echo "mysql-server mysql-server/root_password password $pass" | debconf-set-selections
    echo "mysql-server mysql-server/root_password_again password $pass" | debconf-set-selections
    sudo apt-get install mysql-server mysql-client expect -y > /dev/null 2>&1
    expsql=$(expect -c '
    set timeout 10
    spawn mysql_secure_installation
    expect "Enter password for user root:"
    send "'$pass'\r"
    expect "Press y|Y for Yes, any other key for No:"
    send "y\r"
    expect "Please enter 0 = LOW, 1 = MEDIUM and 2 = STRONG:"
    send "2\r"
    expect "Change the password for root ? ((Press y|Y for Yes, any other key for No) :"
    send "n\r"
    expect "Remove anonymous users? (Press y|Y for Yes, any other key for No) :"
    send "y\r"
    expect "Disallow root login remotely? (Press y|Y for Yes, any other key for No) :"
    send "y\r"
    expect "Remove test database and access to it? (Press y|Y for Yes, any other key for No) :"
    send "y\r"
    expect "Reload privilege tables now? (Press y|Y for Yes, any other key for No) :"
    send "y\r"
    expect eof ')
    echo "$expsql" > /dev/null 2>&1
    systemctl start mysql > /dev/null 2>&1
    systemctl enable mysql > /dev/null 2>&1
    sudo apt-get -y purge expect > /dev/null 2>&1
	
    printc "Installing PHP7.2-FPM" ${YELLOW}
    sudo apt-get install php7.2 php7.2-fpm php7.2-cli php7.2-curl php7.2-mysql php7.2-curl php7.2-gd php7.2-mbstring php-pear -y > /dev/null 2>&1
    systemctl start php7.2-fpm > /dev/null 2>&1
    systemctl enable php7.2-fpm > /dev/null 2>&1
	
    printc "Install PhpMyAdmin" ${YELLOW}
    sudo apt-get install zip -y > /dev/null 2>&1
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
    sudo sed -i 's/keepalive_timeout 65;/keepalive_timeout 2;/' /etc/nginx/nginx.conf
    sudo sed -i 's/# server_tokens off;/server_tokens off;/' /etc/nginx/nginx.conf
    sudo sed -i 's/max_execution_time = 30/max_execution_time = 300/' /etc/php/7.2/fpm/php.ini
    sudo sed -i 's/upload_max_filesize = 2M/upload_max_filesize = 200M/' /etc/php/7.2/fpm/php.ini
    sudo sed -i 's/display_errors = Off/display_errors = On/' /etc/php/7.2/fpm/php.ini
    sudo sed -i 's/listen = /run/php/php7.2-fpm.sock/listen = 127.0.0.1:9000/' /etc/php/7.2/fpm/pool.d/www.conf
	
    printc "Restart Nginx - Mysql - Php  " ${YELLOW}
    systemctl reload php7.2-fpm > /dev/null 2>&1
    systemctl reload nginx > /dev/null 2>&1
    systemctl reload mysql > /dev/null 2>&1

    printc "Installation completed!" ${GREEN} 2
	
  else
  
    printc "Invalid password! Try again" ${RED}
	
  fi
  
 fi

else

 printc "Cancel updated!" ${RED}
	
fi
exit 0