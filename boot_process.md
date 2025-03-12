# General BIOS (legacy) boot process

## Booting from hard disk

This section describe the BIOS boot process, also called the legacy boot
process, which has been the only way to boot from hard disk on the IBM PC
and compatibles, since the IBM PC/XT in 1983. (Since about 2004 there is a
new boot process called UEFI, and PC-compatible computers come with that
enabled. It also supports the GPT partition label format and secure boot.)

The BIOS boot process looks like:

1. The BIOS of the computer or the virtual machine detects and initilizes
   the hardware components, and decides to boot from the first attached hard
   disk. (Depending on its settings, the BIOS may decide to boot from floppy
   disk instead, or it may present a boot menu to the user, where the user
   can choose the boot device.)

2. The BIOS loads the first sector (offset 0 (LBA)) from the hard disk. This
   sector contains the partition table (up to 4 primary partitions) and the
   MBR boot code.

   For the purposes of the BIOS, each disk sector is 512 (== 0x200) bytes
   long.

   The BIOS loads the MBR (HDD sector 0 LBA) to absolute
   address 0x7c00 and jumps to 0:0x7c00 in (8086) real mode. The BIOS passes
   the boot drive number (typically 0x80 for the first hard disk drive) in
   register DL. See also [this
   section](https://pushbx.org/ecm/doc/ldosboot.htm#protocol-rombios-sector)
   for even more details.

3. The MBR boot code copies itself to somewhere else in memory, locates the
   first partition marked as active in the partition table, and loads its
   first sector, the boot sector. This sector contains typically contains
   filesystem headers and the bootsector boot code. The MBR boot code jumps
   to the boot sector boot code.

   For DOS on a hard disk, the filesystem type is usually FAT16. DOS
   filesystems smaller than ~32 MiB are usually of type FAT12. DOS
   filesystems larger than ~2 GiB must be of type FAT32, because DOS only
   supports FAT filesystems, and the maximum of FAT12 is ~32 MiB, and the
   maximum of FAT16 is ~2 GiB.

   For FAT12, FAT16, FAT32 and NTFS filesystems, the boot sector starts with
   a jump instruction, then it contains the filesystem headers (<~90 bytes),
   then it has the boot code. For these filesystems, some filesystem headers
   are also called the BIOS Parameter Block (BPB).

   The boot sector is loaded to absolute address 0x7c00, and
   then the MBR boot code jumps to 0:0x7c00, still in (8086) real mode. The
   MBR boot code MBR passes the boot drive number in register DL. There is no
   standard way to pass the partition number, some MBR code passes the
   address of the partition entry in DS:SI. Most DOS systems identify the
   partition by the *hidden sector count* field of the FAT BPB in the boot
   sector. See also [this
   section](https://pushbx.org/ecm/doc/ldosboot.htm#protocol-mbr-sector) for
   even more details.

4. The boot sector boot code typically locates the operating system kernel
   or loader files (names hardcoded in the boot sector) on the filesystem on
   the boot partition, loads these files, and jumps to one of them.

   For MS-DOS (including Windows 95--98--ME), the boot sector boot code
   loads the first 3 (or 4 for MS-DOS >=7.0) sectors from the file named
   *io.sys* to absolute address 0x700, and jumps to it (0x70:0 for MS-DOS
   <7.0 and 0x70:0x200 for MS-DOS >=7.0, both in (8086) real mode). For
   MS-DOS <7.0, the boot sector boot code also locates the file
   *msdos.sys* (and saves its FAT directory entry at absolute address 0x520,
   the start cluster number low word being at 0x53a and the high word being
   at 0x534, the latter for FAT32 only) in the root directory of the
   filesystem; *io.sys* code will load
   *msdos.sys* later. Some values are passed in registers, such as the boot
   drive number in DL, and other values are passed in memory The exact value
   passing protocol depends on the DOS version.. See also [this
   section](https://pushbx.org/ecm/doc/ldosboot.htm#protocol-sector-msdos6) and
   [this section](https://pushbx.org/ecm/doc/ldosboot.htm#protocol-sector-msdos7)
   for even more details.

   For IBM PC DOS and DR-DOS, the boot sector boot code loads the first 3
   sectors of the file named *ibmbio.com* to absolute address 0x700, and
   jumps to it (0x70:0 in (8086) real mode). The boot sector boot code also
   locates the file *ibmdos.com* (and saves its FAT directory entry at
   absolute address 0x520) in the root directory of the filesystem;
   *ibmbio.com* code will load *ibmdos.com* later. Some values are passed in
   registers, such as the boot drive number in DL, and other values are
   passed in memory.

   For Windows NT 3.1--4.0, Windows 2000 and Windows XP, the boot sector
   boot code loads the first sector of the file named *ntldr* to absolute
   address 0x20000, passes the boot drive number in DL, and jumps to
   0x2000:3 in (8086) real mode. Alternately, it's OK to to load the entire
   *ntldr* to the same address, and jump to 0x2000:0 instead.

5. If the first operating system kernel or loader files are only partially
   loaded, the the partially loaded part loads the rest of the file. This is
   needed because the boot sector (0x200 bytes minus the filesystem headers)
   is usually too short to load an entire file from the filesystem.

   For MS-DOS, IBM PC DOS and DR-DOS, the first 3 or 4 sectors of
   *io.sys* (or *ibmbio.com* for IBM PC DOS and DR-DOS) start with the
   code module named *msload* (see
   [bios/msload.asm](https://github.com/microsoft/MS-DOS/blob/2d04cacc5322951f187bb17e017c12920ac8ebe2/v4.0/src/BIOS/MSLOAD.ASM)
   in the MS-DOS 4.00 source code). *msload* copies itself to somewhere else
   in memory, then it loads the rest of the file to absolute address 0x700,
   then it jups to 0x70:0 in (8086) real mode. Some values are passed in
   registers, such as the boot drive number in DL, and other values are
   passed in memory. The exact value passing protocol depends on the DOS
   version. The size of *msload* (after which the kernel payload starts
   immediately), depends on the DOS version: for MS-DOS
   >=7.0, it's always 0x800 bytes, for everything else it's at <=0x600
   bytes, but shorter. For DOS >=4.00, the end of *msload* can be found like
   this: it's in front of the `"\xe9"` (jmp near) byte of the first
   `"\x0d\x0a\x00\xe9"` string within the first 0x600 bytes. Then the first
   3 bytes right after *msload* (*START$*) jump to the *INIT* function (see
   [bios/msinit.asm](https://github.com/microsoft/MS-DOS/blob/2d04cacc5322951f187bb17e017c12920ac8ebe2/v4.0/src/BIOS/MSINIT.ASM#L395)
   in the MS-DOS 4.00 source code).

   For Windows NT 3.1--4.0, Windows 2000--XP, the boot sector
   boot code loads and the first sector of the file named *ntldr* together
   load the rest of the *ntldr*, and then jump 0x2000:0 in (8086) real mode.
   The boot drive number in passed in register DL, the original boot sector
   remains at memory address 0x7c00, of which *ntldr* uses only the first
   0x24 (or even less, just the hidden sector count) to identify the boot
   partition.

6. The operating system kernel or loader files load more files (such as
   drivers and configuration files), detect hardware components, and
   continue the boot process accordingly.

   For MS-DOS <7.0, IBM PC DOS and DR-DOS, the second kernel file is loaded
   (MS-DOS: *msdos.sys*, IBM PC DOS and DR-DOS: *ibmdos.com*) before any
   other files.

   Then, for some DOS versions, the on-the-fly filesystem compression driver
   file (*dblspace.bin* or *drvspace.bin*) and its configuration file
   (*dblspace.ini* or *drvspace.ini*) are loaded, if present.

   Then, for MS-DOS, IBM PC DOS and DR-DOS, the configuration file
   *config.sys* is loaded (if present) and processed, and then the drivers
   mentioned there are loaded and initialized.

   Then, for MS-DOS, IBM PC DOS and DR-DOS, the command interpreter program
   file *command.com* is loaded and executed. *command.com* loads (if
   present) and runs the commands in *autoexec.bat*, and then enters the
   main loop. In each iteration of the main loop, *command.com* displays the
   prompt (typically on `C>` for DOS <6.0 or `C:\\>` for DOS >=6.0) on the
   console screen, reads a line of user input interactively (until the user
   presses *Enter*), and parses and exeutes that line as a command.

   For Windows NT--2000-XP the files *boot.ini*, *ntdetect.com* and
   *ntbootdd.sys* are loaded first, and then even more drivers (*.sys*
   files) etc.

## Booting from floppy disk

This is just like booting from hard disk (see above), with the following
differences:

* There is no MBR or partition table on the floppy disk, the filesystem
  starts (with its boot sector) right at the beginning.

* The BIOS loads the boot sector directly (same location: absolute address
  0x7c00), and jumps to it (same location: 0:0x7c00 in (8086) real mode),
  passing the boot drive number (typically 0 for the first floppy drive) in
  register DL.

* A useful subset of DOS typically fits to a single floppy disk, so it is
  directly usable from there, even if the system has no hard disk. However,
  real floppies (rather than emulated floppy images) are slow and
  error-prone, so since about 1985, DOS was typically booted and used from
  hard disk instead, and floppies were used only for the first installation
  of DOS to the computer, data transfer between computers and backups.

* Windows NT is able to boot from floppy disk, loading the files *ntldr*,
  *boot.ini*, and *ntdetect.com*, but the full the system is too large to
  fit on a floppy, so *boot.ini* points to a directory on a filesystem in a
  partition on a hard disk, thus from this point all other files will be
  loaded from that hard disk, and the boot floppy will be unused. All this
  is done rarely, typically for system rescue and recovery; typically,
  Windows NT is booted and used from hard disk, using floppies for data
  transfer between computers and backups.

* An emulated floppy disk is usually almost as fast as an emulated hard
  disk, except if the hard disk is much faster if it has some emulation
  acceleration (such as *virtio* in QEMU or Guest Additions in VirtualBox).
