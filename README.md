# rapanel-dev.github.io

GitHub Pages site for the [rApanel](https://github.com/rapanel-dev/rapanel) project.

Hosts the auto-installer and update scripts for rApanel — a web control panel for **rAthena** Ragnarok Online emulator servers.

## Install

One command installs PHP 8.4, Nginx, Node.js, Redis, Supervisor, Composer and rApanel on Ubuntu 24.04 LTS:

```bash
curl -o ~/install.sh https://rapanel-dev.github.io/install.sh && chmod +x ~/install.sh && sudo ~/install.sh
```

## Update

```bash
sudo bash /var/www/rapanel/update.sh
```

## Timezone note

`APP_TIMEZONE` in `.env` must match the OS timezone and MariaDB/MySQL timezone. If you change it, also run:

```bash
sudo timedatectl set-timezone America/Santiago   # example — use your own timezone
```

Otherwise timestamps will be stored in the wrong timezone.

## Links

- [rApanel repository](https://github.com/rapanel-dev/rapanel)
- [rapanel-dev organization](https://github.com/rapanel-dev)
