# Ubuntu LAMP / LEMP Auto Installer

Install Apache (LAMP) or Nginx (LEMP) with PHP, MariaDB, and phpMyAdmin on Ubuntu 18.04 or later. The installer uses the package versions available through your Ubuntu APT repositories.

## Requirements

- Ubuntu 18.04 or later running systemd.
- Root access through `sudo` or a root shell.
- Internet access and working APT repositories, including Ubuntu Universe.
- TCP port 80 available or already in use by the selected web server.

## Quick setup

Download or copy `lamp-ubuntu.sh` to your Ubuntu machine. From the directory containing the script, run:

```bash
wget -O install.sh "https://raw.githubusercontent.com/xoceunder/lamp/master/lamp-ubuntu.sh" && chmod +x install.sh && ./install.sh
```

Select **1** for Apache or **2** for Nginx. Select **0** to cancel. To skip the menu, run either command:

```bash
sudo bash install.sh --apache
sudo bash install.sh --nginx
```

## What the installer does

- Installs the web server, PHP, MariaDB, and phpMyAdmin in separate steps. APT and service commands run quietly while the installer displays progress and errors.
- Configures PHP-FPM for Nginx or the PHP module for Apache.
- Installs PHP extensions including MySQLi, PDO MySQL, cURL, Intl, Mbstring, GD, XML, ZIP, BCMath, SOAP, and Imagick.
- Reuses an existing MariaDB service and preserves its passwords and databases. If the installer detects MySQL, it stops so the database can be migrated separately.
- Starts the selected services and checks that phpMyAdmin responds locally.

## Access your installation

The default document root is `/var/www/html`.

Open [phpMyAdmin](http://127.0.0.1/phpmyadmin/) in a browser on the Ubuntu machine. To connect from another computer, run the following command on that computer:

```bash
ssh -L 8080:127.0.0.1:80 user@server
```

Keep the SSH session open and visit [phpMyAdmin through the tunnel](http://127.0.0.1:8080/phpmyadmin/). Sign in with a MariaDB account that has a password.

## Support

For an installation problem or feature request, open an issue with the Ubuntu version, the selected web server, and the error message.
