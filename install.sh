#!/bin/bash

# =========================================================================
# rApanel Auto-Installer
# Optimizado para Ubuntu 24.04 LTS
#
# Uso:
#   curl -fsSL https://rapanel-dev.github.io/install.sh | sudo bash
# =========================================================================

# Colores
Red='\033[0;31m'
Green='\033[0;32m'
Yellow='\033[0;33m'
Cyan='\033[0;36m'
White='\033[0m'

nodejs_version=22
php_version=php8.4
install_dir="/var/www/rapanel"

clear

echo "=========================================="
echo "   rApanel — Instalador Automático"
echo "   Diseñado para Ubuntu 24.04 LTS"
echo "   Requiere acceso root (sudo -s)"
echo "=========================================="
echo ""

# =========================================================================
# FUNCIONES COMPARTIDAS
# =========================================================================

update_system() {
    echo -e "${Cyan}Actualizando lista de paquetes...${White}"
    apt update -y
}

install_php() {
    if ! dpkg -l | grep -q "$php_version"; then
        echo -e "${Cyan}Instalando PHP 8.4 y extensiones...${White}"
        apt install software-properties-common -y

        max_retries=3
        retry_count=0
        success=false
        while [ $retry_count -lt $max_retries ]; do
            echo "Añadiendo repositorio PHP (intento $((retry_count+1))/$max_retries)..."
            if add-apt-repository ppa:ondrej/php -y; then
                success=true
                break
            else
                echo "Fallo de conexión. Reintentando en 10 segundos..."
                sleep 10
                retry_count=$((retry_count+1))
            fi
        done

        if [ "$success" = false ]; then
            echo -e "${Red}ERROR: No se pudo añadir el repositorio PHP. Intenta más tarde.${White}"
            exit 1
        fi

        apt update -y
        apt install -y curl "$php_version" "$php_version-cli" "$php_version-gd" \
            "$php_version-mysql" "$php_version-common" "$php_version-mbstring" \
            "$php_version-bcmath" "$php_version-xml" "$php_version-fpm" \
            "$php_version-curl" "$php_version-zip" "$php_version-intl" \
            "$php_version-redis"
    else
        echo -e "${Green}PHP ya está instalado. Continuando...${White}"
    fi

    if ! command -v php > /dev/null 2>&1; then
        echo -e "${Red}ERROR: PHP no se instaló correctamente.${White}"
        exit 1
    fi
}

install_nodejs() {
    echo -e "${Cyan}Instalando Node.js $nodejs_version...${White}"
    curl -sL https://deb.nodesource.com/setup_$nodejs_version.x -o /tmp/nodesource_setup.sh
    bash /tmp/nodesource_setup.sh
    apt install nodejs -y
}

install_extras() {
    echo -e "${Cyan}Instalando herramientas adicionales (Redis, Git, Supervisor, Sendmail, Unzip)...${White}"
    apt install -y redis-server git supervisor sendmail unzip cron nano
    systemctl enable --now redis-server
}

install_composer() {
    echo -e "${Cyan}Instalando Composer...${White}"
    curl -sS https://getcomposer.org/installer | \
        $php_version -- --install-dir=/usr/local/bin --filename=composer
}

clone_and_setup() {
    mkdir -p "$install_dir"
    cd "$install_dir"

    echo -e "${Cyan}Clonando rApanel desde GitHub...${White}"
    git clone https://github.com/rapanel-dev/rapanel.git .
    git config --global --add safe.directory "$install_dir"
    git config core.fileMode false

    echo -e "${Cyan}Configurando archivo .env...${White}"
    cp .env.example .env

    # Aplicación
    sed -i "s#APP_URL=.*#APP_URL=http://$domain_name#" .env
    sed -i "s#RA_SERVER_NAME=.*#RA_SERVER_NAME=\"$server_name\"#" .env
    sed -i "s#APP_LOCALE=.*#APP_LOCALE=$app_locale#" .env
    sed -i "s#RA_GAME_MODE=.*#RA_GAME_MODE=$game_mode#" .env

    # Base de datos principal (rAthena + panel ra_*)
    sed -i "s#DB_HOST=.*#DB_HOST=$db_host#" .env
    sed -i "s#DB_PORT=.*#DB_PORT=$db_port#" .env
    sed -i "s#DB_DATABASE=.*#DB_DATABASE=$db_database#" .env
    sed -i "s#DB_USERNAME=.*#DB_USERNAME=$db_username#" .env
    sed -i "s#DB_PASSWORD=.*#DB_PASSWORD=$db_password#" .env

    # Base de datos de logs
    sed -i "s#DB_LOG_HOST=.*#DB_LOG_HOST=$log_db_host#" .env
    sed -i "s#DB_LOG_PORT=.*#DB_LOG_PORT=$log_db_port#" .env
    sed -i "s#DB_LOG_DATABASE=.*#DB_LOG_DATABASE=$log_db_database#" .env
    sed -i "s#DB_LOG_USERNAME=.*#DB_LOG_USERNAME=$log_db_username#" .env
    sed -i "s#DB_LOG_PASSWORD=.*#DB_LOG_PASSWORD=$log_db_password#" .env

    # Base de datos web
    sed -i "s#DB_WEB_HOST=.*#DB_WEB_HOST=$web_db_host#" .env
    sed -i "s#DB_WEB_PORT=.*#DB_WEB_PORT=$web_db_port#" .env
    sed -i "s#DB_WEB_DATABASE=.*#DB_WEB_DATABASE=$web_db_database#" .env
    sed -i "s#DB_WEB_USERNAME=.*#DB_WEB_USERNAME=$web_db_username#" .env
    sed -i "s#DB_WEB_PASSWORD=.*#DB_WEB_PASSWORD=$web_db_password#" .env

    # IPs del servidor rAthena
    sed -i "s#RA_LOGIN_IP=.*#RA_LOGIN_IP=$ra_server_ip#" .env
    sed -i "s#RA_CHAR_IP=.*#RA_CHAR_IP=$ra_server_ip#" .env
    sed -i "s#RA_MAP_IP=.*#RA_MAP_IP=$ra_server_ip#" .env
    sed -i "s#RA_WEB_IP=.*#RA_WEB_IP=$ra_server_ip#" .env

    # Instalar dependencias PHP
    echo -e "${Cyan}Instalando dependencias PHP...${White}"
    export COMPOSER_ALLOW_SUPERUSER=1
    $php_version /usr/local/bin/composer install --no-interaction --no-dev --optimize-autoloader

    # Generar clave de aplicación y migrar
    $php_version artisan key:generate --force
    $php_version artisan migrate --force
    $php_version artisan storage:link

    # Compilar frontend
    echo -e "${Cyan}Compilando assets del frontend (Vite)...${White}"
    npm install --silent
    npm run build

    # Permisos
    chown -R www-data:www-data "$install_dir"/
    chmod -R 775 storage bootstrap/cache/
}

configure_supervisor() {
    echo -e "${Cyan}Configurando Supervisor para colas...${White}"
    cat > /etc/supervisor/conf.d/rapanel-worker.conf << EOF
[program:rapanel-worker]
process_name=%(program_name)s_%(process_num)02d
command=$php_version $install_dir/artisan queue:work --sleep=3 --tries=3 --max-time=3600
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
user=www-data
numprocs=2
redirect_stderr=true
stopwaitsecs=3660
EOF
    supervisorctl reread
    supervisorctl update
    supervisorctl start rapanel-worker:* || true
}

add_cron_job() {
    (crontab -l 2>/dev/null; echo "* * * * * $php_version $install_dir/artisan schedule:run >> /dev/null 2>&1") | crontab -
}

# =========================================================================
# PROMPTS DE CONFIGURACIÓN
# =========================================================================

collect_config() {
    echo ""
    echo "=========================================="
    echo " CONFIGURACIÓN DE RAPANEL"
    echo "=========================================="

    # Dominio
    read -rp "[1/7] Dominio (sin http:// ni www, ej: mi-server.com): " domain_name

    # Nombre del servidor
    read -rp "[2/7] Nombre del servidor RO (ej: Mi Servidor RO): " server_name
    server_name="${server_name:-Mi Servidor RO}"

    # Modo de juego
    echo "[3/7] Modo de juego:"
    echo "      1. renewal (por defecto)"
    echo "      2. pre-renewal"
    read -rp "      Selecciona [1-2]: " game_mode_sel
    if [ "$game_mode_sel" = "2" ]; then
        game_mode="pre-renewal"
    else
        game_mode="renewal"
    fi

    # Idioma
    echo "[4/7] Idioma por defecto:"
    echo "      1. es — Español (por defecto)"
    echo "      2. en — English"
    echo "      3. pt — Português"
    echo "      4. fr — Français"
    read -rp "      Selecciona [1-4]: " locale_sel
    case "$locale_sel" in
        2) app_locale="en" ;;
        3) app_locale="pt" ;;
        4) app_locale="fr" ;;
        *) app_locale="es" ;;
    esac

    # Base de datos rAthena
    echo ""
    echo "--- BASE DE DATOS rAthena (main) ---"
    read -rp "[5/7] Host BD (default: 127.0.0.1): " db_host
    db_host="${db_host:-127.0.0.1}"
    read -rp "      Puerto BD (default: 3306): " db_port
    db_port="${db_port:-3306}"
    read -rp "      Nombre de la BD: " db_database
    read -rp "      Usuario BD: " db_username
    read -srp "      Contraseña BD: " db_password
    echo ""

    # Base de datos de logs
    echo ""
    echo "--- BASE DE DATOS rAthena (logs) ---"
    read -rp "[6/8] ¿Usar la misma BD para logs? (s/n, default: s): " same_logs
    if [[ "$same_logs" == "n" || "$same_logs" == "N" ]]; then
        read -rp "      Host logs (default: $db_host): " log_db_host
        log_db_host="${log_db_host:-$db_host}"
        read -rp "      Puerto logs (default: $db_port): " log_db_port
        log_db_port="${log_db_port:-$db_port}"
        read -rp "      Nombre BD logs: " log_db_database
        read -rp "      Usuario logs: " log_db_username
        read -srp "      Contraseña logs: " log_db_password
        echo ""
    else
        log_db_host="$db_host"
        log_db_port="$db_port"
        log_db_database="$db_database"
        log_db_username="$db_username"
        log_db_password="$db_password"
    fi

    # Base de datos web
    echo ""
    echo "--- BASE DE DATOS rAthena (web) ---"
    read -rp "[7/8] ¿Usar la misma BD para web? (s/n, default: s): " same_web
    if [[ "$same_web" == "n" || "$same_web" == "N" ]]; then
        read -rp "      Host web (default: $db_host): " web_db_host
        web_db_host="${web_db_host:-$db_host}"
        read -rp "      Puerto web (default: $db_port): " web_db_port
        web_db_port="${web_db_port:-$db_port}"
        read -rp "      Nombre BD web: " web_db_database
        read -rp "      Usuario web: " web_db_username
        read -srp "      Contraseña web: " web_db_password
        echo ""
    else
        web_db_host="$db_host"
        web_db_port="$db_port"
        web_db_database="$db_database"
        web_db_username="$db_username"
        web_db_password="$db_password"
    fi

    # IP del servidor rAthena (para estado online)
    echo ""
    read -rp "[8/8] IP del servidor rAthena para estado online (default: 127.0.0.1): " ra_server_ip
    ra_server_ip="${ra_server_ip:-127.0.0.1}"
}

show_success() {
    echo ""
    echo -e "${Green}=========================================================${White}"
    echo -e "${Green} ¡rApanel instalado correctamente!${White}"
    echo -e "${Green}=========================================================${White}"
    echo ""
    echo " URL del panel:  http://$domain_name"
    echo " Servidor:       $server_name"
    echo " Modo de juego:  $game_mode"
    echo " Idioma:         $app_locale"
    echo ""
    echo -e "${Yellow} PASO 1 — Crear el primer administrador:${White}"
    echo "   1. Regístrate en: http://$domain_name/register"
    echo "   2. Ejecuta en MySQL:"
    echo ""
    echo "      UPDATE ra_users SET role = 'admin' WHERE email = 'tu@email.com';"
    echo ""
    echo -e "${Yellow} PASO 2 — Completar configuración en .env:${White}"
    echo "   Edita: $install_dir/.env"
    echo ""
    echo "   • RA_LOGIN_PORT (def: 6900) / RA_CHAR_PORT (def: 6121)"
    echo "     RA_MAP_PORT (def: 5121) / RA_WEB_PORT (def: 8080)"
    echo "     → Puertos de los servidores rAthena para el estado online"
    echo ""
    echo "   • DISCORD_SERVER_ID / DISCORD_BOT_TOKEN / DISCORD_INVITE_URL"
    echo "     → Widget de Discord en la página de inicio"
    echo ""
    echo "   • MAIL_MAILER / MAIL_HOST / MAIL_PORT / MAIL_USERNAME / MAIL_PASSWORD"
    echo "     → Correo para verificación de cuenta y recuperación de contraseña"
    echo ""
    echo "   • RA_2FA_ENABLED / RA_2FA_FORCE_ADMINS"
    echo "     → Autenticación de dos factores"
    echo ""
    echo "   • RA_VIP_ENABLED / RA_BANK_ENABLED / RA_CASHPOINTS_ENABLED"
    echo "     → Funcionalidades opcionales del panel"
    echo ""
    echo "   Tras editar .env ejecuta:"
    echo "   php artisan config:clear && php artisan cache:clear"
    echo ""
    echo -e "${Green}=========================================================${White}"
}

# =========================================================================
# INSTALACIÓN CON NGINX
# =========================================================================

nginx_install() {

    install_nginx_extras() {
        echo -e "${Cyan}Instalando Nginx, Node.js, Redis, Git, Supervisor y Composer...${White}"
        apt install -y nginx
        systemctl restart nginx
        install_nodejs
        install_extras
        install_composer
    }

    setup_nginx_config() {
        echo -e "${Cyan}Configurando Nginx para rApanel...${White}"
        cat > /etc/nginx/sites-available/rapanel.conf << EOF
server {
    listen 80;
    listen [::]:80;
    server_name $domain_name www.$domain_name;
    root $install_dir/public;

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";

    index index.php;
    charset utf-8;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ^~ /data/ {
        try_files \$uri =404;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    error_page 404 /index.php;

    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php/${php_version}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOF
        ln -sf /etc/nginx/sites-available/rapanel.conf /etc/nginx/sites-enabled/
        rm -f /etc/nginx/sites-enabled/default
        systemctl reload nginx
    }

    collect_config
    update_system
    install_php
    install_nginx_extras

    if [ ! -d "$install_dir" ] || [ -z "$(ls -A "$install_dir" 2>/dev/null)" ]; then
        clone_and_setup
        add_cron_job
        configure_supervisor
        setup_nginx_config
        show_success
    else
        echo -e "${Red}ERROR: $install_dir ya existe y no está vacío.${White}"
        echo "Para actualizar usa: sudo bash $install_dir/update.sh"
        exit 1
    fi
}

# =========================================================================
# INSTALACIÓN CON APACHE2
# =========================================================================

apache2_install() {

    install_apache_extras() {
        echo -e "${Cyan}Instalando Apache2, Node.js, Redis, Git, Supervisor y Composer...${White}"
        apt install -y apache2 "libapache2-mod-${php_version}"
        systemctl restart apache2
        install_nodejs
        install_extras
        install_composer
    }

    setup_apache_config() {
        echo -e "${Cyan}Configurando Apache2 para rApanel...${White}"
        cat > /etc/apache2/sites-available/rapanel.conf << EOF
<VirtualHost *:80>
    ServerName $domain_name
    ServerAlias www.$domain_name
    DocumentRoot "$install_dir/public"

    AllowEncodedSlashes On

    <Directory "$install_dir/public">
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF
        a2enmod rewrite
        a2ensite rapanel.conf
        a2dissite 000-default.conf 2>/dev/null || true
        systemctl restart apache2
    }

    collect_config
    update_system
    install_php
    install_apache_extras

    if [ ! -d "$install_dir" ] || [ -z "$(ls -A "$install_dir" 2>/dev/null)" ]; then
        clone_and_setup
        add_cron_job
        configure_supervisor
        setup_apache_config
        show_success
    else
        echo -e "${Red}ERROR: $install_dir ya existe y no está vacío.${White}"
        echo "Para actualizar usa: sudo bash $install_dir/update.sh"
        exit 1
    fi
}

# =========================================================================
# VALIDAR ROOT Y MENÚ PRINCIPAL
# =========================================================================

if [ "$(id -u)" -ne 0 ]; then
    echo -e "${Red}ERROR: Ejecuta este script como root (sudo -s o sudo ./install.sh)${White}"
    exit 1
fi

echo ""
echo "Selecciona el servidor web para rApanel:"
echo "  1. Nginx  (recomendado)"
echo "  2. Apache2"
echo ""
read -rp "Selecciona una opción [1-2]: " selection

case "$selection" in
    2) apache2_install ;;
    *) nginx_install ;;
esac
