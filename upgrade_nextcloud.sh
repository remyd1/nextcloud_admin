#!/usr/bin/env bash


usage() { echo -e "\n\nusage:
$0 -t NEXTCLOUD_TOPDIR -s NEXTCLOUD_SUBDIR -c CACHE_SERVICE_SYSTEMDUNIT -w WEB_SERVICE_SYSTEMDUNIT -u WEB_USER -n NEW_VERSION

  \=> NEXTCLOUD_TOPDIR: The Nextcloud parent directory (eg: /var/www for nextcloud installed at /var/www/nextcloud) (default: '/var/www/html'),
  \=> NEXTCLOUD_SUBDIR: The subdirectory where nextcloud is installed (default: 'nextcloud'),
  \=> CACHE_SERVICE_SYSTEMDUNIT: The systemd service name of your cache server (redis-server, memcached, ...) (default 'redis-server'),
  \=> WEB_SERVICE_SYSTEMDUNIT: The systemd service name of your Web server (nginx, apache2, ...) (default 'apache2'),
  \=> WEB_USER: generally www-data (default 'www-data'),
  \=> NEW_VERSION: New nexctloud version, for upgrade. [required]\n
  examples:
  
  $0 -t /var/www/html -c redis-server -w apache2 -u www-data -n 27.0.2

  $0 -t /var/www -s nextcloud -c memcached -w nginx -u www-data -n 27.0.2

  \n
  $0 -h
    \=> Print this help and exit.
  \n"
  }

NEXTCLOUD_DOWNLOAD_URL="https://download.nextcloud.com/server/releases/"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DBBACKUPCMD="${SCRIPT_DIR}/dbbackup"
_SUDO=$(command -v sudo)
_WGET=$(command -v wget)
_SHA256SUM=$(command -v sha256sum)

if [[ -z "${_WGET}" ]]; then
    echo "wget is needed to use this script"
fi
if [[ -z "${_SUDO}" ]]; then
    echo "sudo is needed to use this script"
fi
if [[ -z "${_SHA256SUM}" ]]; then
    echo "sudo is needed to use this script"
fi



while getopts ":t:s:c:w:u:n:h" opts; do
    case "${opts}" in
        t)
            TOPDIR=${OPTARG}
            ;;
        s)
            NEXTCLOUD_DIR=${OPTARG}
            ;;
        c)
            CACHE_SERV=${OPTARG}
            ;;
        w)
            WEB_SERV=${OPTARG}
            ;;
        u)
            WEB_USER=${OPTARG}
            ;;
        n)
            VERSION=${OPTARG}
            ;;
        h|*)
            usage
            exit 0
            ;;
    esac
done
shift $((OPTIND-1))

# Setting default values
if [[ -z "${WEB_SERV}" ]]; then
    WEB_SERV="apache2"
fi
if [[ -z "${WEB_USER}" ]]; then
    WEB_USER="www-data"
fi
if [[ -z "${CACHE_SERV}" ]]; then
    CACHE_SERV="redis-server"
fi
if [[ -z "${TOPDIR}" ]]; then
    TOPDIR="/var/www/html"
fi
if [[ -z "${NEXTCLOUD_DIR}" ]]; then
    NEXTCLOUD_DIR="nextcloud"
fi
if [[ -z "${VERSION}" ]]; then
    echo "Version is required"
    usage
    exit 1
fi

echo "#-#-#-#-#-#-#-#-#-#-#-#-#-#-#"
echo "Ok; will try to upgrade to version ${VERSION}"

echo "TOPDIR: ${TOPDIR}"
echo "WEB_USER: ${WEB_USER}"
echo "CACHE_SERV: ${CACHE_SERV}"
echo "WEB_SERV: ${WEB_SERV}"
echo "NEXTCLOUD_DIR: ${NEXTCLOUD_DIR}"
echo "#-#-#-#-#-#-#-#-#-#-#-#-#-#-#"


php_initial_check() {
    echo -e "Checking the PHP version used for php-fpm and the web user.... \n"
    FPM_CURRENT_VERSION=$(systemctl list-units| grep -E "fpm.+active.+running"| awk -F"[ -]" '{print $3}')
    WEB_PHP_VERSION=$("${_SUDO}" -u "${WEB_USER}" php --version| awk '{if (NR ==1 ) {print tolower($1)"-"$2}}'|awk -F"." '{print $1"."$2}')

    if [[ "${FPM_CURRENT_VERSION}" != "${WEB_PHP_VERSION}" ]]; then
        echo "php-fpm running version differs from the PHP binary version from ${WEB_USER} user."
        echo "Please fix this before running this script."

        echo '
        ###############################################################################
        # if version are differents, you may use the binary
        # php<version> instead of "php" to manually run the upgrade...
        # For example, "php occ", becomes  "php7.4 occ"
        # Otherwise, you need to modify the symbolic link for php
        # to target the right version (/etc/alternatives/php or directly /usr/bin/php).
        ###############################################################################'

        echo '
        ###############################################################################
        # If php-fpm version is not the good one,
        # You may also need to check the install and apache configuration.
        # See https://askubuntu.com/a/1319874
        ###############################################################################'
        echo "exit"
    fi


    PHP_VER=$("${_SUDO}" -u "${WEB_USER}" php --version |awk '{if ( $1 == "PHP" ) { print $2 }}' |cut -c 1-3)
    PHP_FPM="php${PHP_VER}-fpm"

}


php_initial_check

echo "Current ${WEB_USER} getent value:"
getent passwd "${WEB_USER}"

echo "Modifying shell of ${WEB_USER} to /bin/bash to run upgrade with that user"
usermod -s /bin/bash "${WEB_USER}"

_DATE=$(date '+%Y%m%d')

cd "${TOPDIR}" || exit 2

echo "Current content of TOPDIR..."
echo "###############"
ls -all
echo "###############"

# "df -h" or "ncdu" can be useful to remove some stuffs...

# Downloading version's tarball
"${_WGET}" "${NEXTCLOUD_DOWNLOAD_URL}"/nextcloud-"${VERSION}".tar.bz2
"${_WGET}" "${NEXTCLOUD_DOWNLOAD_URL}"/nextcloud-"${VERSION}".tar.bz2.sha256

# checking tarball and content
if ! $("${_SHA256SUM}" -c nextcloud-"${VERSION}".tar.bz2.sha256 |grep -Eq "OK|Réussi"); then echo -e "Checksum not Ok.......\nExiting."; exit; fi


# If checksum is ok
echo -e "Content of the archive.....\n"
tar -tvf nextcloud-"${VERSION}".tar.bz2

echo -e "Backup time .....\n"

# backup of nextcloud folders + current DB
rsync -Aavx "${NEXTCLOUD_DIR}"/ nextcloud-dirbkp_"${_DATE}"/



cd "${NEXTCLOUD_DIR}" || exit 2

echo -e "Switching to maintenance mode: On\n"
"${_SUDO}" -u "${WEB_USER}" php occ maintenance:mode --on

echo "Backuping database"
echo "Last one will be store in /var/backups/{mysql,pgsql}/"

if [[ -n "${DBBACKUPCMD}" ]]; then
    ${DBBACKUPCMD} "${_DATE}"
fi

# stopping services
systemctl stop "${WEB_SERV}" "${PHP_FPM}" "${CACHE_SERV}"

cd "${TOPDIR}" || exit 2

echo "Extracting nextcloud..."
tar -xf nextcloud-"${VERSION}".tar.bz2
# Copying data folder and config from the old one to the new version

echo "Restoring old configuration"
cp nextcloud-dirbkp_"${_DATE}"/config/config.php nextcloud/config/

# ISEM Hack for data symlink
if [[ $(file "${TOPDIR}/${NEXTCLOUD_DIR}/data") =~ "directory" ]]; then
    cp -r nextcloud-dirbkp_"${_DATE}"/data nextcloud/
elif [[ $(file "${TOPDIR}/${NEXTCLOUD_DIR}/data") =~ "symbolic" ]]; then
    DATA_TARGET=$(readlink "${TOPDIR}/${NEXTCLOUD_DIR}/data")
    cd "${NEXTCLOUD_DIR}" && ln -s "${DATA_TARGET}" data
fi


cd "${TOPDIR}" || exit 2

if [[ "${NEXTCLOUD_DIR}" != "nextcloud" ]]; then
    mv nextcloud "${NEXTCLOUD_DIR}"
fi

# Fixing permissions

echo -e "Fixing permissions\n"
chown -R "${WEB_USER}:${WEB_USER}" "${NEXTCLOUD_DIR}"
find "${NEXTCLOUD_DIR}"/ -type d -exec chmod 750 {} \;
find "${NEXTCLOUD_DIR}"/ -type f -exec chmod 640 {} \;

echo -e "Restarting everything\n"
systemctl start "${WEB_SERV}" "${PHP_FPM}" "${CACHE_SERV}"
cd "${NEXTCLOUD_DIR}/" || exit 2

echo -e "Upgrading... Please wait...\n"
sudo -u "${WEB_USER}" php occ upgrade

echo "############################################################"
echo "Status of services : "
systemctl status --no-pager  "${WEB_SERV}" "${PHP_FPM}" "${CACHE_SERV}"
echo "############################################################"

echo "Switching to maintenance mode: Off"
"${_SUDO}" -u "${WEB_USER}" php occ maintenance:mode --off
echo "Modifying shell of ${WEB_USER} to /usr/sbin/nologin"
usermod -s /usr/sbin/nologin "${WEB_USER}"

echo -e "\nCleaning source packages..."
rm -f "${TOPDIR}"/nextcloud-"${VERSION}".tar.bz2*

echo 'Finished !'
echo "Your old version of nextcloud is available at ${TOPDIR}/nextcloud-dirbkp_${_DATE}/"

echo -e "A reboot or restarting some services may be needed.
  Furthermore, you may also need to run additionnal upgrade commands, like:
  sudo -u ${WEB_USER} php ${TOPDIR}/${NEXTCLOUD_DIR}/occ db:add-missing-indices
  Please check your administration webpage for more informations."
