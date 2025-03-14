.PHONY: release clean

CONFFLAGS =   # Example: make CONFFLAGS=-DDEBUG=1
RELEASE = bakefat.lf3 bakefat.exe bakefat.darwinc32 bakefat.darwinc64
EXTRA = bakefat bakefat.gcc bakefat.ow.exe bakefat.com bakefat.minicc
PTS_OSXCROSS = "${HOME}"/Downloads/pts_osxcross_10.10
CC = cc
GCC = gcc
NASM = nasm
OWCC = owcc

# This is the simple, non-optimizing, architecture-independent, non-cross-compile build. Needed: NASM and any C compiler.
bakefat: bakefat.c boot.nasm fat12b.nasm bin2h.c
# boot.nasm includes fat12b.bin.
	$(NASM) -O0 -o boot.bin boot.nasm
	$(CC) -o bin2h bin2h.c
	./bin2h boot.bin boot.h
	$(CC) -DCONFIG_INCLUDE_BOOT_BIN $(CONFFLAGS) -o bakefat bakefat.c

# This is the GCC (or Clang), simple, architecture-independent, cross-compile build. Needed: NASM and GCC.
bakefat.gcc: bakefat.c boot.nasm fat12b.nasm
# boot.nasm includes fat12b.bin.
	$(NASM) -O0 -o boot.bin boot.nasm
	$(GCC) -ansi -pedantic -W -Wall -s -O2 -DCONFIG_INCBIN_BOOT_BIN $(CONFFLAGS) -o bakefat.gcc bakefat.c

release: $(RELEASE)
extra: $(EXTRA)

bakefat.lf3: bakefat.c boot.nasm fat12b.nasm mmlibcc.sh mmlibc386.nasm mmlibc386.h  # Linux i386 and FreeBSD i386.
	./mmlibcc.sh $(CONFFLAGS) -o bakefat.lf3 bakefat.c boot.nasm

bakefat.exe: bakefat.c boot.nasm fat12b.nasm mmlibcc.sh mmlibc386.nasm mmlibc386.h  # Win32 .exe program.
	./mmlibcc.sh -bwin32 $(CONFFLAGS) -o bakefat.exe bakefat.c boot.nasm

bakefat.minicc: bakefat.c boot.nasm fat12b.nasm
	minicc -Wno-n201 $(CONFFLAGS) -o bakefat.minicc bakefat.c boot.nasm

bakefat.ow.exe: bakefat.c boot.nasm fat12b.nasm  # Win32 .exe program.
	$(NASM) -O0 -f obj -o boot.obj boot.nasm
	$(OWCC) -bwin32 -Wl,runtime -Wl,console=3.10 -s -Os -fno-stack-check -march=i386 -W -Wall -Wno-n201 $(CONFFLAGS) -o bakefat.exe bakefat.c boot.obj

bakefat.com: bakefat.c boot.nasm fat12b.nasm  # DOS 8086 .com program.
	$(NASM) -O0 -f obj -DUSE32= -o boot.obj boot.nasm
	$(OWCC) -bcom -s -Os -fno-stack-check -march=i86 -W -Wall -Wno-n201 $(CONFFLAGS) -o bakefat.com bakefat.c boot.obj

bakefat.darwinc32: bakefat.c boot.nasm fat12b.nasm
# boot.nasm includes fat12b.bin.
	tools/nasm-0.98.39.upx -O0 -w+orphan-labels -f bin $(CONFFLAGS) -o boot.bin boot.nasm
# awk gsub(...) in the newer busybox is buggy, use $busybox1 instead.
	$(PTS_OSXCROSS)/i386-apple-darwin14/bin/gcc -mmacosx-version-min=10.5 -march=i686 -nodefaultlibs -lSystem -O2 -ansi -pedantic -W -Wall -DCONFIG_INCBIN_BOOT_BIN $(CONFFLAGS) -o bakefat.darwinc32 bakefat.c
	$(PTS_OSXCROSS)/i386-apple-darwin14/bin//strip bakefat.darwinc32

bakefat.darwinc64: bakefat.c boot.nasm fat12b.nasm
# boot.nasm includes fat12b.bin.
	tools/nasm-0.98.39.upx -O0 -w+orphan-labels -f bin -o boot.bin boot.nasm
	$(PTS_OSXCROSS)/x86_64-apple-darwin14/bin/gcc -mmacosx-version-min=10.5 -nodefaultlibs -lSystem -O2 -ansi -pedantic -W -Wall -DCONFIG_INCBIN_BOOT_BIN $(CONFFLAGS) -o bakefat.darwinc64 bakefat.c
	$(PTS_OSXCROSS)/x86_64-apple-darwin14/bin/strip bakefat.darwinc64

# FYI to convert boot.bin --> boot.od --> boot.h:
#
#   tools/busybox-1.37.0w od -An -to1 -v boot.bin >boot.od
#   # awk gsub(...) in the newer busybox is buggy, use $busybox1 instead.
#   tools/busybox-minicc-1.21.1.upx awk -f od2h.awk <boot.od >boot.h

clean:
	rm -f bakefat.o bakefat.obj bakefat.sym boot.bin boot.od boot.h boot.obj bin2h $(EXTRA) $(RELEASE)
