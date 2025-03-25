khadas_gen_cmdline() {
	echo "modules=loop,squashfs,sd-mod,usb-storage quiet ${kernel_cmdline}"
}

khadas_gen_config() {
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

build_kernel() {
    local _flavor="$2" _modloopsign= _add
    shift 3
    local _pkgs="$@"
    [ "$modloop_sign" = "yes" ] && _modloopsign="--modloopsign"
    CMD ./update-kernel2 -v \
	$_hostkeys \
	${_abuild_pubkey:+--apk-pubkey $_abuild_pubkey} \
	$_modloopsign \
	--media \
	--keys-dir "$APKROOT/etc/apk/keys" \
	--flavor "$_flavor" \
	--arch "$ARCH" \
	--package "$_pkgs" \
	--feature "$initfs_features" \
	--modloopfw "$modloopfw" \
	--repositories-file "$APKROOT/etc/apk/repositories" \
	"$DESTDIR" \
	|| return 1
    for _add in $boot_addons; do
	apk fetch --root "$APKROOT" --quiet --stdout $_add | tar -C "${DESTDIR}" -zx boot/
    done
}

section_kernels() {
    local _f _a _pkgs
    for _f in $kernel_flavors; do
	_pkgs="linux-$_f $modloop_addons"
	for _a in $kernel_addons; do
	    _pkgs="$_pkgs $_a-$_f"
	done
	echo "$initfs_features::$_hostkeys" ; apk fetch --root "$APKROOT" --simulate alpine-base $_pkgs 2>/dev/null | sort
	
	local id=$( (echo "$initfs_features::$_hostkeys" ; apk fetch --root "$APKROOT" --simulate alpine-base $_pkgs | sort) | checksum)
	build_section kernel $ARCH $_f $id $_pkgs
	exit 1
    done
}

profile_khadas() {
	profile_base
	title="Khadas arm device"
	desc="Edge2 ..."
	image_ext="tar.gz"
	arch="aarch64"
	kernel_flavors="khadas-edge2-oowow-neo-bin"
#	kernel_flavors="rpi"
	kernel_cmdline="console=tty1"
	initfs_features="base squashfs mmc usb kms dhcp https"
	hostname="khadas"
	grub_mod=
}

profile_khadas_img() {
	profile_khadas
	title="Khadas Edge2 Disk Image"
	image_name="alpine-khadas"
	image_ext="img.gz"
}
