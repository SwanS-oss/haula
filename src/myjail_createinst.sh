#!/bin/bash

###############################################################################
# Linux Jail Creator v1.0.0
#
# Written by Juan Jose Castro Sotelo
# Licensed under terms of GPLv3
#
# Changelog:
# - v1.0.0:
#   Initial version
###############################################################################


###############################################################################
ROOTFS=""  # Path of the folder or tarball containing the rootfs for the jail
JAILNAME=""  # Name for the jail once installed. Do not use blanks or symbols
ENVDESCRIPTION=""  # Description for the jail once installed
OSFLAVOUR=""  # OS type inside jail: "linux" for 64 bits or "linux32" for 32 

DESTDIR=$HOME  # Path where the rootfs and tools of the jail will be installed


###############################################################################
# Main

usage ()
{
  echo "\
  Create a jail installer for a rootfs.
  
  Usage: $0 <options>
  
  Options:
    -r
    --rootfs DIR or FILE
      Path of the folder or tarball containing the rootfs for the jail
    
    -n
    --name NAME
      Name for the jail. Do not use blank spaces or symbols
    
    -d
    --descr TEXT
      Description for the jail.
    
    -o
    --osflavour OS
      OS type of the rootfs: 'linux' for 64 bits or 'linux32' for 32 bits
    
    -e
    --destdir DIR
      Directory where the outputs of this tool will be located
      Default: $DESTDIR
    
    -h
    --help
      Show this information
"
}


main ()
{
  ##################################################
  # Input arguments

  while [ "$1" != "" ]; do
    case $1 in
      -r | --rootfs )         shift
                              ROOTFS=$1
                              ;;
      -n | --name )           shift
                              JAILNAME=$1
                              ;;
      -d | --descr )          shift
                              ENVDESCRIPTION=$1
                              ;;
      -o | --osflavour )      shift
                              OSFLAVOUR=$1
                              ;;
      -e | --destdir )        shift
                              DESTDIR=$1
                              ;;
      -h | --help )           usage
                              exit
                              ;;
      * )                     usage
                              exit 1
    esac
    shift
  done


  JAILJAILNAME="jail${JAILNAME#jail}"  # Ensure jail name begins with "jail"

  TARJAILROOTFSNAME="${JAILJAILNAME}.tar.gz"
  INSJAILSCRIPTNAME="${JAILJAILNAME}_install.sh"
  GOJAILSCRIPTNAME="go${JAILJAILNAME}.sh"
  user=`logname`


  echo "
This script will create the installer for the jail: ${JAILNAME}
from the rootfs in: ${JAILTAR}
for the user: ${user}
in: ${DESTDIR}

Inside that path you will find:
* A script to install the jail: ${GOJAILSCRIPTNAME}
* A tar.gz with the rootfs of the jail: $JAILNAME

If you want to change the output path, execute the script with the option 
--destdir DIR
  "

  read -p "Press [Enter] to continue or [Ctrl+C] to cancel..."

  echo "Creating output path if needed..."
  # Create DESTDIR dir
  if [ ! -d "$DESTDIR" ]; then
    mkdir -p "$DESTDIR"
    chown -R $user:$user "$DESTDIR"
  fi
  
  




















  # Extract the jail to the default path
  echo "Extracting jail files..."
  tar -xzvf "${JAILTAR}" -C ${DESTDIR}/${JAILNAME}

  echo "Granting permissions for the user..."
  # Grant access to the jail
  groupadd ${JAILNAME}_jail
  usermod -a -G ${JAILNAME}_jail $user

  # Create jail definition file with proper data
  echo "Creating jail definition..."
  touch /etc/schroot/chroot.d/${JAILNAME}.conf
  cat <<EOF > /etc/schroot/chroot.d/${JAILNAME}.conf
  [${JAILNAME}]
  aliases=${JAILNAME^^},${JAILNAME,,}
  description=${ENVDESCRIPTION}
  personality=${OSFLAVOUR}
  type=directory
  directory=${DESTDIR}/${JAILNAME}
  groups=${JAILNAME}_jail
  root-groups=${JAILNAME}_jail
  script-config=${JAILNAME}/config
  profile=${JAILNAME}
  EOF
  # Note that we created the jail with aliases in lower and upper case

  if [ ! -d "/etc/schroot/$JAILNAME" ]; then
    mkdir -p "/etc/schroot/$JAILNAME"
  fi

  # Create the jail configuration files
  echo "Creating jail configuration..."
  touch /etc/schroot/${JAILNAME}/config
  cat <<EOF > /etc/schroot/${JAILNAME}/config
  FSTAB=/etc/schroot/${JAILNAME}/fstab
  COPYFILES=/etc/schroot/${JAILNAME}/copyfiles
  NSSDATABASES=/etc/schroot/${JAILNAME}/nssdatabases
  EOF

  touch /etc/schroot/${JAILNAME}/fstab
  cat <<EOF > /etc/schroot/${JAILNAME}/fstab
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

  touch /etc/schroot/${JAILNAME}/copyfiles
  cat <<EOF > /etc/schroot/${JAILNAME}/copyfiles
  # Files to copy into the chroot from the host system.
  #
  # <source and destination>
  /etc/resolv.conf
  EOF

  touch /etc/schroot/${JAILNAME}/nssdatabases
  cat <<EOF > /etc/schroot/${JAILNAME}/nssdatabases
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
  echo "Creating gojail script..."
  cat <<EOF > ${DESTDIR}/${GOJAILSCRIPTNAME}
  #!/bin/bash
  JAILNAME=${JAILNAME}
  EOF
  cat <<'EOF' >> ${DESTDIR}/${GOJAILSCRIPTNAME}
  echo Entering to JAIL ${JAILNAME}...
  userNumRecommended=$((`id -u` - 1000))
  echo 
  echo !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  echo !! Do not forget to enter to the user account \'user${userNumRecommended}\' 
  echo !! Working as root is not recommended!!
  echo !!
  echo !! Run: \# su user${userNumRecommended}
  echo !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  echo
  xhost +  # Allow X clients to connect to host X server
  schroot -c ${JAILNAME} --directory=/ --user=root
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


main "$@"

