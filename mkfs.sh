#! /bin/sh --
# by pts@fazekas.hu at Wed Dec 25 13:47:54 CET 2024
set -ex
test "$0" = "${0%/*}" || cd "${0%/*}"

nasm-0.98.39 -O0 -w+orphan-labels -f bin -o boot.bin boot.nasm
#nasm-0.98.39 -O0 -w+orphan-labels -f bin -o boot.bin -l boot.lst boot.nasm
nasm-0.98.39 -O0 -w+orphan-labels -f bin -o iboot.bin iboot.nasm

rm -f fat12.img
# -a: prevent alignment sectors to cluster size.
mkfs.vfat -a -C -D 0 -f 2 -F 12 -i abcd1234 -r 16 -R 1 -s 8 -S 512 --invariant fat12.img 140
printf 'Hello, World!\r\n' >hi.txt
# Without MTOOLS_SKIP_CHECK=1: Total number of sectors (280) not a multiple of sectors per track (32)!
MTOOLS_SKIP_CHECK=1 mcopy -bsomp -i fat12.img hi.txt ::HI.TXT
MTOOLS_SKIP_CHECK=1 mcopy -bsomp -i fat12.img hi.txt ::HI2.TXT

nasm-0.98.39           -O0 -w+orphan-labels -f bin -o IO.SYS.fat1 patchio622.nasm
nasm-0.98.39 -DNOPATCH -O0 -w+orphan-labels -f bin -o IO.SYS.fat2 patchio622.nasm
cmp IO.SYS IO.SYS.fat2  # Must be identical.

nasm-0.98.39           -O0 -w+orphan-labels -f bin -o IO.SYS.msdos401.fat1 patchio401.nasm  # No room to patch in place.
#!!cat MSLOAD.COM.msdos500.fat1 v401_src_plain/BIN2/MSBIO.BIN >IO.SYS.msdos401.fat1a
cmp IO.SYS.msdos401.fat1a IO.SYS.msdos401.fat1
touch -r v401_src_plain/BIN2/MSBIO.BIN IO.SYS.msdos401.fat1
nasm-0.98.39 -DNOPATCH -O0 -w+orphan-labels -f bin -o IO.SYS.msdos401.fat2 patchio401.nasm
cmp IO.SYS.msdos401 IO.SYS.msdos401.fat2  # Must be identical.

nasm-0.98.39           -O0 -w+orphan-labels -f bin -o IO.SYS.msdos500.fat1 patchio500.nasm
nasm-0.98.39 -DNOPATCH -O0 -w+orphan-labels -f bin -o IO.SYS.msdos500.fat2 patchio500.nasm
cmp IO.SYS.msdos500 IO.SYS.msdos500.fat2  # Must be identical.

nasm-0.98.39           -O0 -w+orphan-labels -f bin -o IBMBIO.COM.pcdos71.fat1 patchib71.nasm
nasm-0.98.39 -DNOPATCH -O0 -w+orphan-labels -f bin -o IBMBIO.COM.pcdos71.fat2 patchib71.nasm
cmp IBMBIO.COM.pcdos71 IBMBIO.COM.pcdos71.fat2  # Must be identical.

#nasm-0.98.39 -DFAT_COUNT=1 -O0 -w+orphan-labels -f bin -o fat16m.bin fat16m.nasm  # Supported by Windows 95 DOS mode, not supported by MS-DOS 6.22. Supported by patched MS-DOS 5.00 and 6.22.
nasm-0.98.39 -DFAT_COUNT=2 -DNEW_FAT16_BS -O0 -w+orphan-labels -f bin -o fat16m.bin fat16m.nasm  # Supported by Windows 95 DOS mode, also by MS-DOS 6.22, also by MS-DOS 5.00.
#nasm-0.98.39 -DFAT_COUNT=2 -DFAT_CLUSTER_COUNT=0x7ffe -DFAT_SECTORS_PER_CLUSTER=8 -O0 -w+orphan-labels -f bin -o fat16m.bin fat16m.nasm  # Works on MS-DOS 4.01. !! It looks like FAT_SECTORS_PER_CLUSTER<=8 is needed by MS-DOS 4.01 !! Is this because reserved sector count is not 1? Change it.
#nasm-0.98.39 -DFAT_COUNT=2 -DFAT_CLUSTER_COUNT=0xffee -DFAT_SECTORS_PER_CLUSTER=8 -O0 -w+orphan-labels -f bin -o fat16m.bin fat16m.nasm  # Works on MS-DOS 4.01. !! This (-DFAT_CLUSTER_COUNT=0xffee) also works in MS-DOS 4.01 for reading. But can it boot from it? Yes, the patched MS-DOS 4.01, with a warning: WARNING! SHARE should be loaded for large media. What about the original?
#nasm-0.98.39 -O0 -w+orphan-labels -f bin -o fat16m.bin fat16m.nasm
# rm -f fat16.img && mkfs.vfat -a -C -D 0 -f 1 -F 16 -i abcd1234 -r 128 -R 57 -s 64 -S 512 -h 63 --invariant fat16.img 2096766

rm -f hda.img
truncate -s 2155216896 hda.img  # !! Magic size value for QEMU, see what.txt.
dd if=fat16m.bin bs=65536 of=hda.img conv=notrunc,sparse
mdir -i hda.img
#mcopy -bsomp -i hda.img IO.SYS ::  # Must be first for MS-DOS 6.22 boot sector to boot.
rm -f big.dat
#truncate -s 0 big.dat
#truncate -s 1966080000 big.dat  # Works without the `div 63' bugfix.
#truncate -s 2129920000 big.dat
#truncate -s 2146697216 big.dat
#mcopy -bsomp -i hda.img big.dat ::BIG.DAT
: >empty.dat
touch -d '@1234567890' empty.dat  # Make the output of mcopy reproducible.
printf 'Hello, World!\r\n' >hi.dat
touch -d '@1234567898' hi.dat  # Make the output of mcopy reproducible.
printf 'SWITCHES=/F\r\n' >config.sys.msdos6  # To avoid the 2s delay at boot in MS-DOS 6.x: https://retrocomputing.stackexchange.com/a/31116/3494
touch -d '@1234567894' config.sys.msdos6  # Make the output of mcopy reproducible.
printf '@prompt $p$g\r\n@ver' >autoexec.bat  # MS-DOS 5.00 needs `prompt $p$g', MS-DOS 6.x doesn't.
touch -d '@1234567892' autoexec.bat # Make the output of mcopy reproducible.
touch -r IO.SYS IO.SYS.fat1  # Make the output of mcopy reproducible.
export TZ=GMT  # Make the output of mcopy reproducible.
mcopy -bsomp -i hda.img hi.dat ::E0
mcopy -bsomp -i hda.img hi.dat ::E1
mcopy -bsomp -i hda.img hi.dat ::E2
mcopy -bsomp -i hda.img hi.dat ::E3
mcopy -bsomp -i hda.img hi.dat ::E4
mcopy -bsomp -i hda.img hi.dat ::E5
mcopy -bsomp -i hda.img IO.SYS.fat1 ::IO.SYS  # Must be first for MS-DOS 6.22 boot sector to boot.
mattrib -i hda.img +s ::IO.SYS  # !! First 3 sectors must be contiguous for booting MS-DOS 6.22.
mcopy -bsomp -i hda.img hi.dat ::E6
mcopy -bsomp -i hda.img hi.dat ::E7
if true; then
  mcopy -bsomp -i hda.img hi.dat ::E8
  mcopy -bsomp -i hda.img hi.dat ::E9
  mcopy -bsomp -i hda.img hi.dat ::E10
  mcopy -bsomp -i hda.img hi.dat ::E11
  mcopy -bsomp -i hda.img hi.dat ::E12
  mcopy -bsomp -i hda.img hi.dat ::E13
  mcopy -bsomp -i hda.img hi.dat ::E14
  mcopy -bsomp -i hda.img hi.dat ::E15
  mcopy -bsomp -i hda.img hi.dat ::E16
  mcopy -bsomp -i hda.img hi.dat ::E17
  mcopy -bsomp -i hda.img hi.dat ::E18
fi
mcopy -bsomp -i hda.img MSDOS.SYS ::  # Must be first for MS-DOS 6.22 boot sector to boot.
mattrib -i hda.img +s ::MSDOS.SYS  # !! It's ok if not contiguous for booting MS-DOS 6.22, but may be needed for earlier versions of DOS.
mcopy -bsomp -i hda.img config.sys.msdos6 ::CONFIG.SYS  # To avoid the 2s delay at boot in MS-DOS 6.x: https://retrocomputing.stackexchange.com/a/31116/3494
mcopy -bsomp -i hda.img autoexec.bat ::AUTOEXEC.BAT  # Prevent the `date' and `time' prompt.
mcopy -bsomp -i hda.img COMMAND.COM ::
mdir -i hda.img -a

nasm-0.98.39 -DFAT_COUNT=2 -DFAT_SECTORS_PER_CLUSTER=1 -O0 -w+orphan-labels -f bin -o fat16m.bin fat16m.nasm
rm -f hdb.img
truncate -s 42069504 hdb.img  # (66102+255*63) sectors. !! Maybe QEMU needs less padding (just +16*63). What about VirtualBox?
dd if=fat16m.bin bs=65536 of=hdb.img conv=notrunc,sparse
mcopy -bsomp -i hdb.img empty.dat ::E0
mcopy -bsomp -i hdb.img empty.dat ::E1
mcopy -bsomp -i hdb.img empty.dat ::E2
mcopy -bsomp -i hdb.img IO.SYS.fat1 ::IO.SYS  # Must be first for MS-DOS 6.22 boot sector to boot.
mattrib -i hdb.img +s ::IO.SYS  # !! First 3 sectors must be contiguous for booting MS-DOS 6.22.
mcopy -bsomp -i hdb.img MSDOS.SYS ::  # Must be first for MS-DOS 6.22 boot sector to boot.
mattrib -i hdb.img +s ::MSDOS.SYS  # !! It's ok if not contiguous for booting MS-DOS 6.22, but may be needed for earlier versions of DOS.
mcopy -bsomp -i hdb.img COMMAND.COM ::

nasm-0.98.39 -DFAT_COUNT=2 -DFAT_SECTORS_PER_CLUSTER=2 -O0 -w+orphan-labels -f bin -o fat16m.bin fat16m.nasm
rm -f hdc.img
truncate -s 75614720 hdc.img  # (131620+255*63) sectors. !! Maybe QEMU needs less padding (just +16*63). What about VirtualBox?
dd if=fat16m.bin bs=65536 of=hdc.img conv=notrunc,sparse
mcopy -bsomp -i hdc.img empty.dat ::E0
mcopy -bsomp -i hdc.img empty.dat ::E1
mcopy -bsomp -i hdc.img IO.SYS.fat1 ::IO.SYS  # Must be first for MS-DOS 6.22 boot sector to boot.
mattrib -i hdc.img +s ::IO.SYS  # !! First 3 sectors must be contiguous for booting MS-DOS 6.22.
mcopy -bsomp -i hdc.img empty.dat ::E2
mcopy -bsomp -i hdc.img empty.dat ::E3
mcopy -bsomp -i hdc.img empty.dat ::E4
mcopy -bsomp -i hdc.img MSDOS.SYS ::  # Must be first for MS-DOS 6.22 boot sector to boot.
mattrib -i hdc.img +s ::MSDOS.SYS  # !! It's ok if not contiguous for booting MS-DOS 6.22, but may be needed for earlier versions of DOS.
mcopy -bsomp -i hdc.img COMMAND.COM ::

nasm-0.98.39 -DFAT_COUNT=1 -DFAT_SECTORS_PER_CLUSTER=2 -DNEW_FAT16_BS -O0 -w+orphan-labels -f bin -o fat16m.bin fat16m.nasm
rm -f hdd.img
truncate -s 75614720 hdd.img  # (131620+255*63) sectors. !! Maybe QEMU needs less padding (just +16*63). What about VirtualBox?
dd if=fat16m.bin bs=65536 of=hdd.img conv=notrunc,sparse
mcopy -bsomp -i hdd.img hi.dat ::E0
mcopy -bsomp -i hdd.img hi.dat ::E1
mcopy -bsomp -i hdd.img IBMBIO.COM.pcdos71.fat1 ::IBMBIO.COM  # Must be first for MS-DOS 6.22 boot sector to boot.
mattrib -i hdd.img +s ::IBMBIO.COM  # !! First 3 sectors must be contiguous for booting MS-DOS 6.22.
mcopy -bsomp -i hdd.img hi.dat ::E2
mcopy -bsomp -i hdd.img hi.dat ::E3
mcopy -bsomp -i hdd.img hi.dat ::E4
mcopy -bsomp -i hdd.img IBMDOS.COM ::  # Must be first for MS-DOS 6.22 boot sector to boot.
mattrib -i hdd.img +s ::IBMDOS.COM  # !! It's ok if not contiguous for booting MS-DOS 6.22, but may be needed for earlier versions of DOS.
mcopy -bsomp -i hdd.img config.sys.msdos6 ::CONFIG.SYS  # To avoid the 2s delay at boot: https://retrocomputing.stackexchange.com/a/31116/3494
mcopy -bsomp -i hdd.img autoexec.bat ::AUTOEXEC.BAT  # Prevent the `date' and `time' prompt.
mcopy -bsomp -i hdd.img COMMANDI.COM ::COMMAND.COM

nasm-0.98.39 -DFAT_COUNT=2 -DFAT_SECTORS_PER_CLUSTER=1 -DNEW_FAT16_BS -O0 -w+orphan-labels -f bin -o fat16m.bin fat16m.nasm
rm -f hde.img
truncate -s 75614720 hde.img  # (131620+255*63) sectors. !! Maybe QEMU needs less padding (just +16*63). What about VirtualBox?
dd if=fat16m.bin bs=65536 of=hde.img conv=notrunc,sparse
mcopy -bsomp -i hde.img empty.dat ::E0
mcopy -bsomp -i hde.img empty.dat ::E1
mcopy -bsomp -i hde.img IO.SYS.win95osr2 ::IO.SYS
#mcopy -bsomp -i hde.img IO.SYS.win98se ::IO.SYS
mattrib -i hde.img +s ::IO.SYS
mcopy -bsomp -i hde.img empty.dat ::E2
mcopy -bsomp -i hde.img empty.dat ::E3
mcopy -bsomp -i hde.img empty.dat ::E4
mcopy -bsomp -i hde.img MSDOS.SYS.win95 ::MSDOS.SYS  # BootDelay=0 in MSDOS.SYS to avoid the 2s delay at boot. Windows 98 ignores BootDelay=, and never delays.
mattrib -i hde.img +s ::MSDOS.SYS
mcopy -bsomp -i hde.img COMMAND.COM.win95osr2 ::COMMAND.COM
#mcopy -bsomp -i hde.img COMMAND.COM.win98se ::COMMAND.COM

nasm-0.98.39 -DFAT_COUNT=2 -DFAT_SECTORS_PER_CLUSTER=2 -O0 -w+orphan-labels -f bin -o fat16m.bin fat16m.nasm
rm -f hdf.img
truncate -s 75614720 hdf.img  # (131620+255*63) sectors. !! Maybe QEMU needs less padding (just +16*63). What about VirtualBox?
dd if=fat16m.bin bs=65536 of=hdf.img conv=notrunc,sparse
mcopy -bsomp -i hdf.img empty.dat ::E0
mcopy -bsomp -i hdf.img empty.dat ::E1
mcopy -bsomp -i hdf.img IO.SYS.msdos8 ::IO.SYS
#mcopy -bsomp -i hdf.img IO.SYS ::IO.SYS
mattrib -i hdf.img +s ::IO.SYS
mcopy -bsomp -i hdf.img empty.dat ::E2
mcopy -bsomp -i hdf.img empty.dat ::E3
mcopy -bsomp -i hdf.img empty.dat ::E4
mcopy -bsomp -i hdf.img COMMAND.COM.msdos8 ::COMMAND.COM
# Make it work with *.winme. Do we need MSDOS.INI?

nasm-0.98.39 -DFAT_COUNT=1 -DFAT_SECTORS_PER_CLUSTER=2 -O0 -w+orphan-labels -f bin -o fat16m.bin fat16m.nasm  # Patched IO.SYS.msdos500.fat1 supports -DFAT_COUNT=1.
rm -f hdg.img
truncate -s 75614720 hdg.img  # (131620+255*63) sectors. !! Maybe QEMU needs less padding (just +16*63). What about VirtualBox?
dd if=fat16m.bin bs=65536 of=hdg.img conv=notrunc,sparse
mcopy -bsomp -i hdg.img hi.dat ::E0
mcopy -bsomp -i hdg.img hi.dat ::E1
mcopy -bsomp -i hdg.img IO.SYS.msdos500.fat1 ::IO.SYS
mattrib -i hdg.img +s ::IO.SYS
mcopy -bsomp -i hdg.img hi.dat ::E2
mcopy -bsomp -i hdg.img hi.dat ::E3
mcopy -bsomp -i hdg.img hi.dat ::E4
mcopy -bsomp -i hdg.img MSDOS.SYS.msdos5 ::MSDOS.SYS
mattrib -i hdg.img +s ::MSDOS.SYS
mcopy -bsomp -i hdg.img autoexec.bat ::AUTOEXEC.BAT  # Prevent the `date' and `time' prompt.
mcopy -bsomp -i hdg.img COMMAND.COM.msdos5 ::COMMAND.COM

nasm-0.98.39 -DFAT_COUNT=1 -DFAT_SECTORS_PER_CLUSTER=2 -O0 -w+orphan-labels -f bin -o fat16m.bin fat16m.nasm
rm -f hdh.img
truncate -s 75614720 hdh.img  # (131620+255*63) sectors. !! Maybe QEMU needs less padding (just +16*63). What about VirtualBox?
# !! Why is this error message displayed by IO.SYS at boot time, even for small HDD image? WARNING! SHARE should be loaded for large media
dd if=fat16m.bin bs=65536 of=hdh.img conv=notrunc,sparse
mcopy -bsomp -i hdh.img hi.dat ::E0  # !! Replacing empty.dat with hi.dat would make the boot of MS-DOS 4.01 IO.SYS fail (but the patched IO.SYS.msdos401.fat1 is fine). That's because msload of MS-DOS 4.01 expects io.sys at cluster 2.
mcopy -bsomp -i hdh.img hi.dat ::E1
mcopy -bsomp -i hdh.img IO.SYS.msdos401.fat1 ::IO.SYS
mattrib -i hdh.img +s ::IO.SYS
mcopy -bsomp -i hdh.img hi.dat ::E2
mcopy -bsomp -i hdh.img hi.dat ::E3
mcopy -bsomp -i hdh.img hi.dat ::E4
mcopy -bsomp -i hdh.img COMMAND.COM.msdos401 ::COMMAND.COM
mcopy -bsomp -i hdh.img MSDOS.SYS.msdos401 ::MSDOS.SYS
mattrib -i hdh.img +s ::MSDOS.SYS
mcopy -bsomp -i hdh.img autoexec.bat ::AUTOEXEC.BAT  # Prevent `date' and `time' prompt.

nasm-0.98.39 -DFAT_32=1 -DFAT_COUNT=1 -DFAT_SECTORS_PER_CLUSTER=8 -DFAT_CLUSTER_COUNT=0x3fffe -O0 -w+orphan-labels -f bin -o fat16m.bin fat16m.nasm
rm -f hdi.img
truncate -s 1200M hdi.img  # !! Make the imege smaller.
dd if=fat16m.bin bs=65536 of=hdi.img conv=notrunc,sparse
mcopy -bsomp -i hdi.img empty.dat ::E0
mcopy -bsomp -i hdi.img empty.dat ::E1
mcopy -bsomp -i hdi.img IO.SYS.win95osr2 ::IO.SYS
#mcopy -bsomp -i hdi.img IO.SYS.win98se ::IO.SYS
#mcopy -bsomp -i hdi.img IO.SYS.msdos8 ::IO.SYS
mattrib -i hdi.img +s ::IO.SYS
mcopy -bsomp -i hdi.img empty.dat ::E2
mcopy -bsomp -i hdi.img empty.dat ::E3
mcopy -bsomp -i hdi.img empty.dat ::E4
mcopy -bsomp -i hdi.img MSDOS.SYS.win95 ::MSDOS.SYS  # BootDelay=0 in MSDOS.SYS to avoid the 2s delay at boot. Windows 98 ignores BootDelay=, and never delays.
mattrib -i hdi.img +s ::MSDOS.SYS
mcopy -bsomp -i hdi.img COMMAND.COM.win95osr2 ::COMMAND.COM
#mcopy -bsomp -i hdi.img COMMAND.COM.win98se ::COMMAND.COM
#mcopy -bsomp -i hdi.img COMMAND.COM.msdos8 ::COMMAND.COM

nasm-0.98.39 -DFAT_32=1 -DFAT_COUNT=1 -DFAT_SECTORS_PER_CLUSTER=2 -DFAT_CLUSTER_COUNT=0x3fffe -O0 -w+orphan-labels -f bin -o fat16m.bin fat16m.nasm
rm -f hdj.img
truncate -s 306M hdj.img  # !! Make the imege smaller.
dd if=fat16m.bin bs=65536 of=hdj.img conv=notrunc,sparse
mcopy -bsomp -i hdj.img empty.dat ::E0
mcopy -bsomp -i hdj.img empty.dat ::E1
#mcopy -bsomp -i hdj.img IO.SYS.win95osr2 ::IO.SYS
#mcopy -bsomp -i hdj.img IO.SYS.win98se ::IO.SYS
mcopy -bsomp -i hdj.img IO.SYS.msdos8 ::IO.SYS
mattrib -i hdj.img +s ::IO.SYS
mcopy -bsomp -i hdj.img empty.dat ::E2
mcopy -bsomp -i hdj.img empty.dat ::E3
mcopy -bsomp -i hdj.img empty.dat ::E4
mcopy -bsomp -i hdj.img MSDOS.SYS.win95 ::MSDOS.SYS  # BootDelay=0 in MSDOS.SYS to avoid the 2s delay at boot. Windows 98 ignores BootDelay=, and never delays.
mattrib -i hdj.img +s ::MSDOS.SYS
#mcopy -bsomp -i hdj.img COMMAND.COM.win95osr2 ::COMMAND.COM
#mcopy -bsomp -i hdj.img COMMAND.COM.win98se ::COMMAND.COM
mcopy -bsomp -i hdj.img COMMAND.COM.msdos8 ::COMMAND.COM

#nasm-0.98.39 -DFAT_32=1 -DFAT_COUNT=1 -DFAT_SECTORS_PER_CLUSTER=2 -DFAT_CLUSTER_COUNT=0x3fffe -O0 -w+orphan-labels -f bin -o fat16m.bin fat16m.nasm
if true; then
  nasm-0.98.39 -DFAT_32=1 -DFAT_COUNT=1 -DFAT_SECTORS_PER_CLUSTER=2 -DFAT_CLUSTER_COUNT=0x3fffe -O0 -w+orphan-labels -f bin -o fat16m.bin fat16m.nasm
  rm -f hdk.img
  truncate -s 306M hdk.img  # !! Make the imege smaller.
  dd if=fat16m.bin bs=65536 of=hdk.img conv=notrunc,sparse
#  mcopy -bsomp -i hdk.img empty.dat ::E0
#  mcopy -bsomp -i hdk.img empty.dat ::E1
  mcopy -bsomp -i hdk.img IBMBIO.COM.pcdos71.fat1 ::IBMBIO.COM  # Must be first for MS-DOS 6.22 boot sector to boot.
  mattrib -i hdk.img +s ::IBMBIO.COM  # !! First 3 sectors must be contiguous for booting MS-DOS 6.22.
#  mcopy -bsomp -i hdk.img empty.dat ::E2
#  mcopy -bsomp -i hdk.img empty.dat ::E3
#  mcopy -bsomp -i hdk.img empty.dat ::E4
  mcopy -bsomp -i hdk.img IBMDOS.COM ::  # Must be first for MS-DOS 6.22 boot sector to boot.
  mattrib -i hdk.img +s ::IBMDOS.COM  # !! It's ok if not contiguous for booting MS-DOS 6.22, but may be needed for earlier versions of DOS.
  mcopy -bsomp -i hdk.img COMMANDI.COM ::COMMAND.COM
  mcopy -bsomp -i hdk.img config.sys.msdos6 ::CONFIG.SYS  # To avoid the 2s delay at boot: https://retrocomputing.stackexchange.com/a/31116/3494
  mcopy -bsomp -i hdk.img autoexec.bat ::AUTOEXEC.BAT  # Prevent the `date' and `time' prompt.
else
  nasm-0.98.39 -DFAT_32=1 -DFAT_COUNT=1 -DFAT_SECTORS_PER_CLUSTER=2 -DFAT_CLUSTER_COUNT=0x3fffe -O0 -w+orphan-labels -f bin -o fat16m.bin fat16m.nasm
  rm -f hdk.img
  truncate -s 306M hdk.img  # !! Make the imege smaller.
  dd if=fat16m.bin bs=65536 of=hdk.img conv=notrunc,sparse
  # !! The IBM PC DOS 7.1 FAT32 boot sector doesn't support files before ibmbio.com.
  #mcopy -bsomp -i hdk.img empty.dat ::E0
  #mcopy -bsomp -i hdk.img empty.dat ::E1
  mcopy -bsomp -i hdk.img IBMBIO.COM.pcdos71.fat1 ::IBMBIO.COM  # Must be first for MS-DOS 6.22 boot sector to boot.
  mattrib -i hdk.img +s ::IBMBIO.COM  # !! First 3 sectors must be contiguous for booting MS-DOS 6.22.
  # !! The IBM PC DOS 7.1 FAT32 boot sector doesn't support files before ibmdos.com (except for ibmbio.com).
  #mcopy -bsomp -i hdk.img empty.dat ::E2
  #mcopy -bsomp -i hdk.img empty.dat ::E3
  #mcopy -bsomp -i hdk.img empty.dat ::E4
  mcopy -bsomp -i hdk.img IBMDOS.COM ::  # Must be first for MS-DOS 6.22 boot sector to boot.
  mattrib -i hdk.img +s ::IBMDOS.COM  # !! It's ok if not contiguous for booting MS-DOS 6.22, but may be needed for earlier versions of DOS.
  mcopy -bsomp -i hdk.img COMMANDI.COM ::COMMAND.COM
  mcopy -bsomp -i hdk.img config.sys.msdos6 ::CONFIG.SYS  # To avoid the 2s delay at boot: https://retrocomputing.stackexchange.com/a/31116/3494
  mcopy -bsomp -i hdk.img autoexec.bat ::AUTOEXEC.BAT  # Prevent the `date' and `time' prompt.
  dd bs=1 if=pcdos71-fat32-bs.bin count=422 of=hdk.img skip=90 seek=32346 conv=notrunc  # Use the IBM PC DOS 7.1 FAT32 boot sector.
fi

: "$0" OK.
