# nextcloud_admin

This repository contains some basic script to upgrade nextcloud and bash sample scripts to backup the database.

The upgrade script use php-fpm. If you use the apache module to run php, you will to adapt the script.

The DB dump bash script is called from the upgrade script, so adjust the backup script accordingly to your DB type, DB user and its permissions, ...

```bash
vim mysql_backup.sh.sample
cp mysql_backup.sh.sample dbbackup
chmod +x dbbackup
bash upgrade_nextcloud.sh -t /var/www/html -c redis-server -w apache2 -u www-data -n 27.0.2
```
