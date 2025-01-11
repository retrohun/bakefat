# mbrsys: bootable hard disk image creator for DOS and Windows 3.1--95--98--ME

mbrsys is an easy-to-use, beginner-friendly tool for creating bootable hard
disk images with FAT16 or FAT32 filesystems, usable in virtual machines
running DOS (MS-DOS 4.01--6.22 or PC-DOS 4.01--7.1) or Windows
3.1--95--95-ME in an emulator (such as QEMU or VirtualBox). mrsys runs on
the virtual machine, before the guest operating system installer starts.
mbrsys creates a FAT filesystem, copies the guest system files (io.sys,
command.com and a few more if needed) to it, makes it bootable by writing
boot code to the boot sector, creates a partition, and makes the system
bootable by writing boot code to the MBR.

mbrsys is currently **UNIMPLEMENTED**, this document currently describes how
it would look like and function.

mbrsys features and limitations:

* It is designed for emulators, but it also works on bare metal PCs (any
  8086-based CPU, no need for 186, 286 or 386).
* It adjusts most parameters and sizes automatically. The user only has to
  decide the disk image size (in megabytes) and the filesystem type (FAT16
  or FAT32, and mbrsys makes a recommendation), no need for manual
  calculations.
* No need to run any tool (such as fdisk, install-mbr, mkfs.vfat, mformat,
  ms-sys, bootlace.com) on the host system, the output of mbrsys is is a
  complete, proper, bootable filesystem and partition table, with parameters
  and sizes correctly autodetected and adjusted.
* No need to run any tool (such as fdisk.exe, sys.com or format.com) within
  the virtual machine, mbrsys has already created the filesystem and
  partition table, and made them bootable before these tools would run.
* It works with both CHS and LBA (EBIOS) hard disk addressing. It
  autodetects both, and chooses the one which works better.
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

Here is how to use mbrsys:

1. Download the file mbrsys.bin.

2. Copy the mbrsys.bin file to and resize it to your desired size.

   On Linux and macOS, this looks like this (type the commands without the
   leading `$`):

   ```
   $ cp mbrsys.bin myhd.img
   $ truncate -s 500M myhd.img
   ```

   (In the future, a longer command will be posed, which appends the VHD
   footer for VirtualBox.)

   On Windows, download the file mkhd.exe, double click on it, and answer its
   questions (finish your answers by pressing <Enter>):

   ```
   File name of the disk image to create: myhd.img
   Disk image size: 500M
   Disk image created. Press <Enter> to close this window.
   ```

3. Download the installer (or rescue disk) of your favorite operating system
   (see the supported systems below). After extraction, look for a file of
   size 1474560 bytes (1.44 MB). If there are many, use the one with the
   number 1 or the word *boot* in the filename. Copy it to *fdsys.img* in your
   download folder.

4. Set up a new virtual machine in your favorite emulator with a single hard
   disk with image file *myhd.img*, and a single floppy disk with the image
   *fdsys.img*. Set it up to boot from the hard disk (HDD). If asked, use
   legacy (BIOS) booting rather than EFI or secure boot. For DOS, give it 2
   MiB of memory. For Windows, give it 16 MiB of memory.

   For QEMU, see the instructions in the next step.

5. Start the virtual machine.

   To do so in QEMU, use this command:

   ```
   qemu-system-i386 -M pc-1.0 -m 16 -nodefaults -vga cirrus -hda myhd.img -fda fdsys.img -boot c
`  ```

6. Wait for mbrsys to load in the virtual machine. Upon first boot, in the
   black window, it will ask you which kind of filesystem you want to
   create: FAT16 or FAT32. If unsure, choose the first option.

   It will look like this:

   ```
   SeaBIOS (version ...)
   Booting from Hard Disk...
   Starting mbrsys...
   Found MS-DOS 6.22 on the floppy.
   Hard disk size is 500 MiB (... sectors of 512 bytes each).
   Please answer questions for mbrsys filesystem creation.
   Press <1> to create a FAT16 filesystem, OS does not support FAT32: 1
   Creating bootable FAT16 filesystem.
   Copying system files from the floppy.
   All OK, press <Enter> to reboot:
   Rebooting...
   Booting from Hard Disk...
   Starting MS-DOS...


   MS-DOS Version 6.22


   C:\>_
   ```

7. Subsequent reboots will be faster and simpler, and they don't need the floppy image:

   ```
   SeaBIOS (version ...)
   Booting from Hard Disk...
   Starting MS-DOS...


   MS-DOS Version 6.22


   C:\>_
   ```

   The typical command you can try is `dir`.

   You can turn off the virtual machine at any time, there is no shoutdown
   procedure. mbrsys adds *o.com* to hard disk image. Just run `o` to do a
   power off, initiated from inside.

8. Please note that mbrsys doesn't do a full operating system installation.
   For that you still have to run `a:\\setup.exe` or `a:\\install.exe`, or
   boot from floppy. Advanced users may just copy files from the floppy
   image(s), and write their own *config.sys* and autoexec.bat*, without
   doing a proper installation.

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
Mtools `-i` flag (such as `-i myhd.img@@16384`), mbrsys creates the MBR
headers in a way that Mtools works with our without an offset.

Guest operating systems supported by mbrsys:

* MS-DOS 4.01--5.00--5.x--6.x--6.22.
* IBM PC DOS 4.01--5.00--5.x--6.x--7.0--2000--7.1.
* Windows 3.1: Boot to MS-DOS 6.22 (with mbrsys),  then run *setup.exe* of
  Windows 3.1.
* Windows 95--98--ME and community releases based on that. Windows ME is
  supported only in the multiboot.ru MSDOS8.ISO (get it from
  [here](http://www.multiboot.ru/download/)) MS-DOS 8.0 community release.
  It's possible to install the GUI by first booting to DOS mode (with
  mbrsys), and then running *setup.exe*.
* Windows XP: Boot to Windows 95 OSR2 or Windows 98 DOS mode (with mbrsys),
  then run *setup.exe* of Windows XP.
* FreeDOS 1.0--1.1--1.2--1.3--.
* SvarDOS 2024--. (This uses a fork of the EDR-DOS kernel.)
* TODO: Earlier versions of DR-DOS 7 and EDR-DOS.
* TODO: Datalight ROM-DOS.
* TODO: General Software Embedded DOS-ROM.

Emulators tested and working with mbrsys:

* QEMU (qemu-system-i386 and qemu-system-x86_64).
* VirtualBox.

mbrsys source and build details:

* Boot code is written in 16-bit 8086 assembly: NASM 0.98.39.
* Some library and low-level disk access code is written in 16-bit 8086
  assembly: NASM 0.98.39.
* Windows command-line tools (e.g. mkhd.exe) are written in 32-bit 386
  assembly: NASM 0.98.39.
* The installer which runs in the virtual machine at first boot is written
  in C targeting 16-bit 8086: OpenWatcom 2.0 C compiler wcc.exe.
