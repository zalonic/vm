#!/bin/bash
true
SCRIPT_NAME="Redis Server Ubuntu"
# shellcheck source=lib.sh
source /var/scripts/fetch_lib.sh

# T&M Hansson IT AB © - 2023, https://www.hanssonit.se/

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode

# Must be root
root_check

# Check Ubuntu version
if ! version 18.04 "$DISTRO" 22.04.10
then
    msg_box "Your current Ubuntu version is $DISTRO but must be between 18.04 - 22.04.10 to run this script."
    msg_box "Please contact us to get support for upgrading your server:
https://www.hanssonit.se/#contact
https://shop.hanssonit.se/"
    exit 1
fi

# Check if dir exists
if [ ! -d $SCRIPTS ]
then
    mkdir -p $SCRIPTS
fi

# Check the current PHPVER
check_php

# Install Redis
install_if_not php"$PHPVER"-dev
pecl channel-update pecl.php.net
if ! yes no | pecl install -Z redis
then
    msg_box "PHP module installation failed"
exit 1
else
    printf "${IGreen}\nPHP module installation OK!${Color_Off}\n"
fi
if [ ! -f $PHP_MODS_DIR/redis.ini ]
then
    touch $PHP_MODS_DIR/redis.ini
fi
if ! grep -qFx extension=redis.so $PHP_MODS_DIR/redis.ini
then
    echo "# PECL redis" > $PHP_MODS_DIR/redis.ini
    echo "extension=redis.so" >> $PHP_MODS_DIR/redis.ini
    check_command phpenmod -v ALL redis
fi
install_if_not redis-server

## Redis performance tweaks ##
if ! grep -Fxq "vm.overcommit_memory = 1" /etc/sysctl.conf
then
    echo 'vm.overcommit_memory = 1' >> /etc/sysctl.conf
fi

# Disable THP
if ! grep -Fxq "never" /sys/kernel/mm/transparent_hugepage/enabled
then
    echo "never" > /sys/kernel/mm/transparent_hugepage/enabled
fi

# Raise TCP backlog
#if ! grep -Fxq "net.core.somaxconn" /proc/sys/net/core/somaxconn
#then
#    sed -i "s|net.core.somaxconn.*||g" /etc/sysctl.conf
#    sysctl -w net.core.somaxconn=512
#    echo "net.core.somaxconn = 512" >> /etc/sysctl.conf
#fi

# Set redis options
sed -i "s|# unixsocket .*|unixsocket $REDIS_SOCK|g" $REDIS_CONF
sed -i "s|# unixsocketperm .*|unixsocketperm 777|g" $REDIS_CONF
sed -i "s|^port.*|port 0|" $REDIS_CONF
sed -i 's|# rename-command CONFIG ""|rename-command CONFIG ""|' $REDIS_CONF
systemctl restart redis

# Secure Redis
chown redis:root /etc/redis/redis.conf
chmod 600 /etc/redis/redis.conf

apt-get update -q4 & spinner_loading
apt-get autoremove -y
apt-get autoclean

# Add the needed config to Nextclouds config.php
nextcloud_occ config:system:set memcache.local --value='\OC\Memcache\Redis'
nextcloud_occ config:system:set filelocking.enabled --value='true'
nextcloud_occ config:system:set memcache.distributed --value='\OC\Memcache\Redis'
nextcloud_occ config:system:set memcache.locking --value='\OC\Memcache\Redis'

nextcloud_occ config:system:set redis host --value="$REDIS_SOCK"
nextcloud_occ config:system:set redis port --value=0
nextcloud_occ config:system:set redis dbindex --value=0
nextcloud_occ config:system:set redis timeout --value=0.5

# Set password
sed -i "s|# requirepass .*|requirepass $REDIS_PASS|g" $REDIS_CONF
nextcloud_occ config:system:set redis timeout --value="$REDIS_PASS"
systemctl restart redis
