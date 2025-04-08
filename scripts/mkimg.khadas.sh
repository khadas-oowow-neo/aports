
khadas_gen_cmdline_UNUSED() {
	echo "!!! khadas gen cmdline">&2
	echo "modules=loop,squashfs,sd-mod,usb-storage quiet ${kernel_cmdline}"
}

khadas_gen_config_UNSUSED() {
	echo "!!! khadas gen config">&2
	cat <<-EOF
		kernel=boot/vmlinuz-$kernel_flavors
		initramfs boot/initramfs-$kernel_flavors
		include usercfg.txt
	EOF
}

#build_khadas_config() {
#	echo "BUILD KHADAS CONFIG"
#	khadas_gen_cmdline > "${DESTDIR}"/cmdline.txt
#	khadas_gen_config > "${DESTDIR}"/config.txt
#}

#section_rpi_config() {
#	[ "$hostname" = "khadas" ] || return 0
#	build_section khadas_config $( (khadas_gen_cmdline ; khadas_gen_config) | checksum )
#	build_section khadas_blobs
#}

build_kernel() {
    local _flavor="$2" _modloopsign= _add
    shift 3
    local _pkgs="$@"
    [ "$modloop_sign" = "yes" ] && _modloopsign="--modloopsign"
    CMD "$(dirname "$0")"/khadas/update-kernel2 -v \
	$_hostkeys \
	${_abuild_pubkey:+--apk-pubkey $_abuild_pubkey} \
	$_modloopsign \
	--media \
	--keys-dir "$APKROOT/etc/apk/keys" \
	--flavor "$_flavor" \
	--arch "$ARCH" \
	--package "$_pkgs mkinitfs" \
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
    done
}

profile_khadas() {
	profile_base
	title="Khadas ARM devices"
	desc="Edge2 ..."
	image_ext="tar.gz"
	arch="aarch64"
	modloop_addons="linux-firmware-brcm-khadas-edge2 khadas-dev-boards"

#	kernel_flavors=${KERNEL_FLAVORS:-lts_edge2}
	kernel_flavors=${KERNEL_FLAVORS:-oowow_edge2}
#	kernel_flavors="lts_edge2"
	
	kernel_append="modules=loop,squashfs,sd-mod,usb-storage,cdc_ncm $KERNEL_CMDLINE_APPEND "
	kernel_cmdline="net.ifnames=0 video=HDMI-A-1:1920x1080@60 panic=10 fbcon=font:TER16x32 earlycon=uart8250,mmio32,0xfeb50000 console=ttyFIQ0"
	initfs_features="base squashfs mmc usb kms dhcp https "
	modloopfw="
brcm/BCM.hcd
brcm/BCM4362A2.hcd
brcm/clm_bcm43752a2_pcie_ag.blob
brcm/config.txt
brcm/fw_bcm43752a2_pcie_ag.bin
brcm/fw_bcm43752a2_pcie_ag_apsta.bin
brcm/nvram_AP6275P.txt
brcm/nvram_ap6275p.txt
"
	hostname="khadas"
	apks="$apks
    sfdisk nano
    linux-$kernel_flavors
    $APKS_EXTRA
"
	grub_mod=
}

profile_khadas_img() {
	profile_khadas
	title="Khadas Edge2 Disk Image"
	image_name="alpine-khadas"
	image_ext="img.gz"
}

create_image_imggz() {
    echo "KHADAS img gz"
    sync "$DESTDIR"
    find $DESTDIR
    CMD du -L -k -s "$DESTDIR"
    local part1_start=24576 # 512 byte blocks

    local image_size=$(du -L -k -s "$DESTDIR" | awk '{print $1 + 8192}' ) # 1k bytes blocks
    local imgfile="${OUTDIR}/${output_filename%.gz}"
    image_size=$((image_size+part1_start*2))

    echo "IMAGE_SIZE: $image_size"

    CMD dd if=/dev/zero of="$imgfile" bs=1M count=$(( image_size / 1024 ))

    cat <<EOF | tee /dev/stderr | CMD sfdisk "$imgfile"
label: dos

PART1 : start=$part1_start, type=e
EOF

    local part1_img="$imgfile@@$((part1_start*512))"
    CMD mformat -i "$part1_img" -N 0 ::
    (
    CMD cd $DESTDIR
    echo "DATE: $(date)
SYSTEM: $(uname -a)
USER: $(whoami) $OLDPWD $SSH_CLIENT
" | tee .build-info
    CMD mcopy -s -i "$part1_img" * .alpine-release .build-info ::
    ) || return 1

    #./boot/dtbs-lts_edge2
    #./boot/dtbs-lts_edge2/rockchip
    #./boot/dtbs-lts_edge2/rockchip/rk3588s-khadas-edge2.dtb

    FDT=$(
    cd "$DESTDIR";
    find -name *khadas*.dtb
    )

    CMD mmd -i "$part1_img" ::boot/extlinux
    cat <<EOF | tee /dev/stderr | CMD mcopy -i "$part1_img" - ::boot/extlinux/extlinux.conf
#MENU background /boot/logo.bmp
LABEL $kernel_flavors
    LINUX /boot/vmlinuz-$kernel_flavors
    INITRD /boot/initramfs-$kernel_flavors
    FDT /${FDT#./}
    APPEND $kernel_append $kernel_cmdline

timeout 10
default $kernel_flavors
EOF

    cat <<EOF | tee /dev/stderr | CMD mcopy -i "$part1_img" - ::boot/uEnv.txt
#
# uEnv.txt
#
EOF

    cat <<EOF | tee /dev/stderr | CMD mcopy -i "$part1_img" - ::$FDT.overlay.env
# fdt overlay config file - example
# default
fdt_overlays_dir=
fdt_overlays=
EOF


    ASETUP=${ASETUP:-~/oowow-neo-dev/setup/alpine-setup*}
    [ "$ASETUP" ] && {
	CMD mcopy -vi "$part1_img" $ASETUP ::
    }

    [ "$LBU" ] && {
	CMD mcopy -vi "$part1_img" "$LBU" ::
    }

#   CMD mdir -/ -i "$part1_img" ::

    ls -l1 $imgfile
    echo "Compressing $imgfile..."
    CMD pigz -v -k -f -9 "$imgfile" || CMD gzip -f -9 "$imgfile"
    ls -l1 $imgfile.gz
    md5sum $imgfile.gz | tee $imgfile.gz.md5sum

}
