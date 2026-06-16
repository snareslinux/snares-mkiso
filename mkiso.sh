#!/bin/bash

[[ $# -gt 0 ]] || {
	echo "Usage: $0 <mode> [options]"
	exit 1
}

mode="$1"

[[ "$mode" != -* ]] || {
	echo "!!! First argument most be a mode"
	exit 1
}

shift

prepare_chroot() {
	root="$1"

	mount --rbind /dev "$root/dev"
	mount --make-rslave "$root/dev"

	mount --rbind /proc "$root/proc"
	mount --make-rslave "$root/proc"

	mount --rbind /sys "$root/sys"
	mount --make-rslave "$root/sys"
	
	mount -t tmpfs tmpfs "$root/tmp"
}

cleanup_chroot() {
	root="$1"

	umount -R "$root/dev" 2>/dev/null || true
	umount -R "$root/proc" 2>/dev/null || true
	umount -R "$root/sys" 2>/dev/null || true
	umount "$root/tmp" 2>/dev/null || true
}

run_chroot() {
	root="$1"
	shift

	chroot "$root" /bin/bash
}

case "$mode" in
	install-tools)
		repo="https://repo-de.voidlinux.org/current/musl"

		while getopts ":f" opt; do
			case "$opt" in
				r) repo="$OPTARG" ;;
				:)
					echo "!!! -$OPTARG requires an argument"
					exit 1;
					;;
				*)
					echo "!!! Unknown option: -$OPTARG"
					exit 1;
					;;
			esac
		done

		echo ">>> Installing tool"

		sudo xbps-install \
			-R $repo \
			xbps \
			xorriso \
			grub-x86_64-efi \
			squashfs-tools \
			mtools \
			dosfstools \
			rsync

		echo "Done installing tools."

		;;
	
	build)
		flavour=""
		repo="https://repo-de.voidlinux.org/current/musl"
		flag_x=false
		flag_c=false

		while getopts ":f:r:xc" opt; do
			case "$opt" in
					f) flavour="$OPTARG" ;;
					x) flag_x=true ;;
					r) repo="$OPTARG" ;;
					c) flag_c=true ;;
					:)
						echo "!!! -$OPTARG requires an argument"
						exit 1
						;;
					\?)
						echo "!!! Unknown option: -$OPTARG"
						exit 1
						;;
			esac
		done

		echo ">>> Preparing build"
		
		rm -rf work
		mkdir work
		
		echo "Done preparing build"

		echo ">>> Installing base to rootfs"

		mkdir work/rootfs

		xbps-install \
			-Sy \
			-R $repo \
			-r work/rootfs \
			$(cat profiles/$flavour/packages)

		echo "Done installing base"

		echo ">>> Updating repositories in rootfs"

		mkdir -p work/rootfs/etc/xbps.d

		echo "$repo" > work/rootfs/etc/xbps.d/main-repo.conf

		echo "Done updating repositories"

		echo ">>> Configuring system in rootfs"

		prepare_chroot work/rootfs

		trap 'cleanup_chroot work/rootfs' EXIT

		run_chroot work/rootfs <<EOF

		echo "root:snareslinux" | chpasswd

		useradd -m anon
		echo "anon:snareslinux" | chpasswd
		
		echo "snares" > /etc/hostname

		mkdir -p /etc/dinit.d/boot.d

		ln -sf /etc/dinit.d/dbus /etc/dinit.d/boot.d/dbus
		ln -sf /etc/dinit.d/NetworkManager /etc/dinit.d/boot.d/NetworkManager

		rm -rf /sbin/init
		ln -sf /sbin/dinit /sbin/init

		xbps-reconfigure -fa

		EOF

		echo "Done configuring"

		cleanup_chroot work/rootfs
		trap - EXIT

		echo ">>> Cleaning rootfs"

		rm -rf work/rootfs/var/cache/xbps/*
		rm -rf work/rootfs/var/log/*

		echo "Done cleaning"

		echo ">>> Preparing to compress rootfs"

		mkdir -p work/iso/boot
		mkdir -p work/iso/live

		cp work/rootfs/boot/vmlinuz* work/iso/boot/vmlinuz
		cp work/rootfs/boot/initramfs* work/iso/boot/initramfs.img

		echo "Done preparing"

		echo ">>> Compressing rootfs"

		mksquashfs \
			work/rootfs \
			work/iso/live/filesystem.squashfs \
			-comp zstd

		echo "Done compressing"

		echo ">>> Configuring boot"

		mkdir -p work/iso/boot/grub

		cp defaults/grub.cfg work/iso/boot/grub/grub.cfg

		echo "Done configuring"

		echo ">>> Building ISO"
		
		mkdir output

		grub-mkrescue \
			-o output/snares.iso \
			work/iso
		
		echo "Done building"

		echo "Your ISO can be found in output/"

		;;	
	*)
		echo "!!! Unknown mode: $mode"
		exit 1
		;;
esac
