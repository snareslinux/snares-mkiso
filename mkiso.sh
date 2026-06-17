#!/bin/bash

ARCH=$(xbps-uhelper arch)

set -euo pipefail

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

	mkdir -p $root/{dev,proc,sys,tmp}

	mount --rbind /dev "$root/dev"
	mount --make-rslave "$root/dev"

	mount --rbind /proc "$root/proc"
	mount --make-rslave "$root/proc"

	mount --rbind /sys "$root/sys"
	mount --make-rslave "$root/sys"
	
	mount -t tmpfs tmpfs "$root/tmp"

	ln -sf usr/bin "$root/bin"
	ln -sf usr/sbin "$root/sbin"
	ln -sf usr/lib "$root/lib"
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

	chroot "$root" /bin/bash -s
}

case "$mode" in
	clean)
		[[ $# -eq 0 ]] || {
			echo "!!! clean does not accept any arguments"
			exit 1
		}

		echo ">>> Cleaning"

		rm -rf work
		rm -rf output

		echo "" > repos.conf

		echo "Done cleaning"

		;;

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
			-S \
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
		custom_repo=""
		flag_x=false
		flag_c=false

		while getopts ":f:xc" opt; do
			case "$opt" in
					f) flavour="$OPTARG" ;;
					x) flag_x=true ;;
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

		repos=()

		while read -r repo; do
			[[ -z "$repo" ]] && continue

			if [[ "$repo" == /* ]]; then
				[[ -d "$repo" ]] || continue
			fi

			repos+=("-R" "$repo")
		done < repos.conf

		echo ">>> Preparing build"
		
		rm -rf work
		rm -rf output

		mkdir work
		
		echo "Done preparing build"

		echo ">>> Installing base to rootfs"

		mkdir work/rootfs

		sudo XBPS_ARCH=x86_64-musl xbps-install \
			-S \
			"${repos[@]}" \
			-r work/rootfs \
			$(cat profiles/$flavour/packages)

		echo "Done installing base"

		echo ">>> Updating repositories in rootfs"

		mkdir -p work/rootfs/etc/xbps.d

		cp repos.conf work/rootfs/etc/xbps.d/main-repo.conf

		echo "Done updating repositories"

		echo ">>> Configuring system in rootfs"

		prepare_chroot work/rootfs

		trap 'cleanup_chroot work/rootfs' EXIT

		run_chroot work/rootfs <<-'EOF'

xbps-reconfigure -fa

HASH=$(openssl passwd -6 "snareslinux")
usermod -p "$HASH" root

useradd -m anon
usermod -p "$HASH" anon

useradd -f wheel
usermod -aG wheel anon

mkdir -p /etc/sudoers.d
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel
chmod 0440 /etc/sudoers.d/wheel

echo "snares" > /etc/hostname
dbus-uuidgen --ensure

echo "snares" > /etc/hostname
dbus-uuidgen --ensure

mkdir -p /var/log/dinit

rm -rf /sbin/init
ln -sf /sbin/dinit /sbin/init

mkdir -p /etc/dracut.conf.d

cat > /etc/dracut.conf.d/live.conf <<DRACUT
add_dracutmodules+=" dmsquash-live pollcdrom "
hostonly="no"
DRACUT

dracut -f /boot/initramfs-live.img $(ls /lib/modules)

for kernel in /lib/modules/*; do
	kver=$(basename "$kernel")
	dracut -f \
		--add "dmsquash-live pollcdrom" \
		/boot/initramfs.img \
		"$kver"
done

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
		cp work/rootfs/boot/initramfs.img work/iso/boot/initramfs.img

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
			-volid SNARES \
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
