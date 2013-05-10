#!/bin/bash

__ERRMSGS=""
__INFMSGS=""
__doReboot=0

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


function printMsg()
{
    echo -e "\n= = = = = = = = = = = = = = = = = = = = =\n$1\n= = = = = = = = = = = = = = = = = = = = =\n"
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
        mkdir -p "$rootdir/configs/gb/"
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
	apt-get install alsa-utils
	modprobe snd_bcm2835
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

function checkNeededPackages()
{
	sudo apt-get install -y git
    sudo apt-get install -y dialog
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

    echo -e "\nEmulators and cores:" >> "$rootdir/debug.log"
    checkFileExistence "`find $rootdir/emulators/stella-libretro/ -name "*libretro*.so"`"
    checkFileExistence "`find $rootdir/emulators/gambatte-libretro/ -name "*libretro*.so"`"
    checkFileExistence "`find $rootdir/emulators/pocketsnes-libretro/ -name "*libretro*.so"`"

    echo -e "\nSummary of ROMS directory:" >> "$rootdir/debug.log"
    du -ch --max-depth=1 "$rootdir/roms/" >> "$rootdir/debug.log"


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
	#Make Sure User has Rights to Folder
	chgrp -R $user $rootdir
    chown -R $user $rootdir

	#Startup Cleaner
	starup_setup
	
	main_binaries
	
	#Make Sure User has Rights to Folder (Double Check After Binaries Installation)
	chgrp -R $user $rootdir
    chown -R $user $rootdir

	#Retroarch
	install_retroarch
	configureRetroArch
	
	#ATARI 2600
	install_atari2600

	#GBA
	install_gba

	#MEGA DRIVE/GENESIS
	install_megadrive

	#GAMEGEAR
	install_megadriveLibretro

	#GAMEBOY
	install_gbc

	#SNES
	install_snes
	configure_snes
	
	#GENESIS
	install_dgen
	configureDGEN
	
	#Configure Last Minute Items
	configureSoundsettings
	
	#remove any un-needed objects
	sudo apt-get clean all
	
	chgrp -R $user $rootdir
    chown -R $user $rootdir

	finalize_setup
	
	#set HDMI Mod
	ensureKeyValue "hdmi_drive" "2" "/boot/config.txt"
		
	#Create Load Script
	
	#Change .Profile to Load Script
	
	#Set to Auto Boot to Pi User
	
    setAvoidSafeMode

    createDebugLog
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

function starup_setup(){
	sudo apt-get update
	sudo apt-get -y dist-upgrade
	sudo apt-get -y install git-core binutils
	sudo apt-get install -y dialog
	sudo apt-get install gcc build-essential libsdl1.2-dev
	sudo apt-get clean all
}

function finalize_setup(){

	#apt-get purge -y ca-certificates libraspberrypi-doc xkb-data fonts-freefont-ttf locales manpages midori lxde penguins puzzle lxde-icon-theme lxde-common omxplayer xdg-utils wireless-tools wpasupplicant penguinspuzzle samba-common firmware-atheros firmware-brcm80211 firmware-ralink firmware-realtek gcc-4.4-base:armhf gcc-4.5-base:armhf gcc-4.6-base:armhf ca-certificates libraspberrypi-doc xkb-data fonts-freefont-ttf manpages
	#apt-get autoremove
	#apt-get clean all
	swapoff -a
	dpkg --configure -a
	apt-get purge -y dphys-swapfile
	rm /var/swap
	rm -R /etc/wpa_supplicant
	rm -R /etc/console-setup
	rm -R /usr/share/icons
	rm -R Desktop
	rm -fr /usr/share/doc/*
	rm -rf python_games
	rm ocr_pi.png
	cd /var/log/ 
	rm `find . -type f`
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


home=$(eval echo ~$user)

if [[ ! -d $rootdir ]]; then
    mkdir -p "$rootdir"
    if [[ ! -d $rootdir ]]; then
      echo "Couldn't make directory $rootdir"
      exit 1
    fi
fi

while true; do
    cmd=(dialog --backtitle "Retrode.org - Retrode_Pi Setup. Installation folder: $rootdir for user $user" --menu "Retrode Pi Setup Menu." 22 76 16)
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
