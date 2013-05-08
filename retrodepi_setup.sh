#!/bin/bash

#  Retrode_Pi-Setup - Shell script for initializing Raspberry Pi 
#  with RetroArch, various cores, and EmulationStation (a graphical 
#  front end).
# 
#  (c) Copyright 2012  Florian M�ller (petrockblock@gmail.com)
# 
#  Retrode_Pi-Setup homepage: https://github.com/petrockblog/Retrode_Pi-Setup
# 
#  Permission to use, copy, modify and distribute Retrode_Pi-Setup in both binary and
#  source form, for non-commercial purposes, is hereby granted without fee,
#  providing that this license information and copyright notice appear with
#  all copies and any derived work.
# 
#  This software is provided 'as-is', without any express or implied
#  warranty. In no event shall the authors be held liable for any damages
#  arising from the use of this software.
# 
#  Retrode_Pi-Setup is freeware for PERSONAL USE only. Commercial users should
#  seek permission of the copyright holders first. Commercial use includes
#  charging money for Retrode_Pi-Setup or software derived from Retrode_Pi-Setup.
# 
#  The copyright holders request that bug fixes and improvements to the code
#  should be forwarded to them so everyone can benefit from the modifications
#  in future versions.
# 
#  Many, many thanks go to all people that provide the individual packages!!!
# 
#  Raspberry Pi is a trademark of the Raspberry Pi Foundation.
# 

__ERRMSGS=""
__INFMSGS=""
__doReboot=0

# HELPER FUNCTIONS ###

function ask()
{   
    echo -e -n "$@" '[y/n] ' ; read ans
    case "$ans" in
        y*|Y*) return 0 ;;
        *) return 1 ;;
    esac
}

function addLineToFile()
{
    if [[ -f "$2" ]]; then
        cp "$2" ./temp
        sudo mv "$2" "$2.old"
    fi
    echo "$1" >> ./temp
    sudo mv ./temp "$2"
    echo "Added $1 to file $2"
}

# arg 1: key, arg 2: value, arg 3: file
# make sure that a key-value pair is set in file
# key = value
function ensureKeyValue()
{
    if [[ -z $(egrep -i "#? *$1 = ""?[+|-]?[0-9]*[a-z]*"""? $3) ]]; then
        # add key-value pair
        echo "$1 = ""$2""" >> $3
    else
        # replace existing key-value pair
        toreplace=`egrep -i "#? *$1 = ""?[+|-]?[0-9]*[a-z]*"""? $3`
        sed $3 -i -e "s|$toreplace|$1 = ""$2""|g"
    fi     
}

# make sure that a key-value pair is NOT set in file
# # key = value
function disableKeyValue()
{
    if [[ -z $(egrep -i "#? *$1 = ""?[+|-]?[0-9]*[a-z]*"""? $3) ]]; then
        # add key-value pair
        echo "# $1 = ""$2""" >> $3
    else
        # replace existing key-value pair
        toreplace=`egrep -i "#? *$1 = ""?[+|-]?[0-9]*[a-z]*"""? $3`
        sed $3 -i -e "s|$toreplace|# $1 = ""$2""|g"
    fi     
}

# arg 1: key, arg 2: value, arg 3: file
# make sure that a key-value pair is set in file
# key=value
function ensureKeyValueShort()
{
    if [[ -z $(egrep -i "#? *$1\s?=\s?""?[+|-]?[0-9]*[a-z]*"""? $3) ]]; then
        # add key-value pair
        echo "$1=""$2""" >> $3
    else
        # replace existing key-value pair
        toreplace=`egrep -i "#? *$1\s?=\s?""?[+|-]?[0-9]*[a-z]*"""? $3`
        sed $3 -i -e "s|$toreplace|$1=""$2""|g"
    fi     
}

# make sure that a key-value pair is NOT set in file
# # key=value
function disableKeyValueShort()
{
    if [[ -z $(egrep -i "#? *$1=""?[+|-]?[0-9]*[a-z]*"""? $3) ]]; then
        # add key-value pair
        echo "# $1=""$2""" >> $3
    else
        # replace existing key-value pair
        toreplace=`egrep -i "#? *$1=""?[+|-]?[0-9]*[a-z]*"""? $3`
        sed $3 -i -e "s|$toreplace|# $1=""$2""|g"
    fi     
}

function printMsg()
{
    echo -e "\n= = = = = = = = = = = = = = = = = = = = =\n$1\n= = = = = = = = = = = = = = = = = = = = =\n"
}

function rel2abs() {
  cd "$(dirname $1)" && dir="$PWD"
  file="$(basename $1)"

  echo $dir/$file
}

function checkForInstalledAPTPackage()
{
    PKG_OK=$(dpkg-query -W --showformat='${Status}\n' $1|grep "install ok installed")
    echo Checking for somelib: $PKG_OK
    if [ "" == "$PKG_OK" ]; then
        echo "NOT INSTALLED: $1"
    else
        echo "installed: $1"
    fi    
}

function checkFileExistence()
{
    if [[ -f "$1" ]]; then
        ls -lh "$1" >> "$rootdir/debug.log"
    else
        echo "$1 does NOT exist." >> "$rootdir/debug.log"
    fi
}

# clones or updates the sources of a repository $2 into the directory $1
function gitPullOrClone()
{
    if [[ -d "$1/.git" ]]; then
        pushd "$1"
        git pull
    else
        rm -rf "$1" # makes sure that the directory IS empty
        mkdir -p "$1"
        git clone "$2" "$1"
        pushd "$1"
    fi
}

# END HELPER FUNCTIONS ###

function availFreeDiskSpace()
{
    local __required=$1
    local __avail=`df -P $rootdir | tail -n1 | awk '{print $4}'`

    if [[ "$__required" -le "$__avail" ]] || ask "Minimum recommended disk space (500 MB) not available. Try 'sudo raspi-config' to resize partition to full size. Only $__avail available at $rootdir continue anyway?"; then
        return 0;
    else
        exit 0;
    fi
}

function install_rpiupdate()
{
    # install latest rpi-update script (to enable firmware update)
    printMsg "Installing latest rpi-update script"
    # make sure that certificates are installed
    apt-get install -y ca-certificates
    wget http://goo.gl/1BOfJ -O /usr/bin/rpi-update && chmod +x /usr/bin/rpi-update
}

function run_rpiupdate()
{
    printMsg "Starting rpi-update script"
    /usr/bin/rpi-update
    __doReboot=1
    chmod 777 /dev/fb0
    ensureKeyValueShort "gpu_mem" "128" "/boot/config.txt"
}

# update APT repositories
function update_apt() 
{
    apt-get -y update
}

# upgrade APT packages
function upgrade_apt()
{
    apt-get -y upgrade
    chmod 777 /dev/fb0
    ensureKeyValueShort "gpu_mem" "128" "/boot/config.txt"
}

# add user $user to groups "video", "audio", and "input"
function add_to_groups()
{
    printMsg "Adding user $user to groups video, audio, and input."
    add_user_to_group $user video
    add_user_to_group $user audio
    add_user_to_group $user input
}

# add user $1 to group $2, create the group if it doesn't exist
function add_user_to_group()
{
    if [ -z $(egrep -i "^$2" /etc/group) ]
    then
      sudo addgroup $2
    fi
    sudo adduser $1 $2
}

# make sure ALSA, uinput, and joydev modules are active
function ensure_modules()
{
    printMsg "Enabling ALSA, uinput, and joydev modules permanently"
    sudo modprobe snd_bcm2835
    sudo modprobe uinput
    sudo modprobe joydev

    if ! grep -q "uinput" /etc/modules; then
        addLineToFile "uinput" "/etc/modules"
    else
        echo -e "uinput module already contained in /etc/modules"
    fi
    if ! grep -q "joydev" /etc/modules; then
        addLineToFile "joydev" "/etc/modules"
    else
        echo -e "joydev module already contained in /etc/modules"
    fi    
}

# needed by SDL for working joypads
function exportSDLNOMOUSE()
{
    printMsg "Exporting SDL_NOMOUSE=1 permanently to $home/.bashrc"
    export SDL_NOMOUSE=1
    if ! grep -q "export SDL_NOMOUSE=1" $home/.bashrc; then
        echo -e "\nexport SDL_NOMOUSE=1" >> $home/.bashrc
    else
        echo -e "SDL_NOMOUSE=1 already contained in $home/.bashrc"
    fi    
}

# make sure that all needed packages are installed
function installAPTPackages()
{
    printMsg "Making sure that all needed packaged are installed"
    apt-get install -y libsdl1.2-dev screen scons libasound2-dev pkg-config libgtk2.0-dev \
                        libboost-filesystem-dev libboost-system-dev zip python-imaging \
                        libfreeimage-dev libfreetype6-dev libxml2 libxml2-dev libbz2-dev \
                        libaudiofile-dev libsdl-sound1.2-dev libsdl-mixer1.2-dev \
                        joystick fbi gcc-4.7 automake1.4

    # remove PulseAudio since this is slowing down the whole system significantly
    apt-get remove -y pulseaudio
    apt-get -y autoremove
}


# prepare folder structure for emulator, cores, front end, and roms
function prepareFolders()
{
    printMsg "Creating folder structure for emulator, front end, cores, and roms"

    pathlist=()
    pathlist+=("$rootdir/roms")
    pathlist+=("$rootdir/roms/atari2600")
    pathlist+=("$rootdir/roms/gamegear")
    pathlist+=("$rootdir/roms/gb")
    pathlist+=("$rootdir/roms/gba")
    pathlist+=("$rootdir/roms/mastersystem")
    pathlist+=("$rootdir/roms/megadrive")
    pathlist+=("$rootdir/roms/snes")
    pathlist+=("$rootdir/emulators")

    for elem in "${pathlist[@]}"
    do
        if [[ ! -d $elem ]]; then
            mkdir -p $elem
            chown $user $elem
            chgrp $user $elem
        fi
    done    
}

# settings for RetroArch
function configureRetroArch()
{
    printMsg "Configuring RetroArch in $rootdir/configs/all/retroarch.cfg"

    if [[ ! -f "$rootdir/configs/all/retroarch.cfg" ]]; then
        mkdir -p "$rootdir/configs/all/"
        mkdir -p "$rootdir/configs/atari2600/"
        echo -e "# All settings made here will override the global settings for the current emulator core\n" >> $rootdir/configs/atari2600/retroarch.cfg
        mkdir -p "$rootdir/configs/doom/"
        echo -e "# All settings made here will override the global settings for the current emulator core\n" >> $rootdir/configs/gb/retroarch.cfg
        mkdir -p "$rootdir/configs/gba/"
        echo -e "# All settings made here will override the global settings for the current emulator core\n" >> $rootdir/configs/gba/retroarch.cfg
        mkdir -p "$rootdir/configs/gamegear/"
        echo -e "# All settings made here will override the global settings for the current emulator core\n" >> $rootdir/configs/gamegear/retroarch.cfg
        mkdir -p "$rootdir/configs/mastersystem/"
        echo -e "# All settings made here will override the global settings for the current emulator core\n" >> $rootdir/configs/mastersystem/retroarch.cfg
        mkdir -p "$rootdir/configs/snes/"
        echo -e "# All settings made here will override the global settings for the current emulator core\n" >> $rootdir/configs/snes/retroarch.cfg
        cp /etc/retroarch.cfg "$rootdir/configs/all/"
    fi

    ensureKeyValue "system_directory" "$rootdir/emulators/" "$rootdir/configs/all/retroarch.cfg"
    ensureKeyValue "video_aspect_ratio" "1.33" "$rootdir/configs/all/retroarch.cfg"
    ensureKeyValue "video_smooth" "false" "$rootdir/configs/all/retroarch.cfg"

    # enable and configure rewind feature
    ensureKeyValue "rewind_enable" "true" "$rootdir/configs/all/retroarch.cfg"
    ensureKeyValue "rewind_buffer_size" "10" "$rootdir/configs/all/retroarch.cfg"
    ensureKeyValue "rewind_granularity" "2" "$rootdir/configs/all/retroarch.cfg"
    ensureKeyValue "input_rewind" "r" "$rootdir/configs/all/retroarch.cfg"
}

# install RetroArch emulator
function install_retroarch()
{
    printMsg "Installing RetroArch emulator"
    gitPullOrClone "$rootdir/RetroArch" git://github.com/Themaister/RetroArch.git
    ./configure
    make
    sudo make install
    if [[ ! -f "/usr/local/bin/retroarch" ]]; then
        __ERRMSGS="$__ERRMSGS Could not successfully compile and install RetroArch."
    fi  
    popd
}

function sortromsalphabet()
{
    clear
    pathlist=()
    pathlist+=("$rootdir/roms/amiga")
    pathlist+=("$rootdir/roms/atari2600")
    pathlist+=("$rootdir/roms/fba")
    pathlist+=("$rootdir/roms/gamegear")
    pathlist+=("$rootdir/roms/gb")
    pathlist+=("$rootdir/roms/gba")
    pathlist+=("$rootdir/roms/gbc")
    pathlist+=("$rootdir/roms/intellivision")
    pathlist+=("$rootdir/roms/mame")
    pathlist+=("$rootdir/roms/mastersystem")
    pathlist+=("$rootdir/roms/megadrive")
    pathlist+=("$rootdir/roms/neogeo")
    pathlist+=("$rootdir/roms/nes")
    pathlist+=("$rootdir/roms/snes")
    pathlist+=("$rootdir/roms/pcengine")
    pathlist+=("$rootdir/roms/psx")
    pathlist+=("$rootdir/roms/zxspectrum")
    printMsg "Sorting roms alphabetically"
    for elem in "${pathlist[@]}"
    do
        echo "Sorting roms in folder $elem"
        if [[ -d $elem ]]; then
            for x in {a..z}
            do
                if [[ ! -d $elem/$x ]]; then
                    mkdir $elem/$x
                fi
                find $elem -maxdepth 1 -type f -iname "$x*"| while read line; do
                    mv "$line" "$elem/$x/$(basename "${line,,}")"
                done
            done
            if [[ -f "$elem/g/gamelist.xml" ]]; then
                mv "$elem/g/gamelist.xml" "$elem/gamelist.xml"
            fi
            if [[ -f "$elem/t/theme.xml" ]]; then
                mv "$elem/t/theme.xml" "$elem/theme.xml"
            fi
            if [[ ! -d "$elem/#" ]]; then
                mkdir "$elem/#"
            fi
            find $elem -maxdepth 1 -type f -iname "[0-9]*"| while read line; do
                mv "$line" "$elem/#/$(basename "${line,,}")"
            done
        fi
    done  
    chgrp -R $user $rootdir/roms
    chown -R $user $rootdir/roms
}

# downloads and installs pre-compiles binaries of all essential programs and libraries
function downloadBinaries()
{
    wget -O binariesDownload.tar.bz2 http://blog.Retrode.org/?wpdmdl=3
    tar -jxvf binariesDownload.tar.bz2 -C $rootdir
    pushd $rootdir/Retrode_Pi
    cp -r * ../
    popd

    # handle Doom emulator specifics
    cp $rootdir/emulators/libretro-prboom/prboom.wad $rootdir/roms/doom/
    chgrp $user $rootdir/roms/doom/prboom.wad
    chown $user $rootdir/roms/doom/prboom.wad

    rm -rf $rootdir/Retrode_Pi
    rm binariesDownload.tar.bz2    
}

# downloads and installs theme files for Emulation Station
function install_esthemes()
{
    printMsg "Installing themes for Emulation Station"
    wget -O themesDownload.tar.bz2 http://blog.Retrode.org/?wpdmdl=2
    tar -jxvf themesDownload.tar.bz2 -C $home/

    chgrp -R $user $home/.emulationstation
    chown -R $user $home/.emulationstation

    rm themesDownload.tar.bz2
}

# sets the ARM frequency of the Raspberry to a specific value
function setArmFreq()
{
    cmd=(dialog --backtitle "Retrode.org - Retrode_Pi Setup. Installation folder: $rootdir for user $user" --menu "Choose the ARM frequency. However, it is suggested that you change this with the raspi-config script!" 22 76 16)
    options=(700 "(default)"
             750 "(do this at your own risk!)"
             800 "(do this at your own risk!)"
             850 "(do this at your own risk!)"
             900 "(do this at your own risk!)"
             1000 "(do this at your own risk!)")
    armfreqchoice=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
    if [ "$armfreqchoice" != "" ]; then                
        if [[ -z $(egrep -i "#? *arm_freq=[0-9]*" /boot/config.txt) ]]; then
            # add key-value pair
            echo "arm_freq=$armfreqchoice" >> /boot/config.txt
        else
            # replace existing key-value pair
            toreplace=`egrep -i "#? *arm_freq=[0-9]*" /boot/config.txt`
            sed /boot/config.txt -i -e "s|$toreplace|arm_freq=$armfreqchoice|g"
        fi 
        dialog --backtitle "Retrode.org - Retrode_Pi Setup. Installation folder: $rootdir for user $user" --msgbox "ARM frequency set to $armfreqchoice MHz. If you changed the frequency, you need to reboot." 22 76    
    fi
}

# sets the SD ram frequency of the Raspberry to a specific value
function setSDRAMFreq()
{
    cmd=(dialog --backtitle "Retrode.org - Retrode_Pi Setup. Installation folder: $rootdir for user $user" --menu "Choose the ARM frequency. However, it is suggested that you change this with the raspi-config script!" 22 76 16)
    options=(400 "(default)"
             425 "(do this at your own risk!)"
             450 "(do this at your own risk!)"
             475 "(do this at your own risk!)"
             500 "(do this at your own risk!)")
    sdramfreqchoice=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
    if [ "$sdramfreqchoice" != "" ]; then                
        if [[ -z $(egrep -i "#? *sdram_freq=[0-9]*" /boot/config.txt) ]]; then
            # add key-value pair
            echo "sdram_freq=$sdramfreqchoice" >> /boot/config.txt
        else
            # replace existing key-value pair
            toreplace=`egrep -i "#? *sdram_freq=[0-9]*" /boot/config.txt`
            sed /boot/config.txt -i -e "s|$toreplace|sdram_freq=$sdramfreqchoice|g"
        fi 
        dialog --backtitle "Retrode.org - Retrode_Pi Setup. Installation folder: $rootdir for user $user" --msgbox "SDRAM frequency set to $sdramfreqchoice MHz. If you changed the frequency, you need to reboot." 22 76    
    fi
}

# configure sound settings
function configureSoundsettings()
{
    printMsg "Enabling ALSA thread-based audio driver for RetroArch in $rootdir/configs/all/retroarch.cfg"    

    # RetroArch settings
    ensureKeyValue "audio_driver" "alsathread" "$rootdir/configs/all/retroarch.cfg"
    ensureKeyValue "audio_out_rate" "48000" "$rootdir/configs/all/retroarch.cfg"

    # ALSA settings
    mv /etc/asound.conf /etc/asound.conf.bak
    cat >> /etc/asound.conf << _EOF_
pcm.!default {
type hw
card 0
}

ctl.!default {
type hw
card 0
}
_EOF_

}

# Disables safe mode (http://www.raspberrypi.org/phpBB3/viewtopic.php?p=129413) in order to make GPIO adapters work
function setAvoidSafeMode()
{
    if [[ -z $(egrep -i "#? *avoid_safe_mode=[0-9]*" /boot/config.txt) ]]; then
        # add key-value pair
        echo "avoid_safe_mode=1" >> /boot/config.txt
    else
        # replace existing key-value pair
        toreplace=`egrep -i "#? *avoid_safe_mode=[0-9]*" /boot/config.txt`
        sed /boot/config.txt -i -e "s|$toreplace|avoid_safe_mode=1|g"
    fi     
}

# shows help information in the console
function showHelp()
{
    echo ""
    echo "Retrode_Pi Setup script"
    echo "====================="
    echo ""
    echo "The script installs the RetroArch emulator base with various cores and a graphical front end."
    echo "Because it needs to install some APT packages it has to be run with root priviliges."
    echo ""
    echo "Usage:"
    echo "sudo ./retrodepi_setup.sh: The installation directory is /home/pi/Retrode_Pi for user pi"
    echo "sudo ./retrodepi_setup.sh USERNAME: The installation directory is /home/USERNAME/Retrode_Pi for user USERNAME"
    echo "sudo ./retrodepi_setup.sh USERNAME ABSPATH: The installation directory is ABSPATH for user USERNAME"
    echo ""
}

# Start Emulation Station on boot or not?
function changeBootbehaviour()
{
    cmd=(dialog --backtitle "Retrode.org - Retrode_Pi Setup. Installation folder: $rootdir for user $user" --menu "Choose the desired boot behaviour." 22 76 16)
    options=(1 "Original boot behaviour"
             2 "Start Emulation Station at boot.")
    choices=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
    if [ "$choices" != "" ]; then
        case $choices in
            1) sed /etc/inittab -i -e "s|1:2345:respawn:/bin/login -f $user tty1 </dev/tty1 >/dev/tty1 2>&1|1:2345:respawn:/sbin/getty --noclear 38400 tty1|g"
               sed /etc/profile -i -e "/emulationstation/d"
               dialog --backtitle "Retrode.org - Retrode_Pi Setup. Installation folder: $rootdir for user $user" --msgbox "Enabled original boot behaviour." 22 76    
                            ;;
            2) sed /etc/inittab -i -e "s|1:2345:respawn:/sbin/getty --noclear 38400 tty1|1:2345:respawn:\/bin\/login -f $user tty1 \<\/dev\/tty1 \>\/dev\/tty1 2\>\&1|g"
               if [ -z $(egrep -i "emulationstation$" /etc/profile) ]
               then
                   echo "[ -n \"\${SSH_CONNECTION}\" ] || emulationstation" >> /etc/profile
               fi
               dialog --backtitle "Retrode.org - Retrode_Pi Setup. Installation folder: $rootdir for user $user" --msgbox "Emulation Station is now starting on boot." 22 76    
                            ;;
        esac
    else
        break
    fi    
}

function installGameconGPIOModule()
{
        clear

    dialog --title " gamecon_gpio_rpi installation " --clear \
    --yesno "Gamecon_gpio_rpi requires thats most recent kernel (firmware)\
    is installed and active. Continue with gamecon_gpio_rpi\
    installation?" 22 76
    case $? in
      0)
        echo "Starting installation.";;
      *)
        return 0;;
    esac

    #install dkms
    apt-get install -y dkms

    #reconfigure / install headers (takes a a while)
    if [ "$(dpkg-query -W -f='${Version}' linux-headers-$(uname -r))" = "$(uname -r)-2" ]; then
        dpkg-reconfigure linux-headers-`uname -r`
    else
        wget http://www.niksula.hut.fi/~mhiienka/Rpi/linux-headers-rpi/linux-headers-`uname -r`_`uname -r`-2_armhf.deb
        dpkg -i linux-headers-`uname -r`_`uname -r`-2_armhf.deb
        rm linux-headers-`uname -r`_`uname -r`-2_armhf.deb
    fi

    #install gamecon
    if [ "`dpkg-query -W -f='${Version}' gamecon-gpio-rpi-dkms`" = "0.9" ]; then
        #dpkg-reconfigure gamecon-gpio-rpi-dkms
        echo "gamecon is the newest version"
    else
            wget http://www.niksula.hut.fi/~mhiienka/Rpi/gamecon-gpio-rpi-dkms_0.9_all.deb
            dpkg -i gamecon-gpio-rpi-dkms_0.9_all.deb
        rm gamecon-gpio-rpi-dkms_0.9_all.deb
    fi

    #test if module installation is OK
    if [[ -n $(modinfo -n gamecon_gpio_rpi | grep gamecon_gpio_rpi.ko) ]]; then
            dialog --backtitle "Retrode.org - Retrode_Pi Setup. Installation folder: $rootdir for user $user" --msgbox "Gamecon GPIO driver successfully installed. \
        Use 'zless /usr/share/doc/gamecon_gpio_rpi/README.gz' to read how to use it." 22 76
    else
        dialog --backtitle "Retrode.org - Retrode_Pi Setup. Installation folder: $rootdir for user $user" --msgbox "Gamecon GPIO driver installation FAILED"\
        22 76
    fi
}

function enableGameconSnes()
{
    if [ "`dpkg-query -W -f='${Status}' gamecon-gpio-rpi-dkms`" != "install ok installed" ]; then
        dialog --msgbox "gamecon_gpio_rpi not found, install it first" 22 76
        return 0
    fi

    REVSTRING=`cat /proc/cpuinfo |grep Revision | cut -d ':' -f 2 | tr -d ' \n' | tail -c 4`
    case "$REVSTRING" in
          "0002"|"0003")
             GPIOREV=1 
             ;;
          *)
             GPIOREV=2
             ;;
    esac

dialog --msgbox "\
__________\n\
         |          ### Board gpio revision $GPIOREV detected ###\n\
    + *  |\n\
    * *  |\n\
    1 -  |          The driver is set to use the following configuration\n\
    2 *  |          for 2 SNES controllers:\n\
    * *  |\n\
    * *  |\n\
    * *  |          + = power\n\
    * *  |          - = ground\n\
    * *  |          C = clock\n\
    C *  |          L = latch\n\
    * *  |          1 = player1 pad\n\
    L *  |          2 = player2 pad\n\
    * *  |          * = unconnected\n\
         |\n\
         |" 22 76

    if [[ -n $(lsmod | grep gamecon_gpio_rpi) ]]; then
        rmmod gamecon_gpio_rpi
    fi

    if [ $GPIOREV = 1 ]; then
        modprobe gamecon_gpio_rpi map=0,1,1,0
    else
        modprobe gamecon_gpio_rpi map=0,0,1,0,0,1
    fi

    dialog --title " Update $rootdir/configs/all/retroarch.cfg " --clear \
        --yesno "Would you like to update button mappings \
    to $rootdir/configs/all/retroarch.cfg ?" 22 76

      case $? in
       0)
    if [ $GPIOREV = 1 ]; then
            ensureKeyValue "input_player1_joypad_index" "0" "$rootdir/configs/all/retroarch.cfg"
            ensureKeyValue "input_player2_joypad_index" "1" "$rootdir/configs/all/retroarch.cfg"
    else
        ensureKeyValue "input_player1_joypad_index" "1" "$rootdir/configs/all/retroarch.cfg"
        ensureKeyValue "input_player2_joypad_index" "0" "$rootdir/configs/all/retroarch.cfg"
    fi

        ensureKeyValue "input_player1_a_btn" "0" "$rootdir/configs/all/retroarch.cfg"
        ensureKeyValue "input_player1_b_btn" "1" "$rootdir/configs/all/retroarch.cfg"
        ensureKeyValue "input_player1_x_btn" "2" "$rootdir/configs/all/retroarch.cfg"
        ensureKeyValue "input_player1_y_btn" "3" "$rootdir/configs/all/retroarch.cfg"
        ensureKeyValue "input_player1_l_btn" "4" "$rootdir/configs/all/retroarch.cfg"
        ensureKeyValue "input_player1_r_btn" "5" "$rootdir/configs/all/retroarch.cfg"
        ensureKeyValue "input_player1_start_btn" "7" "$rootdir/configs/all/retroarch.cfg"
        ensureKeyValue "input_player1_select_btn" "6" "$rootdir/configs/all/retroarch.cfg"
        ensureKeyValue "input_player1_left_axis" "-0" "$rootdir/configs/all/retroarch.cfg"
        ensureKeyValue "input_player1_up_axis" "-1" "$rootdir/configs/all/retroarch.cfg"
        ensureKeyValue "input_player1_right_axis" "+0" "$rootdir/configs/all/retroarch.cfg"
        ensureKeyValue "input_player1_down_axis" "+1" "$rootdir/configs/all/retroarch.cfg"

        ensureKeyValue "input_player2_a_btn" "0" "$rootdir/configs/all/retroarch.cfg"
        ensureKeyValue "input_player2_b_btn" "1" "$rootdir/configs/all/retroarch.cfg"
        ensureKeyValue "input_player2_x_btn" "2" "$rootdir/configs/all/retroarch.cfg"
        ensureKeyValue "input_player2_y_btn" "3" "$rootdir/configs/all/retroarch.cfg"
        ensureKeyValue "input_player2_l_btn" "4" "$rootdir/configs/all/retroarch.cfg"
        ensureKeyValue "input_player2_r_btn" "5" "$rootdir/configs/all/retroarch.cfg"
        ensureKeyValue "input_player2_start_btn" "7" "$rootdir/configs/all/retroarch.cfg"
        ensureKeyValue "input_player2_select_btn" "6" "$rootdir/configs/all/retroarch.cfg"
        ensureKeyValue "input_player2_left_axis" "-0" "$rootdir/configs/all/retroarch.cfg"
        ensureKeyValue "input_player2_up_axis" "-1" "$rootdir/configs/all/retroarch.cfg"
        ensureKeyValue "input_player2_right_axis" "+0" "$rootdir/configs/all/retroarch.cfg"
        ensureKeyValue "input_player2_down_axis" "+1" "$rootdir/configs/all/retroarch.cfg"
    ;;
       *)
        ;;
      esac

    dialog --title " Enable SNES configuration permanently " --clear \
        --yesno "Would you like to permanently enable SNES configuration?\
        " 22 76

    case $? in
      0)
    if [[ -z $(cat /etc/modules | grep gamecon_gpio_rpi) ]]; then
    if [ $GPIOREV = 1 ]; then
                addLineToFile "gamecon_gpio_rpi map=0,1,1,0" "/etc/modules"
    else
        addLineToFile "gamecon_gpio_rpi map=0,0,1,0,0,1" "/etc/modules"
    fi
    fi
    ;;
      *)
        #TODO: delete the line from /etc/modules
        ;;
    esac

    dialog --backtitle "Retrode.org - Retrode_Pi Setup. Installation folder: $rootdir for user $user" --msgbox \
    "Gamecon GPIO driver enabled with 2 SNES pads." 22 76
}

function checkNeededPackages()
{
    doexit=0
    type -P git &>/dev/null && echo "Found git command." || { echo "Did not find git. Try 'sudo apt-get install -y git' first."; doexit=1; }
    type -P dialog &>/dev/null && echo "Found dialog command." || { echo "Did not find dialog. Try 'sudo apt-get install -y dialog' first."; doexit=1; }
    if [[ doexit -eq 1 ]]; then
        exit 1
    fi
}

function main_reboot()
{
    clear
    shutdown -r now    
}

# checks all kinds of essential files for existence and logs the results into the file debug.log
function createDebugLog()
{
    clear
    printMsg "Generating debug log"

    echo "RetroArch files:" > "$rootdir/debug.log"

    # existence of files
    checkFileExistence "/usr/local/bin/retroarch"
    checkFileExistence "/usr/local/bin/retroarch-zip"
    checkFileExistence "$rootdir/configs/all/retroarch.cfg"
    echo -e "\nActive lines in $rootdir/configs/all/retroarch.cfg:" >> "$rootdir/debug.log"
    sed '/^$\|^#/d' "$rootdir/configs/all/retroarch.cfg"  >>  "$rootdir/debug.log"

    echo -e "\nEmulation Station files:" >> "$rootdir/debug.log"
    checkFileExistence "$rootdir/supplementary/EmulationStation/emulationstation"
    checkFileExistence "$rootdir/../.emulationstation/es_systems.cfg"
    checkFileExistence "$rootdir/../.emulationstation/es_input.cfg"
    echo -e "\nContent of es_systems.cfg:" >> "$rootdir/debug.log"
    cat "$rootdir/../.emulationstation/es_systems.cfg" >> "$rootdir/debug.log"
    echo -e "\nContent of es_input.cfg:" >> "$rootdir/debug.log"
    cat "$rootdir/../.emulationstation/es_input.cfg" >> "$rootdir/debug.log"

    echo -e "\nEmulators and cores:" >> "$rootdir/debug.log"
    checkFileExistence "`find $rootdir/emulators/stella-libretro/ -name "*libretro*.so"`"
    checkFileExistence "`find $rootdir/emulators/gambatte-libretro/ -name "*libretro*.so"`"
    checkFileExistence "`find $rootdir/emulators/pocketsnes-libretro/ -name "*libretro*.so"`"

    echo -e "\nSummary of ROMS directory:" >> "$rootdir/debug.log"
    du -ch --max-depth=1 "$rootdir/roms/" >> "$rootdir/debug.log"

    echo -e "\nUnrecognized ROM extensions:" >> "$rootdir/debug.log"
    find "$rootdir/roms/atari2600/" -type f ! \( -iname "*.bin" -or -iname "*.jpg" -or -iname "*.xml" \) >> "$rootdir/debug.log"
    find "$rootdir/roms/gamegear/" -type f ! \( -iname "*.gg" -or -iname "*.jpg" -or -iname "*.xml" \) >> "$rootdir/debug.log"
    find "$rootdir/roms/gba/" -type f ! \( -iname "*.gba" -or -iname "*.jpg" -or -iname "*.xml" \) >> "$rootdir/debug.log"
    find "$rootdir/roms/gbc/" -type f ! \( -iname "*.gb" -or -iname "*.jpg" -or -iname "*.xml" \) >> "$rootdir/debug.log"
    find "$rootdir/roms/mastersystem/" -type f ! \( -iname "*.sms" -or -iname "*.jpg" -or -iname "*.xml" \) >> "$rootdir/debug.log"
    find "$rootdir/roms/megadrive/" -type f ! \( -iname "*.smd" -or -iname "*.jpg" -or -iname "*.xml" \) >> "$rootdir/debug.log"
    find "$rootdir/roms/snes/" -type f ! \( -iname "*.smc" -or -iname "*.jpg" -or -iname "*.xml" \) >> "$rootdir/debug.log"

    echo -e "\nCheck for needed APT packages:" >> "$rootdir/debug.log"
    checkForInstalledAPTPackage "libsdl1.2-dev" >> "$rootdir/debug.log"
    checkForInstalledAPTPackage "screen" >> "$rootdir/debug.log"
    checkForInstalledAPTPackage "scons" >> "$rootdir/debug.log"
    checkForInstalledAPTPackage "libasound2-dev" >> "$rootdir/debug.log"
    checkForInstalledAPTPackage "pkg-config" >> "$rootdir/debug.log"
    checkForInstalledAPTPackage "libgtk2.0-dev" >> "$rootdir/debug.log"
    checkForInstalledAPTPackage "libboost-filesystem-dev" >> "$rootdir/debug.log"
    checkForInstalledAPTPackage "libboost-system-dev" >> "$rootdir/debug.log"
    checkForInstalledAPTPackage "zip" >> "$rootdir/debug.log"
    checkForInstalledAPTPackage "libxml2" >> "$rootdir/debug.log"
    checkForInstalledAPTPackage "libxml2-dev" >> "$rootdir/debug.log"
    checkForInstalledAPTPackage "libbz2-dev" >> "$rootdir/debug.log"
    checkForInstalledAPTPackage "python-imaging" >> "$rootdir/debug.log"
    checkForInstalledAPTPackage "libfreeimage-dev" >> "$rootdir/debug.log"
    checkForInstalledAPTPackage "libfreetype6-dev" >> "$rootdir/debug.log"
    checkForInstalledAPTPackage "libaudiofile-dev" >> "$rootdir/debug.log"
    checkForInstalledAPTPackage "libsdl-sound1.2-dev" >> "$rootdir/debug.log"
    checkForInstalledAPTPackage "libsdl-mixer1.2-dev" >> "$rootdir/debug.log"

    echo -e "\nEnd of log file" >> "$rootdir/debug.log" >> "$rootdir/debug.log"

    dialog --backtitle "Retrode.org - Retrode_Pi Setup. Installation folder: $rootdir for user $user" --msgbox "Debug log was generated in $rootdir/debug.log" 22 76    

}

# download, extract, and install binaries
function main_binaries()
{
    __INFMSGS=""

    clear
    printMsg "Binaries-based installation"

    install_rpiupdate
    update_apt
    upgrade_apt
    run_rpiupdate
    installAPTPackages
    ensure_modules
    add_to_groups
    exportSDLNOMOUSE
    prepareFolders
    downloadBinaries
    fixForXBian
    
    # install RetroArch
    install -m755 $rootdir/RetroArch/retroarch /usr/local/bin
    install -m644 $rootdir/RetroArch/retroarch.cfg /etc/retroarch.cfg
    install -m755 $rootdir/RetroArch/retroarch-zip /usr/local/bin
    configureRetroArch
    configure_snes
    install_esthemes
    configureSoundsettings
    install_scummvm
    install_zmachine
    install_zxspectrum

    # install DGEN
    test -z "/usr/local/bin" || /bin/mkdir -p "/usr/local/bin"
    /usr/bin/install -c $rootdir/emulators/dgen-sdl-1.31/installdir/usr/local/bin/dgen $rootdir/emulators/dgen-sdl-1.31/installdir/usr/local/bin/dgen_tobin '/usr/local/bin'
    test -z "/usr/local/share/man/man1" || /bin/mkdir -p "/usr/local/share/man/man1"
    /usr/bin/install -c -m 644 $rootdir/emulators/dgen-sdl-1.31/installdir/usr/local/share/man/man1/dgen.1 $rootdir/emulators/dgen-sdl-1.31/installdir/usr/local/share/man/man1/dgen_tobin.1 '/usr/local/share/man/man1'
    test -z "/usr/local/share/man/man5" || /bin/mkdir -p "/usr/local/share/man/man5"
    /usr/bin/install -c -m 644 $rootdir/emulators/dgen-sdl-1.31/installdir/usr/local/share/man/man5/dgenrc.5 '/usr/local/share/man/man5'
    configureDGEN

    chgrp -R $user $rootdir
    chown -R $user $rootdir

    setAvoidSafeMode

    createDebugLog

    __INFMSGS="$__INFMSGS The Amiga emulator can be started from command line with '$rootdir/emulators/uae4all/uae4all'. Note that you must manually copy a Kickstart rom with the name 'kick.rom' to the directory $rootdir/emulators/uae4all/."
    __INFMSGS="$__INFMSGS You need to copy NeoGeo BIOS files to the folder '$rootdir/emulators/gngeo-0.7/neogeo-bios/'."
    __INFMSGS="$__INFMSGS You need to copy Intellivision BIOS files to the folder '/usr/local/share/jzintv/rom'."

    if [[ ! -z $__INFMSGS ]]; then
        dialog --backtitle "Retrode.org - Retrode_Pi Setup. Installation folder: $rootdir for user $user" --msgbox "$__INFMSGS" 20 60    
    fi

    dialog --backtitle "Retrode.org - Retrode_Pi Setup. Installation folder: $rootdir for user $user" --msgbox "Finished tasks.\nStart the front end with 'emulationstation'. You now have to copy roms to the roms folders. Have fun!" 22 76    
}

function main_updatescript()
{
  scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
  pushd $scriptdir
  if [[ ! -d .git ]]; then
    dialog --backtitle "Retrode.org - Retrode_Pi Setup." --msgbox "Cannot find direcotry '.git'. Please clone the Retrode_Pi Setup script via 'git clone git://github.com/korori/retrode_pi.git'" 20 60    
    popd
    return
  fi
  git pull
  popd
  dialog --backtitle "Retrode.org - Retrode_Pi Setup." --msgbox "Fetched the latest version of the Retrode_Pi Setup script. You need to restart the script." 20 60    
}
function main_setup(){

	#ATARI 2600
	atari2600

	#GBA
	install_gba

	#MEGA DRIVE/GENESIS
	install_megadrive

	#MASTER SYSTEM
	install_megadriveLibretro

	#GAMEBOY
	install_gbc

	#SNES
	install_snes
	configure_snes

	#GENESIS
	configureDGEN
	install_dgen

}
# install Game Boy Color emulator core
function install_gbc()
{
    printMsg "Installing Game Boy Color core"
    gitPullOrClone "$rootdir/emulators/gambatte-libretro" git://github.com/libretro/gambatte-libretro.git
    make -C libgambatte -f Makefile.libretro
    if [[ -z `find $rootdir/emulators/gambatte-libretro/libgambatte/ -name "*libretro*.so"` ]]; then
        __ERRMSGS="$__ERRMSGS Could not successfully compile Game Boy Color core."
    fi      
    popd
}

# install Atari 2600 core
function install_atari2600()
{
    printMsg "Installing Atari 2600 core"
    gitPullOrClone "$rootdir/emulators/stella-libretro" git://github.com/libretro/stella-libretro.git
    # remove msse and msse2 flags from Makefile, just a hack here to make it compile on the Raspberry
    sed 's|-msse2 ||g;s|-msse ||g' Makefile >> Makefile.rpi
    make -f Makefile.rpi
    if [[ -z `find $rootdir/emulators/stella-libretro/ -name "*libretro*.so"` ]]; then
        __ERRMSGS="$__ERRMSGS Could not successfully compile Atari 2600 core."
    fi  
    popd    
}



# configure DGEN
function configureDGEN()
{
    chmod 777 /dev/fb0

    mkdir /home/$user/.dgen/
    chown -R $user /home/$user/.dgen/
    chgrp -R $user /home/$user/.dgen/
    cp sample.dgenrc /home/$user/.dgen/dgenrc 
    ensureKeyValue "joypad1_b0" "A" /home/$user/.dgen/dgenrc
    ensureKeyValue "joypad1_b1" "B" /home/$user/.dgen/dgenrc
    ensureKeyValue "joypad1_b3" "C" /home/$user/.dgen/dgenrc
    ensureKeyValue "joypad1_b6" "MODE" /home/$user/.dgen/dgenrc
    ensureKeyValue "joypad1_b7" "START" /home/$user/.dgen/dgenrc
    ensureKeyValue "joypad2_b0" "A" /home/$user/.dgen/dgenrc
    ensureKeyValue "joypad2_b1" "B" /home/$user/.dgen/dgenrc
    ensureKeyValue "joypad2_b3" "C" /home/$user/.dgen/dgenrc
    ensureKeyValue "joypad2_b6" "MODE" /home/$user/.dgen/dgenrc
    ensureKeyValue "joypad2_b7" "START" /home/$user/.dgen/dgenrc    
}

# install DGEN (Megadrive/Genesis emulator)
function install_dgen()
{
    printMsg "Installing Megadrive/Genesis emulator"
    if [[ -d "$rootdir/emulators/dgen" ]]; then
        rm -rf "$rootdir/emulators/dgen"
    fi   
    wget http://downloads.sourceforge.net/project/dgen/dgen/1.31/dgen-sdl-1.31.tar.gz
    tar xvfz dgen-sdl-1.31.tar.gz -C "$rootdir/emulators/"
    pushd "$rootdir/emulators/dgen-sdl-1.31"
    mkdir "installdir" # only used for creating the binaries archive
    ./configure --disable-hqx --disable-opengl
    make
    make install DESTDIR=$rootdir/emulators/dgen-sdl-1.31/installdir
    make install
    if [[ ! -f "$rootdir/emulators/dgen-sdl-1.31/dgen" ]]; then
        __ERRMSGS="$__ERRMSGS Could not successfully compile DGEN emulator."
    fi  
    popd
    rm dgen-sdl-1.31.tar.gz
}


# install Game Boy Advance emulator core
function install_gba()
{
    printMsg "Installing Game Boy Advance core"
    gitPullOrClone "$rootdir/emulators/vba-next" git://github.com/libretro/vba-next.git
    make -f Makefile.libretro
    if [[ -z `find $rootdir/emulators/vba-next/ -name "*libretro*.so"` ]]; then
        __ERRMSGS="$__ERRMSGS Could not successfully compile Game Boy Advance core."
    fi      
    popd    
}

# install Sega Mega Drive/Mastersystem/Game Gear emulator OsmOse
function install_megadrive()
{
    printMsg "Installing Mega Drive/Mastersystem/Game Gear emulator OsmMose"

    wget https://dl.dropbox.com/s/z6l69wge8q1xq7r/osmose-0.8.1%2Brpi20121122.tar.bz2?dl=1 -O osmose.tar.bz2
    tar -jxvf osmose.tar.bz2 -C "$rootdir/emulators/"
    pushd "$rootdir/emulators/osmose-0.8.1+rpi20121122/"
    make clean
    make
    if [[ ! -f "$rootdir/emulators/osmose-0.8.1+rpi20121122/osmose" ]]; then
        __ERRMSGS="$__ERRMSGS Could not successfully compile OsmMose."
    fi      
    popd
    rm osmose.tar.bz2
}


# install Sega Mega Drive/Mastersystem/Game Gear libretro emulator core
function install_megadriveLibretro()
{
    printMsg "Installing Mega Drive/Mastersystem/Game Gear core (Libretro core)"
    gitPullOrClone "$rootdir/emulators/Genesis-Plus-GX" git://github.com/libretro/Genesis-Plus-GX.git
    make -f Makefile.libretro 
    if [[ ! -f "$rootdir/emulators/Genesis-Plus-GX/libretro.so" ]]; then
        __ERRMSGS="$__ERRMSGS Could not successfully compile Genesis core."
    fi      
    popd
}

# install SNES emulator core
function install_snes()
{
    printMsg "Installing SNES core"
    gitPullOrClone "$rootdir/emulators/pocketsnes-libretro" git://github.com/ToadKing/pocketsnes-libretro.git
    make
    if [[ -z `find $rootdir/emulators/pocketsnes-libretro/ -name "*libretro*.so"` ]]; then
        __ERRMSGS="$__ERRMSGS Could not successfully compile SNES core."
    fi      
    popd
}

# configure SNES emulator core settings
function configure_snes()
{
    printMsg "Configuring SNES core"

    # DISABLE rewind feature for SNES core due to the speed decrease
    ensureKeyValue "rewind_enable" "false" "$rootdir/configs/snes/retroarch.cfg"
}

######################################
# here starts the main loop ##########
######################################

checkNeededPackages

if [[ "$1" == "--help" ]]; then
    showHelp
    exit 0
fi

if [ $(id -u) -ne 0 ]; then
  printf "Script must be run as root. Try 'sudo ./retrodepi_setup' or ./retrodepi_setup --help for further information\n"
  exit 1
fi

# if called with sudo ./retrodepi_setup.sh, the installation directory is /home/CURRENTUSER/Retrode_Pi for the current user
# if called with sudo ./retrodepi_setup.sh USERNAME, the installation directory is /home/USERNAME/Retrode_Pi for user USERNAME
# if called with sudo ./retrodepi_setup.sh USERNAME ABSPATH, the installation directory is ABSPATH for user USERNAME
    
if [[ $# -lt 1 ]]; then
    user=$SUDO_USER
    if [ -z "$user" ]
    then
        user=$(whoami)
    fi
    rootdir=/home/$user/Retrode_Pi
elif [[ $# -lt 2 ]]; then
    user=$1
    rootdir=/home/$user/Retrode_Pi
elif [[ $# -lt 3 ]]; then
    user=$1
    rootdir=$2
fi

esscrapimgw=275 # width in pixel for EmulationStation games scraper

home=$(eval echo ~$user)

if [[ ! -d $rootdir ]]; then
    mkdir -p "$rootdir"
    if [[ ! -d $rootdir ]]; then
      echo "Couldn't make directory $rootdir"
      exit 1
    fi
fi

availFreeDiskSpace 600000

while true; do
    cmd=(dialog --backtitle "Retrode.org - Retrode_Pi Setup. Installation folder: $rootdir for user $user" --menu "Choose installation either based on binaries or on sources." 22 76 16)
    # options=(1 "Binaries-based installation (faster, (probably) not the newest)"
    options=(1 "Setup Retrode Pi (AiO) *Note This will take a while*"
             2 "Update Retrode_Pi Setup script"
             3 "Perform reboot" )
    choices=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)    
    if [ "$choices" != "" ]; then
        case $choices in
            1) main_setup ;;
            2) main_updatescript ;;
            3) main_reboot ;;
        esac
    else
        break
    fi
done

if [[ $__doReboot -eq 1 ]]; then
    dialog --title "The firmware has been updated and a reboot is needed." --clear \
        --yesno "Would you like to reboot now?\
        " 22 76

        case $? in
          0)
            main_reboot
            ;;
          *)        
            ;;
        esac
fi
clear