#!/bin/bash
#
# Copyright (C) 2017 ~ 2018 Deepin Technology Co., Ltd.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

# Setup username, password, timezone and keyboard layout.
# This script is used to setup system info after installation.

# Absolute path to config file.
# Do not read/write this file directly, call installer_get and installer_set
# instead.
CONF_FILE=/etc/deepin-installer.conf

. ./basic_utils.sh

. ./in_chroot/03_setup_user_experience.job
. ./in_chroot/09_generate_machine_id.job
. ./in_chroot/33_setup_lightdm_auto_login.job
. ./in_chroot/34_setup_livefs.job
. ./in_chroot/51_setup_keyboard.job
. ./in_chroot/52_setup_locale_timezone.job
. ./in_chroot/53_setup_user.job
. ./in_chroot/55_customize_user.job
. ./in_chroot/91_remove_unused_packages.job

add_uninstall_package() {
    local package=${1}
    local result=$(dpkg -l | grep "\\s${package}" | awk '{print $2}' | awk -F: '{print $1}' | grep "^${package}$" | wc -l)
    if [ ${result} == "1" ];then
      local list=$(installer_get "DI_UNINSTALL_PACKAGES")
      list="${list} $package"
      installer_set "DI_UNINSTALL_PACKAGES" "${list}"
    fi
}

# Remove component packages
remove_component_packages() {
  local DI_COMPONENT_UNINSTALL=$(installer_get "DI_COMPONENT_UNINSTALL")
  if [ ! -z "${DI_COMPONENT_UNINSTALL}" ];then
    local list=$(installer_get "DI_UNINSTALL_PACKAGES")
    list="${list} ${DI_COMPONENT_UNINSTALL}"
    installer_set "DI_UNINSTALL_PACKAGES" "${list}"
  fi
}

# Check whether btrfs filesystem is used in machine.
detect_btrfs() {
  for i in $(lsblk -o FSTYPE | sed '/^$/d' | uniq); do
    [ "${i}" = "btrfs" ] && return 0
  done
  return 1
}

# Purge packages
uninstall_packages() {
  if detect_btrfs; then
   add_uninstall_package "deepin-installer"
   add_uninstall_package "tshark wireshark-common"
  else
    add_uninstall_package "deepin-installer"
    add_uninstall_package "btrfs-tools"
    add_uninstall_package "tshark"
    add_uninstall_package "wireshark-common"
  fi

  local list=$(installer_get "DI_UNINSTALL_PACKAGES")
  apt-get -y purge ${list}
  # apt autoremove -y   // 屏蔽代码解决磁盘加密时选择非图形组建安装系统成功后，系统无法重启问题。根因：由于cryptsetup被apt autoremove 卸载导致无法启动
}

# Replace lightdm.conf with lightdm.conf.real.
cleanup_lightdm_deepin_installer() {
  local CONF_FILE=/etc/lightdm/lightdm.conf
  local TEMP_CONF_FILE=/etc/lightdm/lightdm.conf.real
  if [ -f "${TEMP_CONF_FILE}" ]; then
    mv -f "${TEMP_CONF_FILE}" "${CONF_FILE}"
  fi
}

# see after_chroot/88_copy_oem_license.job
cleanup_oem_license() {
	local OEM_LICENSE=/oem_license
	if [ -d "${OEM_LICENSE}" ]; then
		rm -rf "${OEM_LICENSE}"
	fi
}

cleanup_first_boot() {
  local FILE=/etc/deepin-installer-first-boot
  [ -f "${FILE}" ] && rm -f "${FILE}"

  if [ -f /lib/systemd/system/deepin-installer.target ]; then
    # Restore default target of systemd
    systemctl set-default -f graphical.target 
  fi

  # See in_chroot/generate_reboot_setup_file.job for more info.
  cleanup_lightdm_deepin_installer
}

setup_default_target() {
    msg "TARGET:before={$(systemctl get-default)}"
    local DI_COMPONENT_UNINSTALL=$(installer_get "DI_COMPONENT_UNINSTALL")
    if [[ "${DI_COMPONENT_UNINSTALL}" =~ ^(.* )?lightdm( .*)?$ ]]; then
         msg "TARGET:lightdm will be removed:{${DI_COMPONENT_UNINSTALL}}"
         systemctl set-default -f multi-user.target
    elif [ -f /usr/sbin/lightdm ]; then
         msg "TARGET:lightdm program found."
        systemctl set-default -f graphical.target
    else
        msg "TARGET:lightdm program NOT found."
        systemctl set-default -f multi-user.target
    fi
    msg "TARGET:after={$(systemctl get-default)}"
}

setup_bluetooth_service() {
    if [ -f /lib/systemd/system/bluetooth.service ]; then
        systemctl restart bluetooth.service
    fi
}

setup_grub_passwd(){
# grub edit password
GRUB_PASSWORD=$(installer_get "DI_GRUB_PASSWORD")
USERNAME=$(installer_get "DI_USERNAME")
if [ -n "$GRUB_PASSWORD" ];then
cat >> /etc/grub.d/00_header <<EOF
cat << P_EOF
set superusers="${USERNAME}"
password_pbkdf2 ${USERNAME} ${GRUB_PASSWORD}
P_EOF
EOF
update-grub
fi
}

oem_audit_mode() {
echo [Seat:*] >> /etc/lightdm/lightdm.conf

echo autologin-user=jenkins-builder >> /etc/lightdm/lightdm.conf

service ssh start
#ssh改为密钥免密码登录
cp /usr/share/deepin-installer/testrun.desktop /home/jenkins-builder/.config/autostart/

chown -R jenkins-builder:jenkins-builder /home/jenkins-builder/
}

main() {
  [ -f "${CONF_FILE}" ] || error "deepin-installer.conf not found"
  cat "${CONF_FILE}" | grep -v "PASSWORD" | grep -v "password"

  generate_machine_id
  setup_lightdm_auto_login
  setup_keyboard
  setup_locale_timezone
  setup_livefs

  # kill dde-system-daemon 因为它返回的头像是错误的
  if [ -f "/usr/lib/deepin-daemon/dde-session-daemon" ];then
    pkill -ef dde-system-daemon
  fi

  # setup_username_password_hostname() will clear value of DI_PASSWORD
  customize_user
  setup_username_password_hostname

  # 解决蓝牙主机名问题
  setup_bluetooth_service

  #设置grub密码
  setup_grub_passwd

  sync
  cleanup_oem_license
  cleanup_first_boot
  remove_component_packages
  setup_default_target
  uninstall_packages # 这必须是最后一步！
  sync

  oem_audit_mode
}

main
