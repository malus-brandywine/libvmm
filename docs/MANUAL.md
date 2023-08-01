# seL4CP VMM manual

This document aims to describe the VMM and how to use it. If you feel there is
something missing from this document or the VMM itself, feel free to let us
know by [opening an issue on the GitHub repository](https://github.com/au-ts/sel4cp_vmm).

## Supported platforms

On AArch64, the following platforms are currently supported:
* QEMU ARM virt
* Odroid-C2
* Odroid-C4
* i.MX8MM-EVK

Support for other architectures is in-progress (RISC-V) and planned (x86).

Existing example systems built on these platforms can be found in the
repository under `board/$BOARD/systems/`.

If your desired platform is not supported yet, please see the section on
[adding your own platform support](#adding-platform-support).

## Creating a system

The goal of this section is to give a detailed introduction into making a
system using the VMM. This is done by explaining one of the example QEMU ARM
virt systems that boots up a simple Linux guest.

All the existing systems are located in `board/$BOARD/systems/`. This is
where the Makefile will look when you pass the `SYSTEM` argument.

### Specifying a virtual machine

<!-- @ivanv: Explain <virtual_machine> options etc more. -->

The first step before writing code is to have a system description that contains
a virtual machine and the VMM protection domain (PD).

The following is essentially what is in
[the QEMU example system](../board/qemu_arm_virt_hyp/systems/simple.system),

```xml
<memory_region name="guest_ram" size="0x10_000_000" />
<memory_region name="serial" size="0x1_000" phys_addr="0x9000000" />
<memory_region name="gic_vcpu" size="0x1_000" phys_addr="0x8040000" />

<protection_domain name="VMM" priority="254">
    <program_image path="vmm.elf" />
    <map mr="guest_ram" vaddr="0x40000000" perms="rw" setvar_vaddr="guest_ram_vaddr" />
    <virtual_machine name="linux" id="0">
        <map mr="guest_ram" vaddr="0x40000000" perms="rwx" />
        <map mr="serial" vaddr="0x9000000" perms="rw" />
        <map mr="gic_vcpu" vaddr="0x8010000" perms="rw" />
    </virtual_machine>
</protection_domain>
```

First we create a VMM as a root PD that contains a virtual machine (VM).
This hierarchy is necessary as the VMM needs to be able to access the guest's
TCB registers and VCPU registers for initialising the guest, delivering virtual
interrupts to the guest and restarting the guest.

You will also see that three memory regions (MRs) exist in the system.
1. `guest_ram` for the guest's RAM region
2. `serial` for the UART
3. `gic_vcpu` for the Generic Interrupt Controller VCPU interface

### Guest RAM region

Since the guest does not necessarily know it is being virtualised, it will
expect some view of contiguous RAM that it can use. In this example system, we
decide to give the guest 256MiB to use as "RAM", however you can provide
however much is necessary for your guest. At a bare minimum, there needs to be
enough memory to place the kernel image and any other associated binaries. How
much memory is required for it to function depends on what you intend to do
with the guest.

This region is mapped into the VMM so that is can copy in the kernel image and
any other binaries and is of course also mapped into the virtual machine so
that it has access to its own RAM.

We can see that the region is mapped into the VMM with
`setvar_vaddr="guest_ram_vaddr"`. The VMM expects that variable to contain
the starting address of the guest's RAM. With the current implementation of the
VMM, it expects that the virtual address of the guest RAM that is mapped into
the VMM as well as the guest physical address of the guest RAM to be the same.
This is done for simplicity at the moment, but could be changed in the future
if someone had a strong desire for the two values to not be coupled.

### Serial region

The UART device is passed through to the guest so that it can access it without
trapping into the seL4 kernel/VMM. This is done for performance and simplicity
so that the VMM does not have to emulate accesses to the UART device. Note that
this will work since nothing else is concurrently accessing the device.

### GIC virtual CPU interface region

The GIC VCPU interface region is a hardware device region passed through to the
guest. The device is at a certain physical address, which is then mapped into
the guest at the address of the GIC CPU interface that the guest expects. In the
case of the example above, the GIC VCPU interface is at `0x8040000`, and we map
this into the guest physical address of `0x8010000`, which is where the guest
expects the CPU interface to be. The rest of the GIC is virtualised in the VGIC
driver in the VMM. Like the UART, the address of the GIC is platform specific.

### Running the system

An example Make command looks something like this:
```sh
make BUILD_DIR=build \
     SEL4CP_SDK=/path/to/sdk \
     CONFIG=debug \
     BOARD=qemu_arm_virt_hyp \
     SYSTEM=simple.system \
     run
```

## Adding platform support

Before you can port the VMM to your desired platform you must have the following:

* A working platform port of the seL4 kernel in hypervisor mode.
* A working platform port of the seL4 Core Platform where the kernel is built as a
  hypervisor.

### Guest setup

While in theory you should be able to run any guest, the VMM has only been tested
with Linux and hence the following instructions are somewhat Linux specific.

Required guest files:

* Kernel image
* Device Tree Source to be passed to the kernel at boot
* Initial RAM disk

Each platform image directory (`board/$BOARD/images`) contains a README with
instructions on how to reproduce the images used if you would like to see
examples of how other example systems are setup.

Before attempting to get the VMM working, I strongly encourage you to make sure
that these binaries work natively, as in, without being virtualised. If they do
not, they likely will not work with the VMM either.

You can either add these images into `board/$BOARD/images/` or specify the
`IMAGE_DIR` argument when building the system which points to the directory
that contains all of the files.

#### Implementation notes

Currently the VMM expects three separate images, the guest kernel image, the
Device Tree Blob (DTB), and the initial RAM disk. Despite it being possible to
package all of these into one single image for a guest such as Linux, there has
currently been no benefit to do this. It would be trivial to change the VMM to
allow a different combination of guest images. If you need this behaviour, please
open a GitHub issue or pull request.

The VMM also (for now) does not have the ability to generate a DTB at runtime,
therefore requiring the Device Tree Source at build time.

### Generic Interrupt Controller (GIC)

On ARM architectures, there is a hardware device called the Generic Interrupt
Controller (GIC). This device is responsible for managing interrupts between
the hardware devices (e.g serial or ethernet) and software. Driving this device
is necessary for any kind of guest operating system.

Version 2, 3, and 4 of the GIC device is not fully virtualised by the hardware.
This means that the parts that are not virtualised by the hardware must be instead
emulated by the VMM.

The VMM currently supports GIC version 2 and 3. GIC version 4 is a super-set of
GIC version so if you see that your platform supports GIC version 4, it should
still work with the VMM. If your platform does not support the GIC versions listed
then the GIC emulation will need to be changed before your platform can be supported.

### Add platform to VMM source code

<!-- @ivanv: These instructions could be improved -->

Lastly, there are some hard-coded values that the VMM needs to support a platform.
There are three files that need to be changed:

* `src/vmm.h`
* `src/vgic/vgic.h`
* For Linux, the device tree needs to contain the location of the initial RAM disk,
  see the `chosen` node of `board/qemu_arm_virt_hyp/images/linux.dts` as an example.

As you can probably tell, all this information that needs to be added is known at
build-time, the plan is to auto-generate these values that the VMM needs to make it
easier to add platform support (and in general make the VMM less fragile).

### Getting the guest image to boot

Getting your guest image to boot without any issues is most likely going to be
platform dependent. This part of the manual aims to provide some guidance for
what to do when your guest image is failing to boot.

#### Virtual memory faults

A very common issue with booting a guest kernel, such as Linux, is that it unexpectedly
has a virtual memory fault in a location that the VMM was not expecting. In Linux, this
usually happens as it is starting up drivers for the various devices on the platform and
the guest does not have access to the location of the device.

There are three options to resolve this.
1. Give the guest access to the region of memory it is trying to access.
2. Disable the device in the node for the device in the Device Tree Source.
3. Configure the guest image without the device driver, so that it does not
try to access it.

##### Option 1 - give the guest access to the memory
##### Option 2 - disabling the device in the device tree

Assuming the guest is being passed a device tree and initialising devices
based on the device tree passed, it is quite simple to disable the device.

Here is an example of how you would change the Device Tree Source to
disable the PL011 UART node for the QEMU ARM virt platform:
```diff
pl011@9000000 {
    clock-names = "uartclk\0apb_pclk";
    clocks = <0x8000 0x8000>;
    interrupts = <0x00 0x01 0x04>;
    reg = <0x00 0x9000000 0x00 0x1000>;
    compatible = "arm,pl011\0arm,primecell";
+   status = "disabled";
};
```

##### Option 3 - configure the guest without the device driver

We will look at Linux for specific examples of how to configure the device
drivers it will use.

A default and generic Linux image (for AArch64) can be built with the following
commands:
```sh
# Configure the kernel based on the default architecture config
make ARCH=arm64 CROSS_COMPILE=<CROSS_COMPILER_PREFIX> defconfig
# Compile the kernel
make ARCH=arm64 CROSS_COMPILE=aarch64-none-elf -j<NUM_THREADS>
```

This will package in a lot of drivers (and perhaps a lot more than you need)
as it is a generic image supposed to work on any AArch64 platform. If you
see that Linux is faulting because it is initialising a particular device,
look in the menu configuration and try to find the enabled option, and
disable it.

To open the menuconfig, run:
```sh
make ARCH=arm64 menuconfig
```

If you are compiling for a different architecture, then replace `arm64` with
your architecture.

If you are unsure or cannot find the configuration option for the device driver,
first find the node for the device in the Device Tree Source. You will see it
has a compatible field such as `compatible = "amlogic,meson-gx-uart`.

By searching for the value of the compatible field in the Linux source code,
you will find the corresponding driver source code.
