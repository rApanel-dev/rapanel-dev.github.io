#!/bin/bash

# =========================================================================
# rApanel — Script de Actualización
#
# Uso:
#   sudo bash /var/www/rapanel/update.sh
# =========================================================================

# Colores
Red='\033[0;31m'
Green='\033[0;32m'
Yellow='\033[0;33m'
Cyan='\033[0;36m'
White='\033[0m'

php_version="php8.4"
# El script vive dentro de su propia instalación: deriva la ruta y el slug automáticamente,
# así funciona sin importar el nombre del directorio elegido al instalar.
install_dir="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
app_slug="$(basename "$install_dir")"

# 1. Validar usuario root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${Red}ERROR: Ejecuta este script como root (sudo -s o sudo ./update.sh)${White}"
    exit 1
fi

# 2. Directorio de trabajo
cd "$install_dir" || { echo -e "${Red}ERROR: No se encontró $install_dir${White}"; exit 1; }

echo -e "${Cyan}Iniciando actualización de rApanel...${White}"

# 3. Solucionar advertencia de seguridad de git
git config --global --add safe.directory "$install_dir"

# 4. Modo mantenimiento y limpiar cachés
$php_version artisan down || true
$php_version artisan route:clear
$php_version artisan cache:clear
$php_version artisan config:clear
$php_version artisan view:clear
$php_version artisan optimize:clear

# 5. Git pull
if git pull; then
    echo -e "${Green}¡Git pull exitoso!${White}"
else
    echo -e "${Yellow}Advertencia: tienes cambios locales que se perderán.${White}"
    read -rp "¿Deseas descartarlos y continuar? (s/n): " continueUpdate
    if [[ "$continueUpdate" != 's' && "$continueUpdate" != 'S' ]]; then
        $php_version artisan up
        echo -e "${Red}Actualización cancelada.${White}"
        exit 1
    fi
    git stash
    git pull
fi

# 6. Dependencias PHP
export COMPOSER_ALLOW_SUPERUSER=1
$php_version /usr/local/bin/composer install --no-interaction --no-dev --optimize-autoloader

# 7. Migraciones
$php_version artisan migrate --force

# 8. Frontend
echo -e "${Cyan}Compilando assets del frontend...${White}"
npm ci --silent
npm run build

# 9. Permisos
chown -R www-data:www-data "$install_dir"/
chmod -R 775 storage bootstrap/cache/

# 10. Reiniciar workers y PHP-FPM para cargar el nuevo código
supervisorctl restart ${app_slug}-worker:* || true
systemctl reload "$php_version-fpm" || true

# 11. Optimizar y salir del modo mantenimiento
$php_version artisan optimize
$php_version artisan up

echo -e "${Green}¡rApanel actualizado correctamente!${White}"
