# bakefat: bootable external FAT disk image creator for DOS and Windows 3.1--95--98--ME

bakefat is an easy-to-use tool for creating bootable hard disk images with a
FAT16 or FAT32 filesystem, and floppy disk images with a FAT12 filesystem,
usable in virtual machines running DOS (MS-DOS 4.01--6.22 or PC-DOS
4.01--7.1) or Windows 3.1--95--95-ME in an emulator (such as QEMU or
VirtualBox). bakefat is an external tool, i.e. it runs on the host system.
bakefat creates a FAT filesystem, makes it bootable by writing boot code to
the boot sector, creates a partition, and makes the system bootable by
writing boot code to the MBR. After that the user has to copy the system
files (such as io.sys, command.com and maybe a few more) manually (using
e.g. Mtools), and the system becomes bootable in the virtual machine.

bakefat is currently **PARTIALLY IMLEMENTED**, this document currently
describes how it would look like and function.

## bakefat features and limitations

* bakefat runs on the host system. Installing an emulator is not necessary
  to run bakefat.
* bakefat is a single-file (statically linked) command-line tool without
  external dependencies. Binary releases are built for Linux i386 (also runs
  on Linux amd64, FreeBSD i386 and FreeBSD amd64), Win32 and macOS x86_64.
  Its C source is architecture-independent and system-independent.
* It adjusts most parameters and sizes automatically. The user only has to
  decide the disk image size (in megabytes) and the operating system
  compatibility, and (optionally) the filesystem type (FAT16 or FAT32). By
  default, bakefat chooses the best filesystem type for the desired operating
  system. There is no need for manual calculations.
* It goes to extreme lengths to make all header field values compatible with
  all supported guest operating systems. This involves autodetecting and
  filling the following header fields at boot time and writing them back to
  disk before the guest operating system has a chance to read them: CHS
  geometry (sectors per track and head count fields in the FAT BPB),
  partition start and end CHS values (in the partition table), EBIOS (LBA)
  feature presence (byte at offset 2 in the FAT boot sector), hidden sector
  count (same as the partition sector offset (LBA), in the FAT BPB), drive
  number (in the FAT BPB).
* The user can also specify the number of FATs, to override the default
  (which is usually 2).
* No need to run any other tool (such as fdisk, install-mbr, mkfs.vfat,
  mformat, ms-sys, bootlace.com) on the host system, the output of bakefat
  is a complete, proper, bootable disk image with a filesystem and a
  partition table, with parameters and sizes correctly autodetected and
  adjusted.
* No need to run any tool (such as fdisk.exe, sys.com or format.com) in the
  virtual machine, everything is automatic, and everything is run with the
  correct autodetected parameters.
* It works with both CHS and LBA (EBIOS) hard disk addressing. It
  autodetects both, and chooses the one which works better. Its boot code
  does the autodetection automatically, upon each reboot of the virtual
  machine.
* It automates partition sector alignment so that it works in DOS <=6.22 and
  Mtools.
* It automates cluster alignment to a multiple of 4 KiB for efficient I/O on
  host filesystems.
* It fills the partition table (MBR and CHS fields) and the FAT filesystem
  BPB headers in a compatible way, so every type and version of DOS will
  boot and will be able to access the FAT filesystem.
* It supports only the MBR partitioning scheme (no GPT).
* It creates a single partition spanning the entire virtual hard disk. (Use
  a partitioning tool to resize and add more partitions.)
* It supports only the FAT16 and FAT32 filesystems (no FAT8, FAT12, NTFS,
  ISO9660, UDF, Linux ext2 etc.) on the virtual hard disk.
* It creates disk image files. Alternatively it can also write to block
  devices (Linux and macOS only, not supported on Win32).
* It uses sparse files for disk images on Linux and macOS so that space on
  the host filesystem is only used by the files, not the empty space. An
  empty disk images uses less than 32 KiB of host filesystem space (plus
  metadata).
* It sets up the boot code so that it doesn't matter where the system files
  (such as io.sys) are on the FAT filesystem, as long as they are in the
  root directory.
* It doesn't contain a boot manager: it can boot only a single guest
  operating system from a hard disk image.
* It provides a tool to apply binary patches to some DOS kernel files (e.g.
  *io.sys* files) to make them more flexible when booting, such as accepting
  a FAT filesystem with only 1 FAT, accepting a FAT filesystem with more
  than 1 reserved sectors and loading a fragmented *io.sys*.

Guest operating systems supported by bakefat for booting:

* MS-DOS 4.01--5.00--5.x--6.x--6.22 *io.sys* and *msdos.sys*.
* IBM PC DOS 4.01--5.00--5.x--6.x--7.0--2000--7.1 *ibmbio.com* and
  *ibmdos.com*.
* Windows 3.1: Boot to MS-DOS 6.22 or patched 7.1 or patched 8.0 (with
  bakefat), then run *setup.exe* of Windows 3.1.
* Windows 95--98--ME *io.sys* and community releases based on these. Windows
  ME is supported only in the multiboot.ru MSDOS8.ISO (get it from
  [here](http://www.multiboot.ru/download/)) MS-DOS 8.0 community release.
  It's possible to install the GUI by first booting to DOS mode (with
  bakefat), and then running *setup.exe*.
* Windows XP (and Windows NT 3.1--4.0 and Windows 2000) installer: Boot to
  Windows 95 OSR2 or Windows 98 DOS mode or MS-DOS 6.22 (with bakefat), then
  run *setup.exe* of Windows XP.
* An already installed Windows XP (and Windows NT 3.1--4.0 and Windows 2000)
  boots using the file named *ntldr* as the kernel. To make the bakefat boot
  code use that, specify the flag *ntldr* when creating the hard disk image
  with bakefat: `bakefat 2G ntldr myhd.img`.

Guest operating systems which may be supported in the future by bakefat for
booting:

* FreeDOS 1.0--1.1--1.2--1.3-- *kernel.sys*.
* SvarDOS 2024-- *kernel.sys*. (This uses a fork of the EDR-DOS kernel.)
* Earlier versions of DR-DOS 7 and EDR-DOS, *drbios.sys* and *drbdos.sys*.
* Datalight ROM-DOS 6.22--7.1 *rom-dos.sys*.
* General Software Embedded DOS-ROM 4.04-- *dos.sys*.
* GRUB4DOS --0.4.4-- *grldr*.
* GRUB 1 *stage2*.
* GRUB 2 i386-pc *core.img*.
* SYSLINUX *syslinux.bin*.

Emulators tested and working with bakefat:

* QEMU (qemu-system-i386 and qemu-system-x86_64).
* VirtualBox.
* VMware Player.

## How to use bakefat

Here is how to use bakefat:

1. Download the program file bakefat and (on Linux and macOS) make it
   executable.

2. In a command window (terminal), run bakefat to create a disk image.

   For example, this is how to create the (approximately) 500 MiB disk image
   file *myhd.img*, making it comaptible with MS-DOS 6.x, on Linux (without
   a leading dollar):

   ```
   $ chmod +x bakefat
   $ ./bakefat 500M myhd.img
   ```

   On Windows, this command looks like this (run from the download folder):

   ```
   bakefat 500M myhd.img
   ```

3. Download the installer (or rescue disk) of your favorite operating system
   (see the supported systems below). After extraction, look for a file of
   size 1474560 bytes (1.44 MB). If there are many, use the one with the
   number 1 or the word *boot* in the filename. Copy it to *fdsys.img*.

4. Copy the system files from the floppy image to the hard disk image.

   For example, copying the MS-DOS 6.22 system files with Mtools on Linux
   and macOS:

   ```
   $ mtools -c mcopy -bsomp -i fdsys.img ::IO.SYS ::MSDOS.SYS ::COMMAND.COM ./
   $ mtools -c mcopy -bsomp -i myhd.img IO.SYS MSDOS.SYS COMMAND.COM ::
   $ mtools -c mattrib -i myhd.img +s ::IO.SYS ::MSDOS.SYS
   ```

4. Set up a new virtual machine in your favorite emulator with a single hard
   disk with image file *myhd.img*. If asked, use legacy (BIOS) booting
   rather than EFI or secure boot. For DOS, give it 2 MiB of memory. For
   Windows 95--98--ME, give it 16 MiB of memory. For Windows NT--2000--XP,
   give it 64 MiB of memory.

   For QEMU, see the instructions in the next step.

5. Start the virtual machine in the emulator.

   To do so with QEMU, use this command:

   ```
   qemu-system-i386 -M pc-1.0 -m 16 -nodefaults -vga cirrus -drive file=myhd.img,format=raw -boot c
`  ```

   Alternatively, if you also want to see the contents of the operating
   system boot and installer floppy, run this command:

   ```
   qemu-system-i386 -M pc-1.0 -m 16 -nodefaults -vga cirrus -drive file=myhd.img,format=raw -drive file=fdsys.img,format=raw,if=floppy -boot c
   ```

6. Wait for the guest operating system to boot in the virtual machine.

   For example, MS-DOS 6.22 will look like this in QEMU:

   ```
   SeaBIOS (version ...)
   Booting from Hard Disk...
   Starting MS-DOS...


   MS-DOS Version 6.22


   C:\>_
   ```

   The typical command you can try is `dir`.

   You can turn off the virtual machine at any time, there is no shoutdown
   procedure. bakefat adds *o.com* to hard disk image. Just run `o` to do a
   power off, initiated from inside.

8. Please note that the *mcopy* above didn't do a full operating system
   installation. For that you still have to run `a:\\setup.exe` or
   `a:\\install.exe`, or boot from floppy. (Use the longer QEMU command
   above, containing *fdsys.img*.) Advanced users may just copy
   files from the floppy image(s), and write their own *config.sys* and
   autoexec.bat*, without doing a proper installation.

When the virtual machine is not running, you can copy files to and from the
disk image (*myhd.img*). Use Mtools on the host machine, for example:

```
echo hello, world >hi.txt
mtools -c mcopy -bsomp -i myhd.img hi.txt ::HI.TXT
```

Then within the virtual machine:

```
C:\>type hi.txt
hello, world

C:\>
```

Please note that there is no need to specify partition offsets for the
Mtools `-i` flag (such as `-i myhd.img@@16384`), bakefat creates the MBR
headers in a way that Mtools works with our without an offset.

## How to create floppy images using the alternative, NASM-only way

Please note that most users should run the *bakefat* command instead, as
described above.

Here is how to create floppy images using NASM only:

1. This is already implemented in the file [fat12b.nasm](fat12b.nasm). The
   shell script [fat12b.sh](fat12b.sh) provides some example commands on
   building bootable floppy disk images.

2. Clone the Git repository, open a terminal window, and cd to the clone
   *bakefat* directory.

3. Install NASM and Mtools. (This is easy on a Linux, macOS or a Unix-like
   system. Use your package manager.)

4. Decide how many kilobytes large your floppy disk image should be. The
   supported sizes are: 160K, 180K, 320K, 360K, 720K, 1200K, 1440K and
   2880K. If in doubt, choose 1200K, that's large and compatible with all
   supported DOS versions.

5. Run this command (specifying the chosen size after `-DP_`) to create the
   floppy disk image file *myfd.img*:

   ```
   nasm -O0 -w+orphan-labels -f bin -DP_1200K -o myfd.img fat12b.nasm
   ```

   This command has created a bootable disk image with a FAT12 filesystem,
   but the system files (1 or 2 kernel files and *command.com*) are missing.

6. Obtain a supported version of MS-DOS (3.30--6.22), IBM PC DOS (3.30--7.1)
   or Windows 95--98--ME boot floppy. Software archives typically have the
   boot floppy image as *disk01.img* (or *boot.img*) as part of the download.

7. Copy the kernel files and *command.com* to *myfd.img*.

   For MS-DOS --6.22:

   ```
   mtools -c mcopy -bsomp -i disk01.img ::IO.SYS ::MSDOS.SYS ::COMMAND.COM ./
   mtools -c mcopy -bsomp -i IO.SYS MSDOS.SYS COMMAND.COM ::
   mtools -c mattrib -i myfd.img +s ::IO.SYS ::MSDOS.SYS
   ```

   For Windows 95--98--ME (MS-DOS 7.x or 8.0):

   ```
   mtools -c mcopy -bsomp -i disk01.img ::IO.SYS ::COMMAND.COM ./
   mtools -c mcopy -bsomp -i IO.SYS COMMAND.COM ::
   mtools -c mattrib -i myfd.img +s ::IO.SYS
   ```

   For IBM PC DOS:

   ```
   mtools -c mcopy -bsomp -i disk01.img ::IBMBIO.COM ::IBMDOS.COM ::COMMAND.COM ./
   mtools -c mcopy -bsomp -i IO.SYS IBMDOS.COM COMMAND.COM ::
   mtools -c mattrib -i myfd.img +s ::IBMBIO.COM ::IBMDOS.COM
   ```

5. Start the virtual machine in the emulator.

   To do so with QEMU, use this command:

   ```
   qemu-system-i386 -M pc-1.0 -m 16 -nodefaults -vga cirrus -drive file=myfd.img,format=raw,if=floppy -boot a
   ```

   Alternatively, if you also want to see the contents of the operating
   system boot and installer floppy, run this command:

   ```
   qemu-system-i386 -M pc-1.0 -m 16 -nodefaults -vga cirrus -drive file=myhd.img,format=raw -drive file=fdsys.img,format=raw,if=floppy -boot c
   ```

## The bakefat hard disk boot process

This is how the operating system boots from a hard disk image created by
bakefat:

1. The BIOS of the virtual machine loads the first sector (offset 0 (LBA))
   from the hard disk. This sector contains the partition table and the
   bakefat MBR boot code. (It also contains a copy of the FAT filesystem
   headers for the external Mtools without an offset, but that's not needed
   for booting.)

2. The bakefat MBR boot code locates the partition containing the FAT
   filesystem, and loads its first sector, the boot sector. This sector
   contains the FAT filesystem headers and the bakefat boot sector boot code.
   The MBR boot code jumps to the boot sector boot code.

3. The bakefat boot sector boot code locates the operating system kernel
   files *io.sys*, *msdos.sys*, *ibmbio.com* and/or *ibmdos.com* in the root
   directory of the FAT filesystem, autodetects the load protocal, and loads
   the first 1536 or 2048 bytes of the first kernel file (depending on the
   load protocol), sets up the register and memory values, and jumps to the
   kernel startup code.

   The load protocol is autodetected like this:

   * If the file *io.sys* is found, and its size is at least 64 KiB, then
     the boot code uses the [MS-DOS v7 load
     protocol](https://pushbx.org/ecm/doc/ldosboot.htm#protocol-sector-msdos7)
     (for booting Windows 95--98--ME and MS-DOS 7.0--7.1--8.0).
     Windows ME and MS-DOS 8.0 are supported only in the
     multiboot.ru MSDOS8.ISO (get it from
     [here](http://www.multiboot.ru/download/)) MS-DOS 8.0 community
     release, and also in
     [TPC-WinMe-DOSMODE](https://github.com/gpdm/TPC-WinMe-DOSMODE)
     community release. MS-DOS 7.1 CDN (community release based on Windows
     98 SE) is also supported.
   * If the file *io.sys* is found, and its size is less than 64 KiB, and
     the file *msdos.sys* is also found, then the boot code uses the [MS-DOS
     v6 load
     protocol](https://pushbx.org/ecm/doc/ldosboot.htm#protocol-sector-msdos6)
     (for booting MS-DOS 3.30--6.22).
   * If the file *ibmbio.com* is found, and the file *ibmdos.com* is also
     found, then the boot code uses a combination of the [MS-DOS v6 load
     protocol](https://pushbx.org/ecm/doc/ldosboot.htm#protocol-sector-msdos6)
     (for booting IBM PC DOS 3.30--7.0) and the [IBM PC DOS v7 load
     protocol](https://pushbx.org/ecm/doc/ldosboot.htm#protocol-sector-ibmdos)
     (for booting IBM PC DOS 7.1).
   * Don't put a combination of these files (e.g. *io.sys* and *ibmdos.com*)
     to the same disk image, because that confuses the boot code.
   * Booting 86-DOS or a version of MS-DOS or IBM PC DOS older than 3.30 is
     not supported, because those load protocols are not implemented in the
     bakefat boot code. (For example, MS-DOS 3.20 and IBM PC DOS 3.20 boot
     code loads the entire *io.sys* file, not just the first 1536 bytes.)

   If the disk image has been created with the *bakefat ntldr* flag, then
   the boot sector boot code uses the following load protocol instead:

   * If the file *ntldr* is found, the the boot code uses the Windows NT
     load protocol (for booting Windows NT 3.1--3.5--3.51--4.0, Windows
     2000, Windows XP).

Guest operating system installers tend to modify the partition table, the
MBR boot code, the FAT filesystem headers in the partition boot sector
and/or the boot code in the partition boot sectors. All such modifications
work fine, except for a single problematic case, which makes the virtual
machine unbootable: the installer modifies the MBR boot code, but it keeps
the bakefat boot code in the partition boot sector intact. Fortunately,
existing DOS and Windows installers don't do that.

## bakefat software source and build details

These are the bakefat software source and build details:

* Boot code is written in 16-bit 8086 assembly: NASM 0.98.39.
* The bakefat command-line tool is written in architecture-independent and
  system-independent ANSI C (C89) (except for calls to some library
  functions such as ftruncate64(2)). The source compiles on either
  sizeof(int) == 2 or == 4.
* The command-line tool contains the boot code precompiled by NASM as a
  few pieces of binary blob.
* TODO: On DOS, add an option to write sectors directly to disk.
