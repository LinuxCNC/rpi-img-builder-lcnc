#!/bin/bash

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

if [[ -f "/etc/opt/board.txt" ]]; then
	. /etc/opt/board.txt
fi

RELEASE=`cat /etc/os-release | grep -w NAME | sed 's/NAME=//g' | sed 's/"//g' | sed 's/ GNU\/Linux//g'`
BOOT=`findmnt -v -n -o SOURCE /boot/broadcom`
ROOTFS=`findmnt -v -n -o SOURCE /`
GROW=`findmnt -v -n -o SOURCE / | sed 's/p/ /'`
GROW_SD=`findmnt -v -n -o SOURCE / | sed 's/./& /8'`

# Functions
partition_uuid(){
echo 'ROOT_PARTUUID="' > root1
blkid -o export -- $ROOTFS | sed -ne 's/^PARTUUID=//p' > root2
echo '"' > root3
paste -d '\0' root1 root2 root3  > /etc/opt/root-pid.txt
rm -f root1 root2 root3
}

create_cmdline(){
if [[ `findmnt -v -n -o FSTYPE / | grep -w "ext4"` ]]; then
	ROOTFSTYPE="rootfstype=ext4";
fi
if [[ `findmnt -v -n -o FSTYPE / | grep -w "btrfs"` ]]; then
	ROOTFSTYPE="rootfstype=btrfs rootflags=subvol=@";
fi
if [[ `findmnt -v -n -o FSTYPE / | grep -w "xfs"` ]]; then
	ROOTFSTYPE="rootfstype=xfs";
fi
source /etc/opt/root-pid.txt
rm -f /boot/broadcom/cmdline.txt
tee /boot/broadcom/cmdline.txt <<EOF
console=serial0,115200 console=tty1 root=PARTUUID=${ROOT_PARTUUID} ${ROOTFSTYPE} fsck.repair=yes logo.nologo net.ifnames=0 firmware_class.path=/lib/firmware/updates/brcm rootwait
EOF
rm -f /etc/opt/root-pid.txt
}

disable_bthelper(){
if [[ `grep -w "Raspberry\ Pi\ 2" "/proc/cpuinfo"` ]]; then
	update-rc.d -f bthelper remove;
fi
if [[ `grep -w "Raspberry\ Pi\ Model\ B\ Rev\ 1" "/proc/cpuinfo"` ]]; then
	update-rc.d -f bthelper remove;
fi
if [[ `grep -w "Raspberry\ Pi\ Model\ B\ Rev\ 2" "/proc/cpuinfo"` ]]; then
	update-rc.d -f bthelper remove;
fi
}

# Expand root filesystem
if [[ "$RELEASE" == "Devuan" ]]; then
	echo ""
	echo -e " \033[1mExpanding root filesystem\033[0m ...";
fi
if [[ `findmnt -v -n -o SOURCE / | grep "mmc"` ]] || [[ `findmnt -v -n -o SOURCE / | grep "nvme"` ]]; then
	bash growpart $GROW > /dev/null 2>&1;
fi
if [[ `findmnt -v -n -o SOURCE / | grep "sd"` ]]; then
	bash growpart $GROW_SD > /dev/null 2>&1;
fi
sleep .50
if [[ `findmnt -v -n -o FSTYPE / | grep -w "ext4"` ]]; then
	resize2fs $ROOTFS > /dev/null 2>&1;
fi
if [[ `findmnt -v -n -o FSTYPE / | grep -w "btrfs"` ]]; then
	btrfs filesystem resize max / > /dev/null 2>&1;
fi
if [[ `findmnt -v -n -o FSTYPE / | grep -w "xfs"` ]]; then
	xfs_growfs -d / > /dev/null 2>&1;
fi

# Fsck boot partition
if [[ -d "/boot/broadcom" ]]; then
	if [[ "$RELEASE" == "Devuan" ]]; then
		echo -e " \033[1mRunning fsck on boot partition\033[0m ...";
	fi
	umount /boot/broadcom
	sleep .50
	bash fsck.fat -trawl $BOOT > /dev/null 2>&1
	sleep .50
	mount /boot/broadcom
	sleep 1s
	if [[ "$ARCH" == "arm" ]]; then
		partition_uuid
		sleep 1s;
		create_cmdline
	fi
fi

# Clean up
if [[ "$RELEASE" == "Debian" || "$RELEASE" == "Ubuntu" ]]; then
	rm -f /var/cache/debconf/*
	rm -f /usr/local/sbin/firstboot
	systemctl disable firstboot;
fi
if [[ "$RELEASE" == "Devuan" ]]; then
	disable_bthelper
	update-rc.d firstboot remove
	rm -f /etc/init.d/firstboot
	rm -f /var/cache/debconf/*
	rm -f /usr/local/sbin/firstboot;
fi

exit 0
