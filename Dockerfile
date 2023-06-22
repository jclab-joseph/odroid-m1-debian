FROM debian:bullseye as builder

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
    git ca-certificates curl wget python3 python-is-python3 debootstrap \
    e2fsprogs util-linux fdisk

RUN mkdir -p /work/boot /work/rootfs /work/output

ARG DEBIAN_MIRROR=
RUN debootstrap \
    --arch=arm64 \
    --include=ca-certificates,bash-completion,vim,util-linux,fdisk,openssl,passwd,systemd,openssh-server,openssh-sftp-server,openssh-client,ifupdown2,isc-dhcp-client,gnupg2,initramfs-tools \
    bullseye \
    /work/rootfs \
    ${DEBIAN_MIRROR}

ARG KERNEL_VERSION=4.19.219-odroid-arm64

RUN wget -O /work/rootfs/tmp/kernel.deb https://github.com/jclab-joseph/odroid-m1-kernel-builder/releases/download/v4.19.219-r0/linux-image-4.19.219-odroid-arm64_4.19.219-odroid-arm64-1_arm64.deb && \
    chroot /work/rootfs dpkg --install /tmp/kernel.deb

RUN chroot /work/rootfs update-initramfs -k 4.19.219-odroid-arm64 -c

RUN ROOTFS_SIZE=$(du -sb /work/rootfs | sed -E 's/\t/ /g' | cut -d' ' -f1) && \
    ROOTFS_SIZE=$((ROOTFS_SIZE + 134217728 + 1048575)) && \
    ROOTFS_SIZE=$((ROOTFS_SIZE / 1048576)) && \
    rm -rf /work/rootfs/debootstrap && \
    mke2fs -L 'rootfs' \
    -N 0 \
    -d "/work/rootfs/" \
    -m 5 \
    -r 1 \
    -t ext4 \
    "/work/rootfs.ext4" \
    ${ROOTFS_SIZE}M

COPY "boot" "/work/boot/"
RUN cp /work/rootfs/boot/* /work/boot/ && \
    (cd /work/boot/ && ln -s vmlinuz-${KERNEL_VERSION} vmlinuz && ln -s initrd.img-${KERNEL_VERSION} initrd.img) && \
    rm -rf /work/rootfs/boot/* && \
    mke2fs -L 'boot' \
    -N 0 \
    -d "/work/boot/" \
    -m 5 \
    -r 1 \
    -t ext4 \
    "/work/boot.ext4" \
    500M

COPY disk.txt /tmp/disk.txt
RUN DISK_SIZE=$((ROOTFS_SIZE + 500 + 4)) && \
    fallocate -l $((DISK_SIZE * 1024 * 1024)) /work/output/disk.img && \
    sfdisk /work/output/disk.img < /tmp/disk.txt && \
    dd if=/work/boot.ext4 of=/work/output/disk.img bs=512 seek=2048 conv=notrunc && \
    dd if=/work/rootfs.ext4 of=/work/output/disk.img bs=512 seek=1026048 conv=notrunc

FROM scratch

COPY --from=builder ["/work/output/*", "/"]

