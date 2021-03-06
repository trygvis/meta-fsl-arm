inherit image_types

IMAGE_BOOTLOADER ?= "u-boot"

# Handle u-boot suffixes
UBOOT_SUFFIX ?= "bin"
UBOOT_PADDING ?= "0"
UBOOT_SUFFIX_SDCARD ?= "${UBOOT_SUFFIX}"

#
# Handles i.MX mxs bootstream generation
#

UBOOT_SUFFIX_SDCARD_mxs ?= "mxsboot-sdcard"
IMAGE_DEPENDS_uboot.mxsboot-sdcard = "u-boot-mxsboot-native u-boot"
IMAGE_CMD_uboot.mxsboot-sdcard = "mxsboot sd ${DEPLOY_DIR_IMAGE}/u-boot-${MACHINE}.${UBOOT_SUFFIX} \
                                             ${DEPLOY_DIR_IMAGE}/u-boot-${MACHINE}.${UBOOT_SUFFIX_SDCARD}"

#
# Create an image that can by written onto a SD card using dd.
#
# External variables needed:
#   ${SDCARD_ROOTFS}    - the rootfs image to incorporate
#   ${IMAGE_BOOTLOADER} - bootloader to use {u-boot, barebox}x
#
# The disk layout used is:
#
#    0  - 1M                  - reserved to bootloader and other data
#    1M - BOOT_SPACE          - kernel
#    BOOT_SPACE - SDCARD_SIZE - rootfs
#

# Default to 3.4GiB images
SDCARD_SIZE ?= "3400"

# Boot partition volume id
BOOTDD_VOLUME_ID ?= "Boot ${MACHINE}"

# Addional space for boot partition
BOOT_SPACE ?= "5M"

IMAGE_DEPENDS_sdcard = "parted-native dosfstools-native mtools-native \
                        virtual/kernel ${IMAGE_BOOTLOADER}"

SDCARD = "${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}.rootfs.sdcard"

SDCARD_GENERATION_COMMAND_mxs = "generate_mxs_sdcard"
SDCARD_GENERATION_COMMAND_mx5 = "generate_imx_sdcard"
SDCARD_GENERATION_COMMAND_mx6 = "generate_imx_sdcard"

generate_imx_sdcard () {
	# Create partition table
	parted -s ${SDCARD} mklabel msdos
	parted -s ${SDCARD} mkpart primary 0 1M
	parted -s ${SDCARD} mkpart primary 1M ${BOOT_SPACE}
	parted -s ${SDCARD} mkpart primary ${BOOT_SPACE} 100%
	parted ${SDCARD} print

	# Change partition type for mxs processor family
	if [ "${SOC_FAMILY}" = "mxs" ]; then
		bbnote "Setting partition type to 0x53 as required for mxs' SoC family."
		echo -n S | dd of=${SDCARD} bs=1 count=1 seek=450 conv=notrunc
	fi

	case "${IMAGE_BOOTLOADER}" in
		u-boot)
		dd if=${DEPLOY_DIR_IMAGE}/u-boot-${MACHINE}.${UBOOT_SUFFIX_SDCARD} of=${SDCARD} conv=notrunc seek=2 skip=${UBOOT_PADDING} bs=512
		;;
		barebox)
		dd if=${DEPLOY_DIR_IMAGE}/barebox-${MACHINE}.bin of=${SDCARD} conv=notrunc seek=1 skip=1 bs=512
		dd if=${DEPLOY_DIR_IMAGE}/bareboxenv-${MACHINE}.bin of=${SDCARD} conv=notrunc seek=1 bs=512k
		;;
		*)
		bberror "Unkown IMAGE_BOOTLOADER value"
		exit 1
		;;
	esac

	BOOT_BLOCKS=$(LC_ALL=C parted -s ${SDCARD} unit b print \
	                  | awk '/ 2 / { print substr($3, 1, length($3 -1)) / 512 }')
	mkfs.vfat -n "${BOOTDD_VOLUME_ID}" -S 512 -C ${WORKDIR}/boot.img $BOOT_BLOCKS
	mcopy -i ${WORKDIR}/boot.img -s ${DEPLOY_DIR_IMAGE}/uImage-${MACHINE}.bin ::/uImage

	dd if=${WORKDIR}/boot.img of=${SDCARD} conv=notrunc seek=1 bs=1M
	dd if=${SDCARD_ROOTFS} of=${SDCARD} conv=notrunc seek=1 bs=${BOOT_SPACE}
}

generate_mxs_sdcard () {
	# Create partition table
	parted -s ${SDCARD} mklabel msdos
	parted -s ${SDCARD} mkpart primary 1MiB 2MiB
	parted -s ${SDCARD} mkpart primary 2MiB ${BOOT_SPACE}
	parted -s ${SDCARD} mkpart primary ${BOOT_SPACE} 100%
	parted ${SDCARD} print

	# Change partition type for mxs processor family
	bbnote "Setting partition type to 0x53 as required for mxs' SoC family."
	echo -n S | dd of=${SDCARD} bs=1 count=1 seek=450 conv=notrunc

	case "${IMAGE_BOOTLOADER}" in
		u-boot)
		dd if=${DEPLOY_DIR_IMAGE}/u-boot-${MACHINE}.${UBOOT_SUFFIX_SDCARD} of=${SDCARD} conv=notrunc seek=1 skip=${UBOOT_PADDING} bs=1MiB
		;;
		*)
		bberror "Unkown IMAGE_BOOTLOADER value"
		exit 1
		;;
	esac

	BOOT_BLOCKS=$(LC_ALL=C parted -s ${SDCARD} unit b print \
	                  | awk '/ 2 / { print substr($3, 1, length($3 -1)) / 512 }')
	mkfs.vfat -n "${BOOTDD_VOLUME_ID}" -S 512 -C ${WORKDIR}/boot.img $BOOT_BLOCKS
	mcopy -i ${WORKDIR}/boot.img -s ${DEPLOY_DIR_IMAGE}/uImage-${MACHINE}.bin ::/uImage

	dd if=${WORKDIR}/boot.img of=${SDCARD} conv=notrunc seek=2 bs=1MiB
	dd if=${SDCARD_ROOTFS} of=${SDCARD} conv=notrunc seek=1 bs=${BOOT_SPACE}
}

IMAGE_CMD_sdcard () {
	if [ -z "${SDCARD_ROOTFS}" ]; then
		bberror "SDCARD_ROOTFS is undefined. To use sdcard image from Freescale's BSP it needs to be defined."
		exit 1
	fi

	# Initialize a sparse file
	dd if=/dev/zero of=${SDCARD} bs=1 count=0 seek=$(expr 1000 \* 1000 \* ${SDCARD_SIZE})

	${SDCARD_GENERATION_COMMAND}
}
