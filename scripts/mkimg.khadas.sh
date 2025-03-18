build_khadas_blobs() {
#	for i in raspberrypi-bootloader-common raspberrypi-bootloader; do
	for i in khadas-bootloader; do
		apk fetch --root "$APKROOT" --quiet --stdout "$i" | tar -C "${DESTDIR}" -zx --strip=1 boot/ || return 1
	done
}

khadas_gen_cmdline() {
	echo "modules=loop,squashfs,sd-mod,usb-storage quiet ${kernel_cmdline}"
}

khadas_gen_config() {
#	local arm_64bit=0
#	case "$ARCH" in
#		aarch64) arm_64bit=1;;
#	esac
	cat <<-EOF
		kernel=boot/vmlinuz-$kernel_flavors
		initramfs boot/initramfs-$kernel_flavors
		include usercfg.txt
	EOF
}

build_khadas_config() {
	khadas_gen_cmdline > "${DESTDIR}"/cmdline.txt
	khadas_gen_config > "${DESTDIR}"/config.txt
}

section_rpi_config() {
	[ "$hostname" = "khadas" ] || return 0
	build_section khadas_config $( (khadas_gen_cmdline ; khadas_gen_config) | checksum )
#	build_section khadas_blobs
}

profile_khadas() {
	profile_base
	title="Khadas arm device"
	desc="Edge2 ..."
	image_ext="tar.gz"
	arch="aarch64"
	kernel_flavors="khadas-edge2"
	kernel_cmdline="console=tty1"
	initfs_features="base squashfs mmc usb kms dhcp https"
	hostname="khadas"
	grub_mod=
}

create_image_imggz() {
	sync "$DESTDIR"
	local image_size=$(du -L -k -s "$DESTDIR" | awk '{print $1 + 8192}' )
	local imgfile="${OUTDIR}/${output_filename%.gz}"
	dd if=/dev/zero of="$imgfile" bs=1M count=$(( image_size / 1024 ))
	mformat -i "$imgfile" -N 0 ::
	mcopy -s -i "$imgfile" "$DESTDIR"/* "$DESTDIR"/.alpine-release ::
	echo "Compressing $imgfile..."
	pigz -v -f -9 "$imgfile" || gzip -f -9 "$imgfile"
}

profile_rpiimg() {
	profile_rpi
	title="Raspberry Pi Disk Image"
	image_name="alpine-rpi"
	image_ext="img.gz"
}

