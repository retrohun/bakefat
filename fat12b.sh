#! /bin/sh --
# by pts@fazekas.hu at Wed Jan 15 15:11:13 CET 2025
set -ex
test "$0" = "${0%/*}" || cd "${0%/*}"

for kib in 160 180 320 360 720 1200 1440 2880; do
  preset="${kib}K"
  nasm-0.98.39 -O0 -w+orphan-labels -f bin -o fd"$kib"k.img -DP_"$preset" fat12b.nasm
done

rm -f fda.img
cp -a fd1440k.img fda.img
#mdir -i fda.img  # To get the free space: 1457664 bytes.
mcopy -bsomp -i fda.img IO.SYS.fat2 ::IO.SYS
# io.sys must be unfragmented (at least in its first 3--4 sectors) for MS-DOS 6.22 and MS-DOS 7.x msload to load it.
# io.sys must be first for MS-DOS 6.22 boot sector (not ours) to boot.
mcopy -bsomp -i fda.img MSDOS.SYS ::MSDOS.SYS
mattrib -i fda.img +s ::IO.SYS ::MSDOS.SYS
mcopy -bsomp -i fda.img COMMAND.COM ::
printf 'SWITCHES=/F\r\n' >config.sys.msdos6  # To avoid the 2s delay at boot in MS-DOS 6.x: https://retrocomputing.stackexchange.com/a/31116/3494
touch -d '@1234567894' config.sys.msdos6  # Make the output of mcopy reproducible.
printf '@prompt $p$g\r\n@ver' >autoexec.bat  # MS-DOS 5.00 needs `prompt $p$g', MS-DOS 6.x doesn't.
touch -d '@1234567892' autoexec.bat # Make the output of mcopy reproducible.
mcopy -bsomp -i fda.img config.sys.msdos6 ::CONFIG.SYS  # To avoid the 2s delay at boot in MS-DOS 6.x: https://retrocomputing.stackexchange.com/a/31116/3494
mcopy -bsomp -i fda.img autoexec.bat ::AUTOEXEC.BAT  # Prevent the `date' and `time' prompt.
: qemu-system-i386 -M pc-1.0 -m 2 -nodefaults -vga cirrus -drive file=fda.img,format=raw,if=floppy -boot a

rm -f fdb.img
cp -a fd2880k.img fdb.img
#mdir -i fdb.img  # To get the free space: 2931712 bytes.
if false; then  # Works: crc32 random.bin
  mcopy -bsomp -i fdb.img IO.SYS.fat2 ::IO.SYS
  mcopy -bsomp -i fdb.img MSDOS.SYS ::MSDOS.SYS
  mcopy -bsomp -i fdb.img COMMAND.COM ::COMMAND.COM
elif true; then  # Works: crc32 random.bin
  mcopy -bsomp -i fdb.img IO.SYS.msdos500.fat2 ::IO.SYS
  mcopy -bsomp -i fdb.img MSDOS.SYS.msdos500 ::MSDOS.SYS
  mcopy -bsomp -i fdb.img COMMAND.COM.msdos500 ::COMMAND.COM
else  # It doesn't even boot, 2880K support was added in MS-DOS 5.00.
  mcopy -bsomp -i fdb.img IO.SYS.msdos401.fat2 ::IO.SYS
  mcopy -bsomp -i fdb.img MSDOS.SYS.msdos401 ::MSDOS.SYS
  mcopy -bsomp -i fdb.img COMMAND.COM.msdos401 ::COMMAND.COM
fi
mattrib -i fdb.img +s ::IO.SYS ::MSDOS.SYS
mcopy -bsomp -i fdb.img config.sys.msdos6 ::CONFIG.SYS  # To avoid the 2s delay at boot in MS-DOS 6.x: https://retrocomputing.stackexchange.com/a/31116/3494
mcopy -bsomp -i fdb.img autoexec.bat ::AUTOEXEC.BAT  # Prevent the `date' and `time' prompt.
mcopy -bsomp -i fdb.img crc32.com ::CRC32.COM  # Run in emulation: crc32	random.bin
mcopy -bsomp -i fdb.img random2880k.bin ::RANDOM.BIN
crc32 random2880k.bin
: qemu-system-i386 -M pc-1.0 -m 2 -nodefaults -vga cirrus -drive file=fdb.img,format=raw,if=floppy -boot a

rm -f fdc.img
cp -a fd1440k.img fdc.img
msd=1
#mdir -i fdc.img  # To get the free space: 1457664 bytes.
if false; then  # Works: crc32 random.bin
  mcopy -bsomp -i fdc.img IO.SYS.fat2 ::IO.SYS
  mcopy -bsomp -i fdc.img MSDOS.SYS ::MSDOS.SYS
  mcopy -bsomp -i fdc.img COMMAND.COM ::COMMAND.COM
elif false; then  # Works: crc32 random.bin
  mcopy -bsomp -i fdc.img IO.SYS.msdos500.fat2 ::IO.SYS
  mcopy -bsomp -i fdc.img MSDOS.SYS.msdos500 ::MSDOS.SYS
  mcopy -bsomp -i fdc.img COMMAND.COM.msdos500 ::COMMAND.COM
elif false; then  # Works: crc32 random.bin
  mcopy -bsomp -i fdc.img IO.SYS.msdos401.fat2 ::IO.SYS
  mcopy -bsomp -i fdc.img MSDOS.SYS.msdos401 ::MSDOS.SYS
  mcopy -bsomp -i fdc.img COMMAND.COM.msdos401 ::COMMAND.COM
elif false; then  # Works: crc32 random.bin
  mcopy -bsomp -i fdc.img IO.SYS.msdos330.fat2 ::IO.SYS
  mcopy -bsomp -i fdc.img MSDOS.SYS.msdos330 ::MSDOS.SYS
  mcopy -bsomp -i fdc.img COMMAND.COM.msdos330 ::COMMAND.COM
elif false; then  # !! smaller crc Works: crc32 random.bin
  # !! IO.SYS.win98cdn7.1app doesn't boot from floppy.
  #mcopy -bsomp -i fdc.img IO.SYS.win98cdn7.1app ::IO.SYS
  #mcopy -bsomp -i fdc.img COMMAND.COM.win98cdn7.1 ::COMMAND.COM
  mcopy -bsomp -i fdc.img IO.SYS.win98se ::IO.SYS
  mcopy -bsomp -i fdc.img COMMAND.COM.win98se ::COMMAND.COM
  msd=
elif true; then  # !! smaller crc Works: crc32 random.bin
  mcopy -bsomp -i fdc.img IO.SYS.msdos8 ::IO.SYS
  mcopy -bsomp -i fdc.img COMMAND.COM.msdos8 ::COMMAND.COM
  msd=
else  # It doesn't even boot, 1440K support was added in MS-DOS 3.30.
  mcopy -bsomp -i fdc.img IO.SYS.msdos320.fat2 ::IO.SYS
  mcopy -bsomp -i fdc.img MSDOS.SYS.msdos320 ::MSDOS.SYS
  mcopy -bsomp -i fdc.img COMMAND.COM.msdos320 ::COMMAND.COM
fi
test -z "$msd" || mattrib -i fdc.img +s ::IO.SYS ::MSDOS.SYS
mcopy -bsomp -i fdc.img config.sys.msdos6 ::CONFIG.SYS  # To avoid the 2s delay at boot in MS-DOS 6.x: https://retrocomputing.stackexchange.com/a/31116/3494
mcopy -bsomp -i fdc.img autoexec.bat ::AUTOEXEC.BAT  # Prevent the `date' and `time' prompt.
mcopy -bsomp -i fdc.img crc32.com ::CRC32.COM  # Run in emulation: crc32	random.bin
test -z "$msd" || mcopy -bsomp -i fdc.img random1440k.bin ::RANDOM.BIN
crc32 random1440k.bin
#dd if="$HOME"/Downloads/bootdisks/by_pts/windows-98-se-no-cd.img of=fdc.img bs=2 skip=31 seek=31 count=225 conv=sync,notrunc  # Use the Windows 98 SE boot sector.
: qemu-system-i386 -M pc-1.0 -m 2 -nodefaults -vga cirrus -drive file=fdc.img,format=raw,if=floppy -boot a

rm -f fdd.img
cp -a fd1200k.img fdd.img
msd=1
#mdir -i fdd.img  # To get the free space: 1457664 bytes.
if false; then  # Works: crc32 random.bin
  mcopy -bsomp -i fdd.img IO.SYS.fat2 ::IO.SYS
  mcopy -bsomp -i fdd.img MSDOS.SYS ::MSDOS.SYS
  mcopy -bsomp -i fdd.img COMMAND.COM ::COMMAND.COM
elif false; then  # Works: crc32 random.bin
  mcopy -bsomp -i fdd.img IO.SYS.msdos500.fat2 ::IO.SYS
  mcopy -bsomp -i fdd.img MSDOS.SYS.msdos500 ::MSDOS.SYS
  mcopy -bsomp -i fdd.img COMMAND.COM.msdos500 ::COMMAND.COM
elif false; then  # Works: crc32 random.bin
  mcopy -bsomp -i fdd.img IO.SYS.msdos401.fat2 ::IO.SYS
  mcopy -bsomp -i fdd.img MSDOS.SYS.msdos401 ::MSDOS.SYS
  mcopy -bsomp -i fdd.img COMMAND.COM.msdos401 ::COMMAND.COM
elif true; then  # Works: crc32 random.bin
  mcopy -bsomp -i fdd.img IO.SYS.msdos330.fat2 ::IO.SYS
  mcopy -bsomp -i fdd.img MSDOS.SYS.msdos330 ::MSDOS.SYS
  mcopy -bsomp -i fdd.img COMMAND.COM.msdos330 ::COMMAND.COM
elif false; then  # !! smaller crc Works: crc32 random.bin
  # !! IO.SYS.win98cdn7.1app doesn't boot from floppy.
  #mcopy -bsomp -i fdd.img IO.SYS.win98cdn7.1app ::IO.SYS
  #mcopy -bsomp -i fdd.img COMMAND.COM.win98cdn7.1 ::COMMAND.COM
  mcopy -bsomp -i fdd.img IO.SYS.win98se ::IO.SYS
  mcopy -bsomp -i fdd.img COMMAND.COM.win98se ::COMMAND.COM
  msd=
elif false; then  # !! smaller crc Works: crc32 random.bin
  mcopy -bsomp -i fdd.img IO.SYS.msdos8 ::IO.SYS
  mcopy -bsomp -i fdd.img COMMAND.COM.msdos8 ::COMMAND.COM
  msd=
else  # It doesn't boot, because it uses an earlier load protocol (without msload at the begining of io.sys).
  mcopy -bsomp -i fdd.img IO.SYS.msdos320.fat2 ::IO.SYS
  mcopy -bsomp -i fdd.img MSDOS.SYS.msdos320 ::MSDOS.SYS
  mcopy -bsomp -i fdd.img COMMAND.COM.msdos320 ::COMMAND.COM
fi
test -z "$msd" || mattrib -i fdd.img +s ::IO.SYS ::MSDOS.SYS
mcopy -bsomp -i fdd.img config.sys.msdos6 ::CONFIG.SYS  # To avoid the 2s delay at boot in MS-DOS 6.x: https://retrocomputing.stackexchange.com/a/31116/3494
mcopy -bsomp -i fdd.img autoexec.bat ::AUTOEXEC.BAT  # Prevent the `date' and `time' prompt.
mcopy -bsomp -i fdd.img crc32.com ::CRC32.COM  # Run in emulation: crc32	random.bin
#mdir -i fdd.img  # To get the free space.
test -z "$msd" || mcopy -bsomp -i fdd.img random1200k.bin ::RANDOM.BIN
crc32 random1200k.bin
#dd if="$HOME"/Downloads/bootdisks/by_pts/windows-98-se-no-cd.img of=fdd.img bs=2 skip=31 seek=31 count=225 conv=sync,notrunc  # Use the Windows 98 SE boot sector.
#dd if=msd320.good.bs.bin of=fdd.img bs=2 skip=31 seek=31 count=225 conv=sync,notrunc  # Use MS-DOS 3.20 boot sector.
#dd if=msd320.good.bs.bin of=fdd.img bs=512 count=1 conv=sync,notrunc  # Use MS-DOS 3.20 boot sector.
: qemu-system-i386 -M pc-1.0 -m 2 -nodefaults -vga cirrus -drive file=fdd.img,format=raw,if=floppy -boot a

rm -f fde.img
cp -a fd720k.img fde.img
msd=1
#mdir -i fde.img  # To get the free space: 1457664 bytes.
if false; then  # Works: crc32 random.bin
  mcopy -bsomp -i fde.img IO.SYS.fat2 ::IO.SYS
  mcopy -bsomp -i fde.img MSDOS.SYS ::MSDOS.SYS
  mcopy -bsomp -i fde.img COMMAND.COM ::COMMAND.COM
elif false; then  # Works: crc32 random.bin
  mcopy -bsomp -i fde.img IO.SYS.msdos500.fat2 ::IO.SYS
  mcopy -bsomp -i fde.img MSDOS.SYS.msdos500 ::MSDOS.SYS
  mcopy -bsomp -i fde.img COMMAND.COM.msdos500 ::COMMAND.COM
elif false; then  # Works: crc32 random.bin
  mcopy -bsomp -i fde.img IO.SYS.msdos401.fat2 ::IO.SYS
  mcopy -bsomp -i fde.img MSDOS.SYS.msdos401 ::MSDOS.SYS
  mcopy -bsomp -i fde.img COMMAND.COM.msdos401 ::COMMAND.COM
elif true; then  # Works: crc32 random.bin
  mcopy -bsomp -i fde.img IO.SYS.msdos330.fat2 ::IO.SYS
  mcopy -bsomp -i fde.img MSDOS.SYS.msdos330 ::MSDOS.SYS
  mcopy -bsomp -i fde.img COMMAND.COM.msdos330 ::COMMAND.COM
elif false; then  # !! smaller crc Works: crc32 random.bin
  # !! IO.SYS.win98cdn7.1app doesn't boot from floppy.
  #mcopy -bsomp -i fde.img IO.SYS.win98cdn7.1app ::IO.SYS
  #mcopy -bsomp -i fde.img COMMAND.COM.win98cdn7.1 ::COMMAND.COM
  mcopy -bsomp -i fde.img IO.SYS.win98se ::IO.SYS
  mcopy -bsomp -i fde.img COMMAND.COM.win98se ::COMMAND.COM
  msd=
elif false; then  # !! smaller crc Works: crc32 random.bin
  mcopy -bsomp -i fde.img IO.SYS.msdos8 ::IO.SYS
  mcopy -bsomp -i fde.img COMMAND.COM.msdos8 ::COMMAND.COM
  msd=
elif false; then  # !! smaller crc Works: crc32 random.bin
  mcopy -bsomp -i fde.img IBMBIO.COM.pcdos71 ::IBMBIO.COM
  mcopy -bsomp -i fde.img IBMDOS.COM.pcdos71 ::IBMDOS.COM
  mcopy -bsomp -i fde.img COMMAND.COM.pcdos71 ::COMMAND.COM
  msd=
elif true; then  # !! smaller crc Works: crc32 random.bin
  mcopy -bsomp -i fde.img IBMBIO.COM.pcdos70 ::IBMBIO.COM
  mcopy -bsomp -i fde.img IBMDOS.COM.pcdos70 ::IBMDOS.COM
  mcopy -bsomp -i fde.img COMMAND.COM.pcdos70 ::COMMAND.COM
  msd=
else  # It doesn't boot, because it uses an earlier load protocol (without msload at the begining of io.sys).
  mcopy -bsomp -i fde.img IO.SYS.msdos320.fat2 ::IO.SYS
  mcopy -bsomp -i fde.img MSDOS.SYS.msdos320 ::MSDOS.SYS
  mcopy -bsomp -i fde.img COMMAND.COM.msdos320 ::COMMAND.COM
fi
test -z "$msd" || mattrib -i fde.img +s ::IO.SYS ::MSDOS.SYS
mcopy -bsomp -i fde.img config.sys.msdos6 ::CONFIG.SYS  # To avoid the 2s delay at boot in MS-DOS 6.x: https://retrocomputing.stackexchange.com/a/31116/3494
mcopy -bsomp -i fde.img autoexec.bat ::AUTOEXEC.BAT  # Prevent the `date' and `time' prompt.
mcopy -bsomp -i fde.img crc32.com ::CRC32.COM  # Run in emulation: crc32	random.bin
#mdir -i fde.img  # To get the free space.
test -z "$msd" || mcopy -bsomp -i fde.img random720k.bin ::RANDOM.BIN
crc32 random720k.bin
#dd if="$HOME"/Downloads/bootdisks/by_pts/windows-98-se-no-cd.img of=fde.img bs=2 skip=31 seek=31 count=225 conv=sync,notrunc  # Use the Windows 98 SE boot sector.
#dd if=msd320.good.bs.bin of=fde.img bs=2 skip=31 seek=31 count=225 conv=sync,notrunc  # Use MS-DOS 3.20 boot sector.
#dd if=msd320.good.bs.bin of=fde.img bs=512 count=1 conv=sync,notrunc  # Use MS-DOS 3.20 boot sector.
: qemu-system-i386 -M pc-1.0 -m 2 -nodefaults -vga cirrus -drive file=fde.img,format=raw,if=floppy -boot a

: "$0" OK.
