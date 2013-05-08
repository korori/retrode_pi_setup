rm -rf python_games
sudo apt-get purge -y x11-common midori lxde python3 python3-minimal
sudo apt-get purge -y `sudo dpkg --get-selections | grep "\-dev" | sed s/install//`
sudo apt-get purge -y `sudo dpkg --get-selections | grep -v "deinstall" | grep python | sed s/install//`
sudo apt-get purge -y `sudo dpkg --get-selections | grep -v "deinstall" | grep python | sed s/install//`
sudo apt-get purge -y lxde-common lxde-icon-theme omxplayer
sudo apt-get purge -y `sudo dpkg --get-selections | grep -v "deinstall" | grep x11 | sed s/install//`
sudo apt-get purge -y gcc-4.5-base:armhf gcc-4.6-base:armhf libraspberrypi-doc xkb-data
sudo apt-get purge -y xdg-utils wireless-tools wpasupplicant penguinspuzzle menu menu-xdg samba-common firmware-atheros firmware-brcm80211 firmware-libertas firmware-ralink firmware-realtek
sudo apt-get autoremove --purge -y
sudo swapoff -a
sudo apt-get purge -y dphys-swapfile
sudo rm /var/swap
sudo rm -R /etc/X11
sudo rm -R /etc/wpa_supplicant
sudo rm -R /etc/console-setup
sudo rm -R /usr/share/icons
cd /var/log/ sudo 
rm `find . -type f`
sudo apt-get update
sudo apt-get -y dist-upgrade
sudo apt-get -y install git-core binutils
sudo apt-get clean all
sudo rm -R Desktop
rm ocr_pi.png