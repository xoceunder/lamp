#!/usr/bin/env bash
# Instalador LAMP/LEMP para Ubuntu. Adaptado de lemp18.4.sh de XoceUnder.
set -Eeuo pipefail

# Muestra una etapa en el formato de recuadro del instalador original.
printc() {
    local message=$1 color=${2:-36}
    local start='' reset='' border
    local LC_ALL=C.UTF-8

    if [[ -t 1 && ${TERM:-dumb} != dumb && -z ${NO_COLOR:-} ]]; then
        printf -v start '\033[%sm' "$color"
        printf -v reset '\033[0m'
    fi

    printf -v border '%*s' "$(( ${#message} + 2 ))" ''
    border=${border// /─}
    printf '\n%s┌%s┐\n│ %s │\n└%s┘%s\n' "$start" "$border" "$message" "$border" "$reset"
}

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

case "${1:-}" in
    -h|--help)
        cat <<'HELP'
Uso: sudo bash lamp-ubuntu.sh [--apache|--nginx]
Sin opciones, el instalador pregunta qué servidor web instalar.
Ubuntu 18.04 o posterior con systemd y repositorios APT operativos.
Instala PHP, MariaDB y phpMyAdmin con los paquetes de APT.
Reutiliza MariaDB si ya está instalado. phpMyAdmin queda accesible localmente. Conserva las contraseñas y las reglas del firewall.
HELP
        exit 0
        ;;
    --apache) server=apache2 ;;
    --nginx) server=nginx ;;
    '') server= ;;
    *) die "Opción desconocida: $1. Consulta --help." ;;
esac
(( $# <= 1 )) || die 'Consulta --help para ver el uso.'

(( EUID == 0 )) || die 'Ejecuta el instalador con sudo.'
[[ -r /etc/os-release ]] || die 'No se pudo identificar el sistema operativo.'
unset ID VERSION_ID
# shellcheck source=/dev/null
. /etc/os-release
[[ ${ID:-} == ubuntu ]] || die 'Este instalador requiere Ubuntu.'
[[ ${VERSION_ID:-} =~ ^[0-9]+\.[0-9]+$ ]] || die 'No se pudo determinar la versión de Ubuntu.'
dpkg --compare-versions "$VERSION_ID" ge 18.04 || die 'Se requiere Ubuntu 18.04 o posterior.'
[[ -d /run/systemd/system ]] || die 'El sistema debe estar iniciado con systemd.'

if [[ -z $server ]]; then
    [[ -t 0 ]] || die 'En modo automático indica --apache o --nginx.'
    while true; do
        printc "Instalador web para Ubuntu $VERSION_ID"
        printf '%s\n' '1) Apache (LAMP)' '2) Nginx (LEMP)' '0) Cancelar'
        read -r -p 'Selecciona el servidor web [1/2/0]: ' choice || exit 1
        case "$choice" in
            1) server=apache2; break ;;
            2) server=nginx; break ;;
            0) exit 0 ;;
            *) printf '%s\n' 'Selecciona 1, 2 o 0.' ;;
        esac
    done
fi

trap 'printf "Instalación interrumpida en la línea %s (código %s).\n" "$LINENO" "$?" >&2' ERR
export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C

exec 9>/run/lock/lamp-ubuntu.lock
flock -n 9 || die 'Ya hay otra instancia del instalador ejecutándose.'

listeners=$(ss -H -ltnp 'sport = :80')
while IFS= read -r listener; do
    [[ -z $listener || $listener == *\"$server\"* ]] ||
        die "El puerto TCP 80 ya está ocupado por otro servicio: $listener"
done <<< "$listeners"

# Los metapaquetes seleccionan las extensiones de la versión de PHP de Ubuntu.
php_packages=(
    php-cli php-common
    php-mysql php-curl php-intl php-mbstring
    php-gd php-xml php-zip php-bcmath php-soap php-imagick
)
mariadb_existing=false
if systemctl cat mariadb.service >/dev/null 2>&1; then
    mariadb_existing=true
elif systemctl cat mysql.service >/dev/null 2>&1 || [[ -d /var/lib/mysql/mysql ]]; then
    die 'Se detectó MySQL o un directorio de datos sin servicio identificado. Se requiere una migración por separado.'
fi

web_preexistente=false
if systemctl cat "$server.service" >/dev/null 2>&1 || [[ -d /etc/$server/sites-enabled ]]; then
    web_preexistente=true
fi

nginx_default=/etc/nginx/sites-enabled/default
nginx_stock=/etc/nginx/sites-available/default
nginx_site=/etc/nginx/sites-available/lamp-ubuntu
nginx_enabled=/etc/nginx/sites-enabled/lamp-ubuntu

if [[ $server == apache2 ]]; then
    php_packages+=(libapache2-mod-php)
else
    php_packages+=(php-fpm)
    if [[ -e $nginx_default || -L $nginx_default ]]; then
        stock_checksum=$(dpkg-query -W -f='${Conffiles}' nginx-common 2>/dev/null |
            awk -v path="$nginx_stock" '$1 == path {print $2}' || true)
        [[ -L $nginx_default && $(readlink -f "$nginx_default") == "$nginx_stock" &&
            -n $stock_checksum ]] &&
            printf '%s  %s\n' "$stock_checksum" "$nginx_stock" | md5sum --check --status ||
            die "El sitio predeterminado de Nginx está personalizado. Revisa $nginx_default antes de continuar."
    fi
    if [[ -e $nginx_enabled || -L $nginx_enabled ]]; then
        [[ -L $nginx_enabled && $(readlink "$nginx_enabled") == "$nginx_site" ]] ||
            die "Ya existe otra configuración en $nginx_enabled."
    fi
    if [[ -e $nginx_site || -L $nginx_site ]]; then
        [[ -f $nginx_site && ! -L $nginx_site ]] &&
            read -r marker < "$nginx_site" && [[ $marker == '# Administrado por lamp-ubuntu.sh' ]] ||
            die "Ya existe otra configuración en $nginx_site."
    fi
fi

printc "Actualizando repositorios de Ubuntu $VERSION_ID" 33
apt-get -o APT::Update::Error-Mode=any update > /dev/null 2>&1
install_packages() {
    apt-get install -y --no-remove --no-install-recommends "$@" > /dev/null 2>&1
}

if $mariadb_existing; then
    printc "Reutilizando MariaDB instalado"
else
    printc "Instalando MariaDB" 33
    install_packages mariadb-server mariadb-client
fi
printc "Iniciando MariaDB" 33
systemctl enable --now mariadb.service > /dev/null 2>&1
systemctl is-active --quiet mariadb.service

printc "Instalando $server" 33
install_packages "$server"

printc "Instalando PHP y extensiones web" 33
install_packages "${php_packages[@]}"

printc "Instalando phpMyAdmin" 33
# La integración web se realiza más abajo. dbconfig-common es opcional
# para el acceso normal de phpMyAdmin a bases de datos existentes.
if ! dpkg-query -W -f='${Status}' phpmyadmin 2>/dev/null | grep -qx 'install ok installed'; then
    printf '%s\n' \
        'phpmyadmin phpmyadmin/reconfigure-webserver multiselect' \
        'phpmyadmin phpmyadmin/dbconfig-install boolean false' | debconf-set-selections > /dev/null 2>&1
fi
install_packages phpmyadmin curl
[[ -f /usr/share/phpmyadmin/index.php ]] || die 'El paquete phpMyAdmin no instaló index.php en la ruta esperada.'

check_phpmyadmin() {
    local reply status attempt curl_status=0
    local url=http://127.0.0.1/phpmyadmin/

    # La recarga puede terminar antes de que los nuevos workers atiendan HTTP.
    for attempt in 1 2 3 4 5; do
        curl_status=0
        reply=$(curl --noproxy '*' --silent --location --max-redirs 3 \
            --connect-timeout 2 --max-time 5 --write-out '\n%{http_code}' "$url") ||
            curl_status=$?
        status=${reply##*$'\n'}
        if (( curl_status == 0 )) && [[ $status == 200 && $reply == *pma_username* ]]; then
            return 0
        fi
        if (( attempt < 5 )); then
            sleep 1
        fi
    done

    if (( curl_status != 0 )); then
        die "phpMyAdmin no respondió en $url (curl $curl_status, HTTP ${status:-000})."
    fi
    if [[ $status == 200 ]]; then
        die "phpMyAdmin respondió HTTP 200 en $url, pero no mostró el formulario de acceso."
    fi
    die "phpMyAdmin respondió HTTP $status en $url. Revisa los registros de $server y PHP."
}

start_php_fpm() {
    local dependencies php_version fpm_service
    # Leer el paquete del que depende el metapaquete instalado, incluso si
    # php en la terminal apunta a otra versión.
    dependencies=$(dpkg-query -W -f='${Depends}' php-fpm)
    [[ $dependencies =~ (^|[[:space:],])php([0-9]+\.[0-9]+)-fpm($|[[:space:],]) ]] ||
        die 'No se pudo determinar el servicio PHP-FPM a partir de php-fpm.'
    php_version=${BASH_REMATCH[2]}
    fpm_service="php$php_version-fpm.service"
    fpm_socket="/run/php/php$php_version-fpm.sock"
    printc "Iniciando PHP $php_version FPM" 33
    systemctl enable --now "$fpm_service" > /dev/null 2>&1
    systemctl is-active --quiet "$fpm_service"
    [[ -S $fpm_socket ]] || die "PHP-FPM no creó el socket esperado en $fpm_socket."
}

configure_nginx() (
    backup=$(mktemp -d /etc/nginx/.lamp-ubuntu.XXXXXXXX)
    default_target=
    had_enabled=false
    if [[ -L $nginx_default ]]; then
        default_target=$(readlink "$nginx_default")
    fi
    if [[ -L $nginx_enabled ]]; then
        had_enabled=true
    fi
    if [[ -f $nginx_site ]]; then
        cp -p -- "$nginx_site" "$backup/site"
    fi

    rollback_nginx() {
        if [[ -f $backup/site ]]; then
            mv -f -- "$backup/site" "$nginx_site"
        else
            rm -f -- "$nginx_site"
        fi
        if ! $had_enabled; then
            rm -f -- "$nginx_enabled"
        fi
        if [[ -n $default_target && ! -L $nginx_default ]]; then
            ln -s -- "$default_target" "$nginx_default"
        fi
        rm -rf -- "$backup"
        if $reload_attempted; then
            systemctl reload nginx.service > /dev/null 2>&1 || true
        fi
    }
    reload_attempted=false
    trap rollback_nginx EXIT

    cat > "$backup/new-site" <<NGINX
# Administrado por lamp-ubuntu.sh
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    root /var/www/html;
    index index.php index.html index.nginx-debian.html;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location = /phpmyadmin {
        return 301 /phpmyadmin/;
    }

    location ^~ /phpmyadmin/ {
        root /usr/share;
        index index.php;
        allow 127.0.0.1;
        allow ::1;
        deny all;

        location ~ ^/phpmyadmin/(?:setup|libraries|templates|vendor)(?:/|\$) {
            deny all;
        }

        location ~ /\\. {
            deny all;
        }

        location ~ \\.php\$ {
            include snippets/fastcgi-php.conf;
            fastcgi_pass unix:$fpm_socket;
        }
    }

    location ~ /\\. {
        deny all;
    }

    location ~ \\.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$fpm_socket;
    }
}
NGINX
    chmod 0644 "$backup/new-site"
    mv -f -- "$backup/new-site" "$nginx_site"
    if ! $had_enabled; then
        ln -s -- "$nginx_site" "$nginx_enabled"
    fi
    if [[ -n $default_target ]]; then
        rm -- "$nginx_default"
    fi

    nginx -t > /dev/null 2>&1
    printc "Iniciando Nginx" 33
    systemctl enable --now nginx.service > /dev/null 2>&1
    reload_attempted=true
    systemctl reload nginx.service > /dev/null 2>&1
    printc "Verificando phpMyAdmin" 33
    check_phpmyadmin
    trap - EXIT
    rm -rf -- "$backup"
)

if [[ $server == apache2 ]]; then
    printc "Configurando Apache y el módulo de PHP" 33
    [[ -f /etc/phpmyadmin/apache.conf ]] || die 'Falta la configuración de Apache del paquete phpMyAdmin.'
    apache_pma=/etc/apache2/conf-available/lamp-ubuntu-phpmyadmin.conf
    if [[ ! -e $apache_pma && ! -L $apache_pma ]]; then
        cat > "$apache_pma" <<'APACHE'
# Administrado por lamp-ubuntu.sh
<LocationMatch "(?i)^/phpmyadmin(?:/|$)">
    Require local
</LocationMatch>
APACHE
    fi
    # Algunos servidores ya tienen habilitado el archivo del paquete.
    if [[ ! -e /etc/apache2/conf-enabled/phpmyadmin.conf &&
          ! -e /etc/apache2/conf-enabled/lamp-ubuntu-phpmyadmin-alias.conf ]]; then
        ln -s /etc/phpmyadmin/apache.conf /etc/apache2/conf-enabled/lamp-ubuntu-phpmyadmin-alias.conf
    fi
    a2enconf lamp-ubuntu-phpmyadmin > /dev/null 2>&1
    apache2ctl configtest > /dev/null 2>&1
    apache_modules=$(apache2ctl -M 2>/dev/null)
    [[ $apache_modules =~ [[:space:]]php[0-9_]*_module[[:space:]] ]] ||
        die 'Apache no tiene el módulo de PHP activo. Revisa la configuración de PHP y del MPM.'
    printc "Iniciando Apache con PHP" 33
    systemctl enable --now apache2.service > /dev/null 2>&1
    systemctl reload apache2.service > /dev/null 2>&1
    printc "Verificando phpMyAdmin" 33
    check_phpmyadmin
else
    start_php_fpm
    printc "Configurando Nginx" 33
    configure_nginx
fi
systemctl is-active --quiet "$server.service"

if [[ $server == nginx ]] || ! $web_preexistente; then
    # Comprobar las extensiones en el PHP web, que puede diferir del CLI.
    probe=$(mktemp /var/www/html/lamp-check-XXXXXXXX.php)
    trap 'rm -f -- "$probe"' EXIT
    cat > "$probe" <<'PHP'
<?php
$required = array(
    'mysqli', 'pdo_mysql', 'curl', 'intl', 'mbstring', 'gd', 'dom',
    'SimpleXML', 'xmlreader', 'xmlwriter', 'zip', 'bcmath', 'soap',
    'imagick', 'json', 'fileinfo', 'openssl', 'session'
);
$missing = array_filter($required, function ($extension) {
    return !extension_loaded($extension);
});
echo $missing ? 'MISSING:' . implode(', ', $missing) : PHP_VERSION;
PHP
    chmod 0644 "$probe"
    php_web_version=$(curl --noproxy '*' -fsS --max-time 10 "http://127.0.0.1/${probe##*/}" 2>/dev/null) || die 'Falló la prueba HTTP local de PHP.'
    if [[ $php_web_version == MISSING:* ]]; then
        die "Faltan extensiones en PHP web: ${php_web_version#MISSING:}"
    fi
    [[ $php_web_version =~ ^[0-9]+\.[0-9]+\.[0-9]+[-+~.a-zA-Z0-9]*$ ]] ||
        die 'El servidor web no devolvió una versión válida de PHP.'
    rm -f -- "$probe"
    trap - EXIT
    printf 'PHP web %s\n' "$php_web_version"
fi

printc "Instalación completada" 32
printf '%s y MariaDB están activos.\n' "$server"
php -v
if command -v mariadbd >/dev/null; then
    mariadbd --version
else
    mysqld --version
fi
printf '%s\n' \
    'Sitio predeterminado: /var/www/html' \
    'phpMyAdmin: http://127.0.0.1/phpmyadmin/' \
    'Desde otro equipo: ssh -L 8080:127.0.0.1:80 usuario@servidor' \
    'Después abre http://127.0.0.1:8080/phpmyadmin/ e inicia sesión con un usuario de MariaDB con contraseña.'
