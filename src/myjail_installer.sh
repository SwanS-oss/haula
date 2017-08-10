#!/bin/bash

###############################################################################
# Linux Jail Installer v2.5.0
#
# Written by Juan Jose Castro Sotelo
# Licensed under terms of GPLv3
#
# Changelog:
# - v2.5.0:
#   Support for online debootstrap rootfs.
#   gojail script autodetects the user with same uid inside jail.
#   Improved gojail script suggestion about user login.
#   Source rootfs dir is kept as jail rootfs when type raw and destdir not set.
# - v2.2.1:
#   Converts destdir relative path to absolute (needed by schroot config)
# - v2.2.0:
#   Support for raw (directory) and tar rootfs types
#   Improved verbosity
# - v2.1.1:
#   Minor code modifications
# - v2.1.0:
#   Ensures that the jail folder, go script and group begin with "jail" word.
#   Check that group name for the jail will not be longer than 16 characters.
# - v2.0.0:
#   Made generic. Allow input arguments to install any rootfs in a tar.gz
# - v1.2.2: 
#   Fixed username reading in Ubuntu 16.04 terminal
# - v1.2.1: 
#   Fixed OSFLAVOUR for Linux 64 bits. Added xhost + to gojail script
# - v1.2.0: 
#   home and media folders in host mounted as /host/home and /host/media
# - v1.1.0: 
#   Included gojail script creation
# - v1.0.0:
#   Initial version
###############################################################################


###############################################################################
# Config constants (only set if installer personalized for specific jail)

JAILRFS=""  # Path of the directory, tarball or repo containing the rootfs for the jail 
JAILNAME=""  # Name for the jail once installed. Do not use blanks or symbols
JAILDESC=""  # Description for the jail once installed
OSFLAVOUR="linux"  # OS type inside jail: "linux" for 64 bits or "linux32" for 32 
JAILRFSTYPE=""  # Specify the rootfs type (raw, tar or targz). Empty for automatic

DESTDIR_DFL=$HOME  # Path where the rootfs and tools of the jail will be installed

OPTUNINSTALL=false
OPTYES=false

declare -A DEBOOTSTRAP_REPOURL
DEBOOTSTRAP_REPOURL=( 
["hamm"]="http://deb.debian.org/debian/" 
["slink"]="http://deb.debian.org/debian/" 
["potato"]="http://deb.debian.org/debian/" 
["woody"]="http://deb.debian.org/debian/" 
["sarge"]="http://deb.debian.org/debian/" 
["etch"]="http://deb.debian.org/debian/" 
["lenny"]="http://deb.debian.org/debian/" 
["squeeze"]="http://deb.debian.org/debian/" 
["wheezy"]="http://deb.debian.org/debian/" 
["jessie"]="http://deb.debian.org/debian/" 
["stretch"]="http://deb.debian.org/debian/" 

["lucid"]="http://archive.ubuntu.com/ubuntu/" 
["maverick"]="http://archive.ubuntu.com/ubuntu/" 
["natty"]="http://archive.ubuntu.com/ubuntu/" 
["oneiric"]="http://archive.ubuntu.com/ubuntu/" 
["precise"]="http://archive.ubuntu.com/ubuntu/" 
["quantal"]="http://archive.ubuntu.com/ubuntu/" 
["raring"]="http://archive.ubuntu.com/ubuntu/" 
["saucy"]="http://archive.ubuntu.com/ubuntu/" 
["trusty"]="http://archive.ubuntu.com/ubuntu/" 
["utopic"]="http://archive.ubuntu.com/ubuntu/" 
["vivid"]="http://archive.ubuntu.com/ubuntu/" 
["wily"]="http://archive.ubuntu.com/ubuntu/" 
["xenial"]="http://archive.ubuntu.com/ubuntu/" 
["yakkety"]="http://archive.ubuntu.com/ubuntu/" 
["zesty"]="http://archive.ubuntu.com/ubuntu/" 
["artful"]="http://archive.ubuntu.com/ubuntu/" 
)

GROUPNAMEMAXLEN=32


VERSION="2.5.0-stable"




###############################################################################
# Functions

show_usage ()
{
  echo "\
Usage: $0 <options>"
}


show_help ()
{
  echo "\
Install a Linux rootfs inside a schroot jail.
[options]
  -r, --rootfs DIR | FILE | DEBOOTSTRAP
    Rootfs of the jail. 
    Can be a directory with the files (raw), a tarball file (.tar or .tar.gz)
    or an online debootstrap repository.
    To download the debootstrap rootfs, use the following syntax:
    debootstrap:<version>[:<arch>:<variant>]
  -t, --rfstype TYPE
    Specify the rootfs type (raw, tar, targz or debootstrap). 
    If not specified, it is detected automatically from the value of --rootfs
  -n, --name NAME
    Name for the jail once installed. Do not use blank spaces or symbols.
  -d, --descr TEXT
    Description for the jail once installed.
  -o, --osflavour OS
    OS type inside jail: 'linux' for 64 bits, 'linux32' for 32 bits.
    Default: 'linux'
  -e, --destdir DIR
    Directory where the rootfs and tools of the jail will be installed.
    If not specified, the 'rootfs' parent folder will be used when rootfs type
    is raw (directory). When rootfs type is tar, targz or debootstrap, it 
    defaults to: $DESTDIR_DFL
  -u, --uninstall
    Uninstall a previously installed jail. Specify the jail name with --name.
  -h, --help
    Show this information
  -v, --version
    Show the version number of this tool"
}


do_install ()
{
  # Check resulting group number length
  if [ ${#JAILJAILNAME} -gt $GROUPNAMEMAXLEN ]; then
    echo "Error: $JAILJAILNAME cannot be longer than $GROUPNAMEMAXLEN characters"
    exit 1
  fi
  
  # Setting rootfs type
  if [ "$JAILRFSTYPE" != "" ]; then
    if [[ ! "$JAILRFSTYPE" =~ ^(raw|tar|targz)$ ]]; then
      echoerr "\
The rootfs type specified is invalid (${JAILRFSTYPE}). Use raw, tar or targz"
    fi
  else 
    # Autodetect rootfs type
    if [ -d "$JAILRFS" ]; then
      JAILRFSTYPE="raw"
    elif [[ "$JAILRFS" =~ ^.*\.tar$ ]]; then
      JAILRFSTYPE="tar"
    elif [[ "$JAILRFS" =~ ^.*\.tar\.gz$ ]]; then
      JAILRFSTYPE="targz"
    elif [[ "$JAILRFS" =~ ^debootstrap:.*$ ]]; then
      JAILRFSTYPE="debootstrap"
    else
      echoerr "Unknown rootfs format. Use RAW directory, .tar or .tar.gz"
      exit 1
    fi
  fi
  
  # Extra processing rootfs argument
  if [ "$JAILRFSTYPE" == "debootstrap" ]; then
    debootstrap_ver="`echo "$JAILRFS" | awk 'BEGIN { FS = ":" } ; {print $2}'`"
    debootstrap_arc="`echo "$JAILRFS" | awk 'BEGIN { FS = ":" } ; {print $3}'`"
    debootstrap_var="`echo "$JAILRFS" | awk 'BEGIN { FS = ":" } ; {print $4}'`"
    
    if [ "$debootstrap_ver" == "" ]; then
      echoerr "\
A OS version for debootstrap is not specified. 
Use this syntax for the --rootfs option:

    --rootfs debootstrap:<version>[:<arch>:<variant]

Example: 

    --rootfs debootstrap:trusty:i386:minbase"
      exit 1
    fi
    
    if [ "${DEBOOTSTRAP_REPOURL["$debootstrap_ver"]}" == "" ]; then
      echoerr "Rootfs version for debootstrap ($debootstrap_ver) not supported"
      exit 1
    fi
  fi
  
  if [ "$DESTDIR" == "" ]; then
    if [ "$JAILRFSTYPE" == "raw" ]; then
      DESTDIR="`readlink -f "$JAILRFS/.."`"
      JAILRFS_TARGETDIR="`basename "$JAILRFS"`"
    else
      DESTDIR="$DESTDIR_DFL"
      JAILRFS_TARGETDIR="$JAILJAILNAME"
    fi
  else
    JAILRFS_TARGETDIR="$JAILJAILNAME"
  fi
  
  # Convert destdir path to absolute if needed (schroot config requires it)
  if [[ ! "$DESTDIR" =~ ^/.* ]]; then  # note: ~ is expanded by shell before running 
    DESTDIR="$(pwd)/${DESTDIR}"
  fi

  if [ -d "$DESTDIR" ]; then
    DESTDIR="`readlink -f "${DESTDIR}"`"
  fi
  
  echo "
This script will install the jail: ${JAILNAME}
from:          ${JAILRFS}  (type: ${JAILRFSTYPE})
for the user:  ${user}
in:            ${DESTDIR}

Inside that path you will find:
* A script to enter to the jail:       ${GOJAILSCRIPTNAME}
* A subfolder with the jail OS files:  ${JAILRFS_TARGETDIR}

If you want to change the installation base path, 
execute the script with the option --destdir DIR
"

  [ "$OPTYES" != true ] && read -p "\
Press [Enter] to continue or [Ctrl+C] to cancel..."


  # Get schroot from aptitude
  if ! which schroot > /dev/null; then 
    echo "Installing schroot..."
    apt-get install schroot
  fi

  # Get debootstrap from aptitude
  if [ -x ./debootstrap ] && ! which debootstrap > /dev/null; then 
    echo "Installing debootstrap..."
    apt-get install debootstrap
  fi


  echo "Creating installation path if needed (${DESTDIR}/${JAILRFS_TARGETDIR})..."
  # Create DESTDIR dir
  if [ ! -d "$DESTDIR" ]; then
    mkdir -p "$DESTDIR"
    chown -R $user:$user "$DESTDIR"
  fi
  if [ ! -d "${DESTDIR}/${JAILRFS_TARGETDIR}" ]; then
    mkdir -p "${DESTDIR}/${JAILRFS_TARGETDIR}"
    chown -R $user:$user "${DESTDIR}/${JAILRFS_TARGETDIR}"
  fi


  # Obtain rootfs
  case $JAILRFSTYPE in
    targz )
      # Extract the jail rootfs to the target path
      echo "Extracting jail rootfs files..."
      tar -xzvf "${JAILRFS}" -C "${DESTDIR}/${JAILRFS_TARGETDIR}"
      ;;
    tar )
      # Extract the jail rootfs to the target path
      echo "Extracting jail rootfs files..."
      tar -xvf "${JAILRFS}" -C "${DESTDIR}/${JAILRFS_TARGETDIR}"
      ;;
    raw )
      if [ "${DESTDIR}/${JAILRFS_TARGETDIR}" != "$JAILRFS" ]; then
        if [ ! "${JAILRFS}" -ef "${DESTDIR}/${JAILRFS_TARGETDIR}" ]; then
          # Copy the jail rootfs folder to the target path
          echo "Copying jail rootfs files..."
          cp -a "${JAILRFS}/." "${DESTDIR}/${JAILRFS_TARGETDIR}"
        fi
      fi
      ;;
    debootstrap )
      # Download the jail rootfs to the target path
      echo "Downloading jail rootfs from debootstrap..."
      # rootfs has the form: debootstrap:trusty:i386:minbase
      cmd="debootstrap"
      [ "$debootstrap_arc" != "" ] && cmd="$cmd --arch $debootstrap_arc"
      [ "$debootstrap_var" != "" ] && cmd="$cmd --variant $debootstrap_var"
      cmd="$cmd $debootstrap_ver \"${DESTDIR}/${JAILRFS_TARGETDIR}\" \"${DEBOOTSTRAP_REPOURL["$debootstrap_ver"]}\""
      echo $cmd
      eval $cmd
      #debootstrap --variant=minbase --arch=i386 trusty DEPCM2/ "$DEBOOTSTRAP_REPOURL"
      ;;
    * )
      echoerr "Internal failure with JAILRFSTYPE"
      ;;
  esac
    
  # Grant access to the jail
  echo "Granting permissions for the user '$user'..."
  echo "  Creating system group for jail users (${JAILJAILNAME})..."
  groupadd "${JAILJAILNAME}"

  echo "  Adding user '$user' to the jail group..."
  usermod -a -G "${JAILJAILNAME}" "$user"

  # Create jail definition file with proper data
  echo "Creating jail definition... (/etc/schroot/chroot.d/${JAILNAME}.conf)"
  touch "/etc/schroot/chroot.d/${JAILNAME}.conf"
  cat <<EOF > "/etc/schroot/chroot.d/${JAILNAME}.conf"
[${JAILNAME}]
aliases=${JAILNAME^^},${JAILNAME,,}
description=${JAILDESC}
personality=${OSFLAVOUR}
type=directory
directory=${DESTDIR}/${JAILRFS_TARGETDIR}
groups=${JAILJAILNAME}
root-groups=${JAILJAILNAME}
script-config=${JAILNAME}/config
profile=${JAILNAME}
EOF
  # Note that we created the jail with aliases in lower and upper case

  if [ ! -d "/etc/schroot/$JAILNAME" ]; then
    mkdir -p "/etc/schroot/$JAILNAME"
  fi

  # Create the jail configuration files
  echo "Creating jail configuration... (/etc/schroot/${JAILNAME}/config fstab copyfiles nssdatabases)"
  touch "/etc/schroot/${JAILNAME}/config"
  cat <<EOF > "/etc/schroot/${JAILNAME}/config"
FSTAB=/etc/schroot/${JAILNAME}/fstab
COPYFILES=/etc/schroot/${JAILNAME}/copyfiles
NSSDATABASES=/etc/schroot/${JAILNAME}/nssdatabases
EOF

  touch "/etc/schroot/${JAILNAME}/fstab"
  cat <<EOF > "/etc/schroot/${JAILNAME}/fstab"
# fstab: static file system information for chroots.
# Note that the mount point will be prefixed by the chroot path
# (CHROOT_PATH)
#
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
/proc           /proc           none    rw,bind         0       0
/sys            /sys            none    rw,bind         0       0
/dev            /dev            none    rw,bind         0       0
/dev/pts        /dev/pts        none    rw,bind         0       0
/home           /host/home      none    rw,bind         0       0
/media          /host/media     none    rw,bind         0       0
/tmp            /tmp            none    rw,bind         0       0

# It may be desirable to have access to /run, especially if you wish
# to run additional services in the chroot.  However, note that this
# may potentially cause undesirable behaviour on upgrades, such as
# killing services on the host.
#/run           /run            none    rw,bind         0       0
#/run/lock      /run/lock       none    rw,bind         0       0
#/dev/shm       /dev/shm        none    rw,bind         0       0
#/run/shm       /run/shm        none    rw,bind         0       0
EOF

  touch "/etc/schroot/${JAILNAME}/copyfiles"
  cat <<EOF > "/etc/schroot/${JAILNAME}/copyfiles"
# Files to copy into the chroot from the host system.
#
# <source and destination>
/etc/resolv.conf
EOF

  touch "/etc/schroot/${JAILNAME}/nssdatabases"
  cat <<EOF > "/etc/schroot/${JAILNAME}/nssdatabases"
# System databases to copy into the chroot from the host system.
#
# <database name>

#passwd
#shadow
#group
#gshadow
#services
#protocols
#networks
#hosts
EOF

  #Create script to easily enter to the jail
  echo "Creating gojail script... (${DESTDIR}/${GOJAILSCRIPTNAME})"
  cat <<EOF > "${DESTDIR}/${GOJAILSCRIPTNAME}"
#!/bin/bash
JAILNAME=${JAILNAME}
JAILRFSDIR=${JAILRFS_TARGETDIR}
EOF
  cat <<'EOF' >> ${DESTDIR}/${GOJAILSCRIPTNAME}
userUid="`id -u`"
jailUserNameRecommended="`awk -v userUid="${userUid}" -F: \
  '($3 == userUid) {print $1}' ${JAILRFSDIR}/etc/passwd`"
userNumRecommended="$userUid" #"$(($userUid - 1000))"
echo "\
Entering to jail '${JAILNAME}' ($JAILRFSDIR)...

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!! Do not forget to enter to a regular user account.
!! Working as root is not recommended!!
!!"
if [ "$jailUserNameRecommended" != "" ]; then echo "\
!! The recommended user account inside the jail is (has the same uid): 
!! $jailUserNameRecommended
!!
!! Run: 
!!
!!     # su ${jailUserNameRecommended}
!!"
else echo "\
!! It is recommended to use inside the jail a regular user with the same uid 
!! than the yours outside (${userUid}), to avoid permissions issues when sharing
!! files between the jail and the host.
!!
!! To create the user and login as it, run: 
!!
!!     # useradd -u ${userUid} user${userNumRecommended}
!!     # su user${userNumRecommended}
!!"
fi
echo "\
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
"
xhost +  # Allow X clients to connect to host X server
schroot -c ${JAILNAME} --directory=/ --user=root #2>"./${JAILNAME}_err.log"
EOF

  chown $user:$user ${DESTDIR}/${GOJAILSCRIPTNAME}
  chmod u+x ${DESTDIR}/${GOJAILSCRIPTNAME}

  #Grant access to host and local display
  echo "Configuring host to allow access to graphic server..."
  xhost +

  echo "

DONE!


NEXT STEPS:

Start a new shell session before accessing the jail:
$ su $user

To enter the jail run the script installed:
$ ${DESTDIR}/${GOJAILSCRIPTNAME}

"

}


echoerr() {
  echo "error: $@" >&2
}




###############################################################################
# Main

main ()
{
  ##################################################
  # Input arguments

  SHORT_OPTS=":r:t:n:d:o:e:uyhv"
  LONG_OPTS="rootfs:,rfstype:,name:,descr:,osflavour:,destdir:,uninstall,yes,help,version,onlyhelp"
  args=`getopt -o $SHORT_OPTS --long $LONG_OPTS -- "$@"`
  if [ $? -ne 0 ]; then
    show_option_error
    exit 1
  fi
  eval set -- "$args"

  while true ; do
    case $1 in
      -r | --rootfs )         shift
                              JAILRFS="$1"
                              ;;
      -t | --rfstype )        shift
                              JAILRFSTYPE="$1"
                              ;;
      -n | --name )           shift
                              JAILNAME="$1"
                              ;;
      -d | --descr )          shift
                              JAILDESC="$1"
                              ;;
      -o | --osflavour )      shift
                              OSFLAVOUR="$1"
                              ;;
      -e | --destdir )        shift
                              DESTDIR="$1"
                              ;;
      -u | --uninstall )      OPTUNINSTALL=true
                              echo "Feature not implemented yet"; exit 1
                              ;;
      -y | --yes )            OPTYES=true
                              ;;
      -h | --help )           show_usage; show_help; exit 0
                              ;;
      -v | --version )        echo "Version $VERSION"; exit 0
                              ;;
      --onlyhelp )            show_help; exit 0
                              ;;
      --)               shift ; break
                        ;;
      *)                echo "Internal error ($1)!" ; exit 1
    esac
    shift
  done


  # Check for super-user privileges or exit (stdout > stderr)
  if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root" 1>&2
    exit 1
  fi

  JAILJAILNAME="jail${JAILNAME#jail}"  # Ensure jail name begins with "jail"
  GOJAILSCRIPTNAME="go${JAILJAILNAME}.sh"
  user=`logname 2>/dev/null || echo ${SUDO_USER:-${USER}}`
  
  do_install
}


main "$@"


