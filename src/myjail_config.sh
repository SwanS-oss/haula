#!/bin/bash

###############################################################################
# Linux Jail Rootfs Configurer v0.1-alpha
#
# Written by Juan Jose Castro Sotelo
# Licensed under terms of GPLv3
#
# Changelog:
# - v0.1.0:
#   Initial version
###############################################################################


HOST_DISPLAY_DFL=":0"
PKG_TO_INSTALL_DFL="ubuntu-minimal software-properties-common nano openssl wget make"
REPO_TO_ENABLE_DFL="universe restricted multiverse"
JAIL_HOSTNAME_DFL=""
OPTYES_DFL=false


VERSION="0.1-alpha"




###############################################################################
# Functions

show_usage()
{
  echo "\
Usage: ${0##*/} <options>"
}


show_help()
{
  echo "\
Set a basic configuration to a pre-existing Linux rootfs inside a schroot jail.
[options]
  -n, --name NAME
    Name (alias) of the schroot jail.
    Do not set if this tool is executed inside the jail.
    If not set and outside a jail, it will be prompted to configure the host.
  -i, --display ID
    Specify the number of the display in the host PC to which connect the
    display of the jail.
    Automatically detected if not set and executed from outside the jail.
    Set it to empty (--hostdisplay "") to skip display configuration.
    Default: ${HOST_DISPLAY_DFL}
  -o, --hostname NAME
    Hostname to set up in the jail.
    Set it to empty (--hostname "") to skip hostname configuration.
    Default: ${JAIL_HOSTNAME_DFL:-"the name of the jail"}
  -k, --pkgs PKGS
    List of packages that should be installed inside the jail. Space separated.
    Set it to empty (--pkgs "") to skip packages installation.
    Default: ${PKG_TO_INSTALL_DFL}
  -r, --repo2en REPOS
    List of the distribution's repositories to enable. Space separated.
    Note: 'main' repository, or equivalent, is always considered to be enabled
    Set it to empty (--repo2enable "") to skip this configuration.
    Default: ${REPO_TO_ENABLE_DFL}
  -y, --yes
    Automatize the procedure answering yes to all.
  -h, --help
    Show this information"
}


show_option_error()
{
  echo "\
Bad action, option or argument. Take a look at:

    $ ${0##*/} --help" >&2
}


exitIfNotRoot() {
  if [ $EUID -ne 0 ]; then
     echo "\
This script must be run as root or with sudo.

Example: 

    $ sudo ${0##*/}" 1>&2
     exit 1
  fi
}


isInsideJail() {
  # REQUIRE ROOT PROVILEGES!!!
  # Check that the script is running inside the jail
  if [ "$(stat -c %d:%i /)" != "$(stat -c %d:%i /proc/1/root/.)" ]; then
    return 0
  else
    return 1
  fi
}


ver ()
{
  printf "%03d%03d%03d%03d" $(echo "$1" | tr '.' ' ')
}


isYes() {
  echo "$1" | grep -i "^y" &> /dev/null
  # Note: [ "$1" != "" ] && echo "$1" | $FUNCNAME || \ does not work for empty
  # input. Tried cat, dd and read and "if then else". Nothing...
}


askYes() 
{
  # ARGS IN:
  local textToShow="$1"
  local defaultOption="${2:-"y"}"  # "y" or "n"
  
  local output="$textToShow"
  local option="invalid"
  
  while [[ ! "$option" =~ (^$|^[NnYy].*$) ]]; do
    if [[ "$defaultOption" =~ ^[Nn].*$ ]]; then
      echo -n "${textToShow} [yes/No]: "
    else
      echo -n "${textToShow} [Yes/no]: "
    fi
    
    read option
  done
  
  if isYes "${option}" \
  || [[ ! "$defaultOption" =~ ^[Nn].*$ && "$option" == "" ]]; then 
    return 0
  else
    return 1 
  fi

}




jail_getRootfsPath()
{
  local jailName="$1"
  schroot --info -c "$jailName" 2>/dev/null | grep "^ *Directory" \
  | awk '{print $2}'
}


jail_execCmd()
{
  local jailName="$1"
  local cmd="$2"
  
  schroot -c "$jailName" -d / -u root -- $2
}




main()
{
  # Grab options

  JAILNAME=""  # Name for the schroot jail to configure
  HOST_DISPLAY="detectit"
  JAIL_HOSTNAME="$JAIL_HOSTNAME_DFL"
  PKG_TO_INSTALL="$PKG_TO_INSTALL_DFL"
  REPO_TO_ENABLE="$REPO_TO_ENABLE_DFL"

  OPTYES="$OPTYES_DFL"

  
  SHORT_OPTS=":i:s:k:n:p:yhv"
  LONG_OPTS="display:,hostname:,pkgs:,name:,repo2en:,yes,help,version,onlyhelp"
  args=`getopt -o $SHORT_OPTS --long $LONG_OPTS -- "$@"`
  if [ $? -ne 0 ]; then
    show_option_error
    exit 1
  fi
  eval set -- "$args"


  while true ; do
    case "$1" in
      --display | -i )  shift
                        HOST_DISPLAY="$1"
                        ;;
      --hostname | -s ) 
                        shift
                        JAIL_HOSTNAME="$1"
                        ;;
      --pkgs | -k )     shift
                        PKG_TO_INSTALL="$1"
                        ;;
      --name | -n )     shift
                        JAILNAME="$1"
                        [ "$JAIL_HOSTNAME_DFL" == "" ] \
                        && JAIL_HOSTNAME_DFL=$JAILNAME
                        ;;
      --repo2en | -p )  shift
                        REPO_TO_ENABLE="$1"
                        ;;
      --yes | -y )      OPTYES=true
                        ;;
      --help | -h )     show_usage; show_help; exit 0
                        ;;
      --version | -v )  echo "Version $VERSION"; exit 0
                        ;;
      --onlyhelp )      show_help; exit 0
                        ;;
      --)               shift ; break
                        ;;
      *)                echo "Internal error ($1)!" ; exit 1
    esac
    shift
  done
  
  [ "$JAIL_HOSTNAME" == "" ] && JAIL_HOSTNAME=$JAIL_HOSTNAME_DFL


  exitIfNotRoot
  
  # Check that the script is running inside the jail
  if ! isInsideJail; then
    if [ "$JAILNAME" == "" ]; then
      echo "You are not inside a jail. Configuration will be done on host system!"
      if ! askYes "Are you sure you want to continue?" "n"; then
        exit 1
      fi
    fi
    
    if [ "$HOST_DISPLAY" == "detectit" ]; then  # Not set by user argument
      if [ "$DISPLAY" != "" ]; then
        HOST_DISPLAY="$DISPLAY"  # Use host display number
      else
        HOST_DISPLAY="$HOST_DISPLAY_DFL"
      fi
    fi
  else
    if [ "$HOST_DISPLAY" == "detectit" ]; then  # Not set by user argument
      HOST_DISPLAY="$HOST_DISPLAY_DFL"
    fi
  fi


  if [ "$JAILNAME" != "" ]; then
    jailRootfsPath=`jail_getRootfsPath "$JAILNAME"`
    [ ! -d "$jailRootfsPath" ] && exit 1
    cp -f "$0" "$jailRootfsPath"
    chmod a+x "$jailRootfsPath/${0##*/}"
    sed -i "\
      s%^HOST_DISPLAY_DFL=.*%HOST_DISPLAY_DFL=\"$HOST_DISPLAY\"  #%;\
      s%^PKG_TO_INSTALL_DFL=.*%PKG_TO_INSTALL_DFL=\"$PKG_TO_INSTALL\"  #%;\
      s%^REPO_TO_ENABLE_DFL=.*%REPO_TO_ENABLE_DFL=\"$REPO_TO_ENABLE\"  #%;\
      s%^JAIL_HOSTNAME_DFL=.*%JAIL_HOSTNAME_DFL=\"$JAIL_HOSTNAME\"  #%;\
      s%^OPTYES_DFL=.*%OPTYES_DFL=\"$OPTYES\"  #%" "$jailRootfsPath/${0##*/}"
    jail_execCmd "$JAILNAME" "/${0##*/}" && exit 0 || exit 1
  fi


  #######################################################
  ################## UBUNTU #############################
  #######################################################


  # Obtain info about the chrooted system
  . /etc/lsb-release || exit 1 # Obtain DISTRIB_ID and DISTRIB_RELEASE variables
  distrib_major=`echo ${DISTRIB_RELEASE} | awk 'BEGIN { FS = "." } ; {print $1}'`




  # Set unattended packages installation if --yes option set
  [ "$OPTYES" == true ] && export DEBIAN_FRONTEND=noninteractive 
  
  ##### Adaptation of the jail to particularities of the host system

  # Workaround issue with upstart inside chroot
  echo "Checking issue with upstart inside chroot..."
  if [ -e /sbin/initctl ] && ! /sbin/initctl list &>/dev/null; then
    if $OPTYES || askYes "Override /sbin/initctl to fix issue with upstart?" "y"; then
      # Since initctl does not work, we fake it to return success always to not
      # intefere in other utilities, as apt-get. Do not use services now... :(
      dpkg-divert --local --rename --add /sbin/initctl \
      && ln -s /bin/true /sbin/initctl || exit 1
    fi
  fi
  echo




  ##### Installation of applications of general interest in the jail

  if [ $(ver $distrib_major) -le $(ver 12.04) ]; then
    PKG_TO_INSTALL="`echo "$PKG_TO_INSTALL" \
    | sed 's/software-properties-common/python-software-properties/'`"
  fi

  echo "The following packages are going to be installed inside the jail:"
  echo "$PKG_TO_INSTALL"

  if $OPTYES || askYes "Install applications of general interest?" "y"; then
    echo "Installing applications of general interest in the jail..."
    apt-get update || exit 1
    apt-get install -y $PKG_TO_INSTALL || exit 1
    echo
  fi




  ##### General configuration of the jail

  # Enable extra common repositories
  if [ "$REPO_TO_ENABLE" != "" ] \
    && ( $OPTYES \
    || askYes "Enable extra common repositories ($REPO_TO_ENABLE)?" "y" ); then
    echo "Enabling extra common repositories ($REPO_TO_ENABLE)..."
    add-apt-repository "deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc) main $REPO_TO_ENABLE" || exit 1
    apt-get update
    echo
  fi

  # Configure users
  if $OPTYES || askYes "Set root password to 'root'?" "y"; then
    echo "Setting root password to 'root'..."
    pwconv && echo root:root | chpasswd
    echo
  fi

  if $OPTYES || askYes "Create users from user0 to user9 to match host uid from 1000 to 1009?" "y"; then
    echo "Creating users from user0 to user9 to match host uid from 1000 to 1009..."
    for number in `seq 0 9`; do useradd user${number} --shell /bin/bash --create-home --skel /etc/skel --password $(openssl passwd -1 user); done
    echo "*** PASSWORD is 'user' ***"
    if $OPTYES || askYes "Enable sudo for these users?" "y"; then
      echo "Adding users from user0 to user9 to sudoers..."
      for number in `seq 0 9`; do usermod -a -G sudo user${number}; done
    fi
    echo
  fi

  # Configure hostname
  if [ "$JAIL_HOSTNAME" != "" ] \
    && ( $OPTYES \
    || askYes "Configure hostname of the jail to '${JAIL_HOSTNAME}'?" "y" ); then
    echo "Configuring the hostname of the jail to '${JAIL_HOSTNAME}'..."
    echo depcm2 > /etc/hostname && echo 127.0.0.1 ${JAIL_HOSTNAME} >> /etc/hosts
    echo
  fi

  # Enable display usage from the jail
  if [ "$HOST_DISPLAY" != "" ] \
    && ( $OPTYES \
    || askYes "Enable display usage from the jail (display ${HOST_DISPLAY})?" "y" ); then
    echo "Enabling display usage from the jail (display ${HOST_DISPLAY})..."
    echo export DISPLAY=${HOST_DISPLAY}.0 >> /etc/bash.bashrc
    echo
  fi

  # Enable commands shortcuts
  if $OPTYES || askYes "Enable commands shortcuts (ll, mygrep, cd.., ...)?" "y"; then
    echo "Enabling commands shortcuts (ll, mygrep, cd.., ...)..."
    cat <<'EOF' >> /etc/bash.bashrc
## Improve file listing ##
alias ls='ls --color=auto'
alias ll='ls -halp'

## Quick ways to get out of current directory ##
alias cd..='cd ..'
alias ..='cd ..'
alias ...='cd ../../../'
alias ....='cd ../../../../'
alias .....='cd ../../../../'

## Improve the grep command output for ease of use ##
alias grep='grep --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'

## Search files containing a string ##
alias mygrep='grep -RIins'
alias myGrep='grep -RIns' # Do it case-sensitive

## Remove all backup files generated by gedit at once ##
alias myrm~="echo \"Deleting all ~ files in this directory and subdirectories...\"; \
find ./ -name '*~' -exec rm '{}' \; -print -or -name \".*~\" -exec rm {} \; -print \
&& echo \"All deleted!\" || echo \"Failure!\""
EOF
  fi
}

main "$@"



