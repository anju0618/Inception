#!/bin/bash
set -e

FTP_PASSWORD=$(cat "$FTP_PASSWORD_FILE")

if ! id "$FTP_USER" >/dev/null 2>&1; then
    useradd -d "/home/${FTP_USER}/wordpress" -s /usr/sbin/nologin "$FTP_USER"
fi

echo "${FTP_USER}:${FTP_PASSWORD}" | chpasswd
mkdir -p "/home/${FTP_USER}/wordpress"
chown -R "${FTP_USER}:${FTP_USER}" "/home/${FTP_USER}/wordpress"
echo "$FTP_USER" > /etc/vsftpd.userlist

exec vsftpd /etc/vsftpd.conf
