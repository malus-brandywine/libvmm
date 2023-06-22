<!--
     Copyright 2023, UNSW (ABN 57 195 873 179)

     SPDX-License-Identifier: CC-BY-SA-4.0
-->

# QEMU Passthrough Application

## Intro

<!-- @jade: update the description -->
Documentation about the QEMU passthrough demo systems. The system contains a VMM and a Linux guest with a passthrough block device and ethernet device.
The purpose of this example is to demonstrate device passthrough on QEMU.

# Issue

1. We don't yet have a serial multiplexor on sel4cp VMM, so only one VM gets to have the passthrough serial device and be able to do serial I/O.

2. Due to the current limitation of the build system, some hacks are used in this system to bypass the configuration, see [more information](../../../docs/camkes_to_cp_guide.md)

3. seL4CP VMM doesn't yet support virtual PCI, so we have to use `virtio-*-device` (via MMIO) instead of `virtio-*-pci`.

# Prerequisites

The QEMU command we use for this example assumes that we already set up an image `sel4cp-vmm.img` and a network tap `tap0` properly.
```shell
$ qemu-system-aarch64 -machine virt,virtualization=on,highmem=off,secure=off \
-cpu cortex-a53 \
-serial mon:stdio \
-device loader,file=your/build/dir/loader.img,addr=0x70000000,cpu-num=0 \
-m size=4G \
-nographic \
-drive id=disk,file=sel4cp-vmm.img,if=none \
-device virtio-blk-device,drive=disk \
-netdev tap,id=mynet0,ifname=tap0,script=no,downscript=no \
-device virtio-net-device,netdev=mynet0,mac=52:55:00:d1:55:01 # you're free to set the MAC addr to your favourite number
```
we are using `-netdev` instead of the newer feature `-nic` because `-nic` doesn't support `virtio-net-device`.

To create an image for the passthrough blk device on you own machine:
```shell
$ dd if=/dev/zero of=sel4cp-vmm.img bs=1M count=1000
$ # you might need to do `sudo modprobe loop`
$ losetup -P /dev/loop0 sel4cp-vmm.img
$ fdisk -l /dev/loop0 # and create a partition
$ mkfs -t ext2 /dev/loop0p1
$ losetup -D
```

To add files to the image:
```shell
$ # you might need to do `sudo su`
$ losetup -P /dev/loop0 sel4cp-vmm.img
$ mount /dev/loop0p1 /mnt/path/to/somewhere
$ cp path/to/your/files/* /mnt/path/to/somewhere/vhost-test/
$ umount /mnt/path/to/somewhere
$ losetup -D
```

To set up a tap interface on you own machine, assuming your network interface is `enp0s3`:
```shell
$ brctl addbr br0
$ ip addr flush dev enp0s3
$ brctl addif br0 enp0s3
$ tunctl -t tap0 -u `whoami`
$ brctl addif br0 tap0
$ dhclient -v br0 # sudo might be needed
```

In case you no longer need the tab interface, and want to do a cleanup:
```shell
$ brctl delif br0 tap0
$ tunctl -d tap0
$ brctl delif br0 enp0s3
$ ifconfig br0 down
$ brctl delbr br0
$ ifconfig enp0s3 up
$ dhclient -v enp0s3
```

# Usage

Build and run the example:
```shell
make -B BUILD_DIR=your/build/dir SEL4CP_SDK=/your/sdk/dir SYSTEM=passthrough.system CONFIG=debug BOARD=qemu_arm_virt_hyp run
```

Mount the disk in guest Linux:
```shell
$ mount /dev/vda1 /mnt/
$ # do stuff
$ umount /mnt/
```

Start the network interface:
```shell
$ ifconfig eth0 up
$ udhcpc eth0
$ ping unsw.edu.au
```

# Reference
1. sel4cp manual: https://github.com/BreakawayConsulting/sel4cp/blob/main/docs/manual.md
2. Setting up Qemu with a tap interface: https://gist.github.com/extremecoders-re/e8fd8a67a515fee0c873dcafc81d811c