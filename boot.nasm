;
; boot.nasm: boot code (MBR, FAT16 boot sectors and FAT32 boot sector)
; by pts@fazekas.hu at Thu Dec 26 01:51:51 CET 2024
;
; Compile with: nasm -w+orphan-labels -f bin -o boot.bin boot.nasm
; Minimum NASM version required to compile: 0.98.39
;
; See fat16m.nasm for more docs and TODOs.
;
; MS-DOS 4.01--6.22 (and PC-DOS 4.01--7.1) boot process from HDD:
;
; * The BIOS loads the MBR (HDD sector 0 LBA) to 0x7c00 and jumps to
;   0:0x7c00. The BIOS passes .drive_number (typically 0x80) in register DL.
;   See also https://pushbx.org/ecm/doc/ldosboot.htm#protocol-rombios-sector
; * The MBR contains the boot code and the partition table (up to 4 primary
;   partitions).
; * The boot code in the MBR finds the first active partition, and loads its
;   boot sector (sector 0 of the partition) to jumps to 0:0x7c00. The boot
;   code in the MBR passes .drive_number in register DL.
;   See also https://pushbx.org/ecm/doc/ldosboot.htm#protocol-mbr-sector
; * In case of MS-DOS and PC-DOS the boot sector is the very first sector of
;   a FAT12 or FAT16 file system, and it starts with a jump instruction,
;   then it contains the FAT filesystem headers (i.e. BIOS Parameter Block,
;   BPB), then it contains the boot code.
; * The boot code in the boot sector (msboot, MS-DOS source:
;   boot/msboot.asm) finds io.sys in the root directory (and it saves the
;   directory entry to 0x500), msdos.sys (and it saves the directory entry
;   to 0x520), loads the first 3 sectors of io.sys (i.e. msload) to 0x700,
;   and jumps to 0x70:0. msboot passes .drive_number in DL,
;   .media_descriptor (media byte) in CH, sector number of the first cluster
;   (cluster 2) in AX:BX.
;   See also https://pushbx.org/ecm/doc/ldosboot.htm#protocol-sector-msdos6
; * msload (MS-DOS source: bios/msload.asm) loads the rest of io.sys
;   (msbio.bin) to 0x700 (using the start cluster number put at 0x51a by
;   msboot), and jumps to 0x70:0. The file start offset of msbio.bin within
;   io.sys depends on the DOS version. It's the \xe9 (jmp near) byte of the
;   first \x0d\x0a\x00\xe9 string within the first 0x600 bytes of io.sys.
;   msload passes DL, CH, AX and BX as above.
; * The first 3 bytes of msbio.bin (START$) jump to the INIT function.
; * The INIT function (part of MS-DOS source: bios/msinit.asm) loads
;   msdos.sys (using the start cluster number put at 0x53a by msboot). It
;   starts with the cluster number in the root directory (already load by
;   msboot to word [0x53a] == word [0x520+0x1a]).
; * DOS processes config.sys, loading additional drivers.
; * DOS loads command.com.
; * command.com processes autoexec.bat.
; * command.com displays the prompt (e.g. `C>` or `C:\>`), and waits for
;   user input.
;

bits 16
cpu 8086
;org 0x7c00  ; Independent.

%macro assert_fofs 1
  times +(%1)-($-$$) times 0 nop
  times -(%1)+($-$$) times 0 nop
%endm
%macro assert_at 1
  times +(%1)-$ times 0 nop
  times -(%1)+$ times 0 nop
%endm

PSTATUS:  ; Partition status.
.ACTIVE equ 0x80

BOOT_SIGNATURE equ 0xaa55  ; dw.

%macro fat_header 8  ; %1: .reserved_sector_count value; %2: .sector_count value; %3: .fat_count, %4: .sectors_per_cluster, %5: fat_sectors_per_fat, %6: fat_rootdir_sector_count, %7: fat_32 (0 for FAT16, 1 for FAT32), %8: partition_gap_sector_count.
; More info about FAT12, FAT16 and FAT32: https://en.wikipedia.org/wiki/Design_of_the_FAT_file_system
;
.header:	jmp strict short .boot_code
		nop  ; 0x90 for CHS. Another possible value is 0x0e for LBA. Who uses it? It is ignored by .boot_code.
assert_at .header+3
.oem_name:	db 'MSDOS5.0'
assert_at .header+0xb
.bytes_per_sector: dw 0x200  ; The value 0x200 is hardcoded in boot_sector.boot_code, both explicitly and implicitly.
assert_at .header+0xd
.sectors_per_cluster: db (%4)
assert_at .header+0xe
.reserved_sector_count: dw (%1)+(%8)
assert_at .header+0x10
.fat_count:	db (%3)  ; Must be 1 or 2. MS-DOS 6.22 supports only 2. Windows 95 DOS mode supports 1 or 2.
assert_at .header+0x11
.rootdir_entry_count: dw (%6)<<4  ; Each FAT directory entry is 0x20 bytes. Each sector is 0x200 bytes.
assert_at .header+0x13
%if (%7) || (((%2)+(%8))&~0xffff)
.sector_count_zero: dw 0  ; See true value in .sector_count.
%else
.sector_count_zero: dw (%2)+(%8)
%endif
assert_at .header+0x15
.media_descriptor: db 0xf8  ; 0xf8 for HDD.
assert_at .header+0x16
%if (%7)  ; FAT32.
.sectors_per_fat: dw 0
%else
.sectors_per_fat: dw (%5)
%endif
assert_at .header+0x18
; FreeDOS 1.2 `dir c:' needs a correct value for .sectors_per_track and
; .head_count. MS-DOS 6.22 and FreeDOS 1.3 ignore these values (after boot).
.sectors_per_track: dw 1  ; Track == cylinder. Dummy nonzero value to pacify mtools(1). Will be overwritten with value from BIOS int 13h AH == 8.
assert_at .header+0x1a
.head_count: dw 1  ; Dummy nonzero value to pacify mtools(1). Will be overwritten with value from BIOS int 13h AH == 8.
assert_at .header+0x1c
.hidden_sector_count: dd 0  ; Occupied by MBR and previous partitions. Will be overwritten with value from the partition entry: partition start sector offset. !! Does MS-DOS 6.22 use it outside boot (probably no)? Does FreeDOS use it (probably no).
assert_at .header+0x20
.sector_count: dd (%2)+(%8)
assert_at .header+0x24
.fstype_fat1x: equ .header+0x36
.fstype_fat32: equ .header+0x52
.drive_number_fat1x: equ .header+0x24
.drive_number_fat32: equ .header+0x40
%if (%7)  ; FAT32.
; B1G-4K based on: rm -f fat32.img && mkfs.vfat -a -C -D 0 -f 1 -F 32 -i abcd1234 -r 128 -R 17 -s 8 -S 512 -h 63 --invariant fat32.img 1049604
; -R >=16 for Windows NT installation, it modifies sector 8 when making the partition bootable.
.sectors_per_fat_fat32: dd (%5)
assert_at .header+0x28
.mirroring_flags: dw 0  ; As created by mkfs.vfat.
assert_at .header+0x2a
.version: dw 0
assert_at .header+0x2c
.rootdir_start_cluster: dd 2
assert_at .header+0x30
.fsinfo_sec_ofs: dw 1+(%8)
assert_at .header+0x32
.first_boot_sector_copy_sec_ofs: dw 6+(%8)  ; 6 was created by mkfs.vfat, also for Windows XP. 4 would also work. There are up to 3 sectors here. Windows XP puts some extra boot code to sector 8 (of 16).
assert_at .header+0x34
.reserved:	dd 0, 0, 0
assert_at .header+0x40
.drive_number: db 0x80
assert_at .header+0x41
.reserved2:	db 0
assert_at .header+0x42
.extended_boot_segnature: db 0x29
assert_at .header+0x43
.volume_id: dd 0x1234abcd  ; 1234-ABCD.
assert_at .header+0x47
.volume_label:	db 'NO NAME    '
assert_at .header+0x52
.fstype:	db 'FAT32   '
assert_at .header+0x5a
%else  ; Non-FAT32.
; Based on: truncate -s 2155216896 hda.img  # !! Magic size value for QEMU, see what.txt.
; Based on: rm -f fat16.img && mkfs.vfat -a -C -D 0 -f 1 -F 16 -i abcd1234 -r 128 -R 57 -s 64 -S 512 -h 63 --invariant fat16.img 2096766
assert_at .header+0x24
.drive_number: db 0x80
assert_at .header+0x25
.var_unused: db 0  ;.var_read_head: db 0  ; Can be used as a temporary variable in .boot_code.
assert_at .header+0x26
.extended_boot_segnature: db 0x29
assert_at .header+0x27
.volume_id: dd 0x1234abcd  ; 1234-ABCD.
assert_at .header+0x2b
.volume_label:	db 'NO NAME    '
assert_at .header+0x36
.fstype:	db 'FAT16   '
assert_at .header+0x3e
%endif
%endm

assert_fofs 0
mbr:  ; Master Boot record, sector 0 (LBA) of the drive.
; More info about the MBR: https://wiki.osdev.org/MBR_(x86)
; More info about the MBR: https://en.wikipedia.org/wiki/Master_boot_record
; More info about the MBR: https://en.wikipedia.org/wiki/Master_boot_record#BIOS_to_MBR_interface
; More info about the MBR: https://en.wikipedia.org/wiki/Master_boot_record#MBR_to_VBR_interface
; More info about the MBR: https://pushbx.org/ecm/doc/ldosboot.htm#protocol-rombios-sector
; MBR code: https://web.archive.org/web/20100117123431/https://mirror.href.com/thestarman/asm/mbr/Win2kmbr.htm
; MBR code: https://github.com/egormkn/mbr-boot-manager/blob/master/mbr.asm
; MBR code: https://prefetch.net/blog/2006/09/09/digging-through-the-mbr/
; MBR code: https://web.archive.org/web/20080312222741/http://ata-atapi.com/hiwmbr.htm
; It is unusual to have a FAT filesystem header in an MBR, but that's our main innovation to make `mdir -i hda.img` work.
fat_header 1, 0, 2, 1, 1, 1, 1, 0x3f  ; !! fat_reserved_sector_count, fat_sector_count, fat_fat_count, fat_sectors_per_cluster, fat_sectors_per_fat, fat_rootdir_sector_count, fat_32, partition_1_sec_ofs
.org: equ -0x7e00+.header
		times 0x5a-($-.header) db '+'  ; Pad FAT16 headers to the size of FAT32, for uniformity.
.boot_code:
.var_change: equ .header-2  ; db.
.var_bs_cyl_sec: equ .header-4  ; dw. CX value (cyl and sec) for int 13h AH == 2 and AH == 4.
.var_bs_drive_number: equ .header-5  ; db. DH value (drive number) for int 13h AH == 2 and AH == 4.
.var_bs_head: equ .header-6  ; db. DL value (head) for int 13h AH == 2 and AH == 4.
; This MBR .boot_code is smarter than typical MBR .boot code, because it
; ignores the CHS values in the partition table (and uses the LBA values
; instead), so that it remains independent of various LBA-to-CHS mappings in
; emulators such as QEMU.
;
; !! Does the Windows 95 MBR (`ms-sys -9`) also ignore the CHS value in the partition entry?
; !! Use LBA (EBIOS) is avaolable to boot from partitions starting above 8 GiB. Unfortunately, .write_boot_sector would break.
		cli
		xor ax, ax
		mov si, 0x7c00
		mov ss, ax
		mov sp, si
		sti
		cld
		push ss
		pop ds
		push ss
		pop es
		mov di, -.org+.header
		mov bp, di  ; BP := 0x7e00 (address of relocated MBR).
		mov cx, 0x100
		rep movsw  ; Copy MBR from 0:0x7c00 to 0:0x7e00.
		jmp 0:-.org+.after_code_copy
		; Fall through, but within the copy.
.after_code_copy:
;%define FORCE_CHS  ; Please note that there is no FORCE_LBA, because this mbr.boot_code calls .read_sector_chs directly.
%ifndef FORCE_CHS
		mov ah, 0x41  ; Check extensions (EBIOS). DL already contains the drive number.
		mov bx, 0x55aa
		int 0x13  ; BIOS syscall.
		jc .done_ebios	 ; No EBIOS.
		cmp bx, 0xaa55
		jne .done_ebios	 ; No EBIOS.
		ror cl, 1
		jnc .done_ebios	 ; No EBIOS.
		mov [bp-.header+.read_sector+1], al  ; Self-modifying code: change the `jmp short .read_sector_chs' at `.read_sector' to `jmp short .read_sector_lba'. (AL is still 0 here.)
%endif
.done_ebios:	xor di, di  ; Workaround for buggy BIOS. Also the 0 value will be used later.
		mov ah, 8  ; Read drive parameters.
		mov [bp-.header+.drive_number0], dl  ; .drive_number0 passed to the MBR .boot_code by the BIOS in DL.
		push dx
		int 13h  ; BIOS syscall.
		jc .jc_fatal1
		and cx, byte 0x3f
		mov [bp-.header+.sectors_per_track], cx
		mov dl, dh
		mov dh, 0
		inc dx
		mov [bp-.header+.head_count], dx
		mov ah, 1  ; Get status of last drive operation. Needed after the AH == 8 call.
		pop dx  ; mov dl, [bp-.header+.drive_number0]
		int 13h  ; BIOS syscall.

		mov si, -.org+.partition_1-0x10
		mov cx, 4  ; Try at most 4 partitions (that's how many fit to the partition table).
.next_partition:
		add si, byte 0x10
		cmp byte [si], PSTATUS.ACTIVE
		loopne .next_partition
		jne .fatal1
		; Now: SI points to the first active partition entry.
		mov ax, [si+8]    ; Low  word of sector offset (LBA) of the first sector of the partition.
		mov dx, [si+8+2]  ; High word of Sector offset (LBA) of the first sector of the partition.
		mov bx, sp  ; BX := 0x7c00. That's where we load the partition boot sector to.
		push di  ; .var_change := 0. DI is still 0.
		call .read_sector_chs  ; Ruins AX, CX and DX. Sets CX to CHS cyl_sec value. Sets DH to CHS head value. Sets DL to drive number.
		cmp word [0x7dfe], BOOT_SIGNATURE
		jne .fatal1
.jc_fatal1:	jc .fatal1  ; This never matches after the BOOT_SIGNATURE check, but it matches after `jc .jc_fatal1'.
		push cx  ; mov [bx-.header+.var_bs_cyl_sec], cx  ; Save it for a subsequent .write_boot_sector.
		push dx  ; mov [bx-.header+.var_bs_head], dh  ; mov [bx-.header+.var_bs_drive_number], dl  ; Save it for a subsequent .write_boot_sector.
		; Now fix some FAT12, FAT16 or FAT32 BPB fields
		; (.drive_number, .hidden_sector_count, .sectors_per_track
		; and .head_count) in the in-memory boot sector just loaded.
		;
		; This is to help our boot_sector.boot_code (and make room
		; for more code in our boot_sector), and also to help other
		; operating systems to boot (e.g. if a `sys c:' command has
		; overwritten our boot_sector.boot_code).
		;
		; We are a bit careful, and we don't fix anything if the BPB
		; doesn't indicate a FAT filesystem. That's because the user
		; may have created a different filesystem since the initial
		; boot.
		;
		; !! Write the changes back to the on-disk boot sector (and
		;    also to the on-disk MBR), in case an operating system
		;    reads it again. For example, `dir c:' in FreeDOS 1.0,
		;    1.1 and 1.2 (but not 1.3) needs a correct
		;    boot_sector.sectors_per_track and
		;    boot_sector.head_count, even if not booted from our HDD.
		; !! Write CHS values in the partition table back to the
		;    on-disk MBR. This is to make FreeDOS kernel display
		;    fewer warnings at boot time.
		;
		; !! Add code to reinstall our mbr.header and mbr.boot_code
		;    after an installer has overwritten it.
		mov cx, 1
		push si
		mov si, -.org+.drive_number0
		mov ax, 'FA'
		cmp [bx-.header+.fstype_fat1x], ax
		jne .no_fat1
		cmp word [bx-.header+.fstype_fat1x+2], 'T1'  ; Match 'FAT12' and 'FAT16'.
		je .fix_fat1
.no_fat1:	cmp [bx-.header+.fstype_fat32], ax
		jne .done_fatfix
		cmp word [bx-.header+.fstype_fat32+2], 'T3'  ; Match 'FAT32'. PC DOS 7.1 detects FAT32 by `cmp word [bx-.header+.sectors_per_fat], 0 ++ je .fat32'. More info: https://pushbx.org/ecm/doc/ldosboot.htm#protocol-sector-ibmdos
		jne .done_fatfix
.fix_fat32:	lea di, [bx-.header+.drive_number_fat32]
		call .change_bpb
		jmp short .fix_fat
.fix_fat1:	lea di, [bx-.header+.drive_number_fat1x]
		call .change_bpb
.fix_fat:	pop si
		push si
		add si, byte 8
		lea di, [bx-.header+.hidden_sector_count]
		mov cl, 4  ; 4 bytes.
		call .change_bpb  ; Copy to dword [bx-.header+.hidden_sector_count+2].
		mov si, -.org+.sectors_per_track
		lea di, [bx-.header+.sectors_per_track]
		mov cl, 4  ; 4 bytes.
		call .change_bpb  ; Copy to word [bx-.header+sectors_per_track] and then word [bx-.header+.head_count].
		pop si  ; Pass it to boot_sector.boot_code according to the load protocol.
.done_fatfix:	;mov dl, [bp-.header+.drive_number0]  ; No need for mov, DL still contains the drive number. Pass .drive_number0 to the boot sector .boot_code in DL.
		cmp [bx-.header+.var_change], ch  ; CH == 0.
		je .done_write
; Writes the boot sector at BX back to the partition.
; Inputs: ES:BX: buffer address, DL: .drive_number0.
; Ruins: AX, flags.
;
; We do this in case an operating system reads it again. For example, `dir
; c:' in FreeDOS 1.0, 1.1 and 1.2 (but not 1.3) needs a correct
; boot_sector.sectors_per_track and boot_sector.head_count, even if not
; booted from our HDD.
.write_boot_sector:
		mov ax, 0x301  ; AL == 1 means: read 1 sector.
		pop dx  ; Restore [bx-.header+.var_bs_head] to DH and [bx-.header+.var_bs_drive_number] to DL (unnecessary).
		pop cx  ; Restore [bx-.header+.var_bs_cyl_sec] to CX.
		int 0x13  ; BIOS syscall to write sectors.
		; Ignore failure in CL.
.done_write:	;mov byte [si], PSTATUS.ACTIVE  ; Fake active partition for boot sector. Not needed, we've already checked above.
		; Also pass pointer to the booting partition in DS:SI.
		;times 2 pop di  ; No need: the boot sector will set its own SS:SP.
		jmp 0:0x7c00  ; Jump to boot sector .boot_code.
		; Not reached.
.fatal1:	mov si, -.org+.errmsg_os
; Prints NUL-terminated message starting at SI, and halts.
;
; This is a library function which can be called from boot_sector.boot_code
; using `jmp strict near mbr.fatal+(.org-mbr.org)'. Of course, library
; functions in the boot sector only works if mbr.boot_code is not
; overwritten.
.fatal:
.next_msg_byte:	lodsb
		test al, al  ; Found terminating NUL?
		jz .halt
		mov ah, 0xe
		mov bx, 7
		int 0x10
		jmp short .next_msg_byte
.halt:		cli
.hang:		hlt
		jmp short .hang
; Changes the BPB in the boot sector just loaded.
; Inputs: SI: source buffer; DI: destination buffer; CX: number of bytes to change, must be positive.
; OutputS: CX: 0.
; Ruins: SI, DI.
.change_bpb:	cmpsb
		je .change_bpb_cont
		dec si
		dec di
		movsb
		inc byte [bx-.header+.var_change]
%if 0  ; Just for debugging.
		push ax
		push bx
		mov ax, 0xe00|'*'
		mov bx, 7
		int 0x10
		pop bx
		pop ax
%endif
.change_bpb_cont:
		loop .change_bpb
		ret

; Reads a single sector from the specified BIOS drive, using LBA (EBIOS) if available, otherwise falling back to CHS.
; Inputs: DX:AX: LBA sector number on the drive; ES:BX: points to read buffer.
; Output: DL: drive number. Halts on failures.
; Ruins: AX, CX, DX (output), flags.
;
; This is a library function which can be called from boot_sector.boot_code
; using `call mbr.read_sector+(.org-mbr.org)'. Of course, library
; functions in the boot sector only works if mbr.boot_code is not
; overwritten.
;
; When called as a library function, BP points to boot_sector (0x7c00).
; When called directly from the MBR, BP points to the relocated mbr
; (0x7e00). This discrepancy doesn't matter, because all the values used
; (.drive_number0, .sectors_per_track and .head_count) are at the same offset
; and have the same value. The boot_sector.boot_code must do a `mov
; [bp-.header+.drive_number0], dl' to make it work.
.read_sector:
		jmp short .read_sector_chs  ; Self-modifying code: EBIOS autodetection may change this to `jmp short .read_sector_lba' by setting byte [bp-.header+.read_sector+1] := 0.
		; Fall through to .read_sector_lba.

; Reads a single sector from the specified BIOS drive, using LBA (EBIOS).
; Inputs: DX:AX: LBA sector number on the drive; ES:BX: points to read buffer.
; Output: DL: drive number. Halts on failures.
; Ruins: AH, CX, DX (output), flags.
.read_sector_lba:
		push si
		; Construct .dap (Disk Address Packet) for BIOS int 13h AH == 42, on the stack.
		xor cx, cx
		push cx  ; High word of .dap_lba_high.
		push cx  ; Low word of .dap_lba_high.
		push dx  ; High word of .dap_lba.
		push ax  ; Low word of .dap_lba.
		push es  ; .dap_mem_seg.
		push bx  ; .dap_mem_ofs.
		inc cx
		push cx  ; .dap_sector_count := 1.
		mov cl, 0x10
		push cx  ; .dap_size := 0x10.
		mov si, sp
		mov ah, 0x42
.do_read:	mov dl, 0x80  ; Self-modifying code: drive number (.drive_number0) in this `mov' will be overwritten by self-modifying code.
.drive_number0:	equ $-1  ; db. Unlike .drive_number, this offset is independent of filesystem type (FAT16 or FAT32).
		int 0x13  ; BIOS syscall to read sectors.
.jc_fatal_disk:	mov si, -.org+.errmsg_disk
		jc .fatal
		add sp, byte 0x10  ; Pop the .dap and keep CF (indicates error).
		pop si
		ret

; Reads a single sector from the specified BIOS drive, using CHS.
; Inputs: DX:AX: LBA sector number on the drive; ES:BX: points to read buffer.
; Output: DL: drive number; CX: CHS cyl_sec value; DH: CHS head value. Halts on failures.
; Ruins: AX, CX (output), DH (output), flags.
.read_sector_chs:
		push bx  ; Save.
		mov bx, [bp-.header+.sectors_per_track]
		xchg cx, ax  ; CX := AX (save it for later), AX := junk.
		xor ax, ax
		cmp dx, bx
		jb .small
		xchg ax, dx
		div bx  ; We neeed this extra division if io.sys is near the end of the 2 GiB filesystem (with 32 KiB clusters, sectors_per_track==63, sector_number =~ 258+65518*64).
.small:		xchg ax, cx
		div bx
		xchg dx, cx
		inc cx  ; Like `inc cl`, but 1 byte shorter.
		mov bl, cl  ; BL := sec.
		; This also works:
		; mov cx, [bp-.header+.head_count]
		; div cx
		div word [bp-.header+.head_count]
		mov dh, dl  ; DH := head.
		xchg al, ah
		mov cl, 6
		shl al, cl
		xchg cx, ax  ; CX := AX; AX := junk.
		or cl, bl
		pop bx  ; Restore.
		mov ax, 0x201  ; AL == 1 means: read 1 sector.
		push si  ; Adapt to the .do_read ABI.
		sub sp, byte 0x10  ; Adapt to the .do_read ABI.
		jmp short .do_read

.errmsg_disk:	db 'Disk error', 0	
.errmsg_os:	db 'No OS', 0
		;Other typical error message: db 'Missing operating system', 0
		;Other typical error message: db 'Invalid partition table', 0
		;Other typical error message: db 'Error loading operating system', 0

		times 0x1b8-($-.header) db '-'  ; Padding.
assert_at .header+0x1b8
.disk_id_signature: dd 0x9876edcb
assert_at .header+0x1bc
.reserved_word_0: dw 0
.partition_1:
assert_at .header+0x1be  ; Partition 1.
		times 4*0x10 db 0 ; Partition table consisting of 4 primary partitions.
assert_at .header+0x1fe
.boot_signature: dw BOOT_SIGNATURE
assert_at .header+0x200

; ---

%macro fat_boot_sector_common 0
.org: equ -0x7c00+.header
.boot_code:
		mov bp, -.org+.header
		cli
		xor ax, ax
		mov ss, ax
		mov sp, bp
		mov ds, ax
		;mov es, ax  ; We set ES := 0 later for FAT16. FAT32 doesn't need it.
		cld
		sti
%endm  ; fat_boot_sector_common

; --- FAT16 boot sector.

; !! Provide the same code for any value of fat_sectors_per_cluster.
%macro fat16_boot_sector 1  ; %1: fat_sectors_per_cluster
		fat_header 1, 0, 2, (%1), 1, 1, 0, 0  ; !! fat_reserved_sector_count, fat_sector_count, fat_fat_count, fat_sectors_per_cluster, fat_sectors_per_fat, fat_rootdir_sector_count, fat_32, partition_1_sec_ofs
		fat_boot_sector_common
.new_dipt:  ; Disk initialization parameter table, a copy of int 1eh. !!
.var_clusters_sec_ofs: equ .header-4  ; dd. Sector offset (LBA) of the clusters (i.e. cluster 2) in this FAT filesystem, from the beginning of the drive.
.var_fat_sec_ofs: equ .boot_code+0xc+4  ; dd. Sector offset (LBA) of the first FAT in this FAT filesystem, from the beginning of the drive. Only used if .fat_sectors_per_cluster<4. !! Unify FAT16 and FAT32, don't need this.

		push ds
		pop es
		mov cx, [bp-.header+.sector_count_zero]
		test cx, cx  ; !! Unnecessary code, .sector_count_zero is always 0.
		jz .sc_saved
		mov [bp-.header+.sector_count], cx  ; !! Who uses this output? The MS-DOS kernel at boot time?
.sc_saved:	mov ax, 0x20  ; Size of a directory entry.
		mul word [bp-.header+.rootdir_entry_count]
		mov bx, 0x200  ; [bp-.header+.bytes_per_sector]  ; Hardcode 0x200.
		add ax, bx
		dec ax
		div bx
		; Now: AX == number of sectors in the root directory.
		xchg cx, ax  ; CX := AX (number of sectors in the root directory); AX := junk.
%if (%1)>=4
		xor ax, ax
		xor bx, bx
		mov al, [bp-.header+.fat_count]
		mul word [bp-.header+.sectors_per_fat]
		add ax, [bp-.header+.hidden_sector_count]
		adc dx, [bp-.header+.hidden_sector_count+2]
		add ax, [bp-.header+.reserved_sector_count]
		adc dx, bx
%else
		mov ax, [bp-.header+.reserved_sector_count]
		xor dx, dx
		add ax, [bp-.header+.hidden_sector_count]
		adc dx, [bp-.header+.hidden_sector_count+2]
		mov [bp-.header+.var_fat_sec_ofs], ax
		mov [bp-.header+.var_fat_sec_ofs+2], dx
		xor ax, ax
		mov al, [bp-.header+.fat_count]
		mul word [bp-.header+.sectors_per_fat]
		add ax, [bp-.header+.var_fat_sec_ofs]
		adc dx, [bp-.header+.var_fat_sec_ofs+2]
%endif
                ; Now: DX:AX == the sector offset (LBA) of the root directory in this FAT filesystem.
                push dx  ; Set initial value of var_clusters_sec_ofs+2.
                push ax  ; Set initial value of var_clusters_sec_ofs.
		add [bp-.header+.var_clusters_sec_ofs], cx
%if (%1)>=4
		adc [bp-.header+.var_clusters_sec_ofs+2], bx  ; BX == 0.
%else
		adc [bp-.header+.var_clusters_sec_ofs+2], byte 0
%endif
                ; Now: DX:AX == the sector offset (LBA) of the root directory in this FAT filesystem; CX == number of sectors in the root directory.
		mov bh, 3  ; BH := missing-filename-bitset (io.sys and msdos.sys).
.next_rootdir_sector:
		mov di, 0x700  ; DI := Destination address for .read_sector (== 0x700).
		xchg bx, di
		call .read_sector
		xchg bx, di
		mov di, 0x700
.next_entry:	push cx  ; Save.
		push di  ; Save.
		mov si, -.org+.io_sys
		mov cx, 11  ; .io_sys_end-.io_sys
		repe cmpsb
		jne .not_io_sys
		cmp [di-11+0x1c+2], cl  ; 0x1c is the offset of the dword-sized file size in the FAT directory entry.
		je .do_io_sys_or_ibmbio_com  ; Jump if file size of io.sys is shorter than 0x10000 bytes. This is true for MS-DOS v6 (e.g. 6.22), false for MS-DOS v7 (e.g. Windows 95).
		mov byte [bp-.header+.jmp_far_inst+2], 2  ; MS-DOS v7 load protocol wants `jmp 0x70:0x200', we set the 2 here.
		and bh, ~2  ; No need for msdos.sys.
.do_io_sys_or_ibmbio_com:
		mov di, 0x500  ; Load protocol: io.sys expects directory entry of io.sys at 0x500.
		and bh, ~1
		jmp short .copy_entry
.not_io_sys:
		pop di
		push di
		add si, cx  ; Assumes that .ibmbio_com follows .io_sys. mov si, -.org+.ibmbio_com
		mov cl, 11  ; .io_sys_end-.io_sys
		repe cmpsb
		je .do_io_sys_or_ibmbio_com
		pop di
		push di
		add si, cx  ; Assumes that .msdos_sys follows .ibmbio_com. Like this, but 1 byte shorter: mov si, -.org+.msdos_sys
		mov cl, 11  ; .msdos_sys_end-.msdos_sys  ; CH is already 0.
		repe cmpsb
		jne .not_msdos_sys
.do_msdos_sys_or_ibmdos_com:
		and bh, ~2
		mov di, 0x520  ; Load protocol: io.sys expects directory entry of msdos.sys at 0x520.
.copy_entry:	pop si
		push si
		mov cl, 0x10  ; CH is already 0.
		rep movsw
		jmp short .entry_done
.not_msdos_sys:
		pop di
		push di
		add si, cx  ; Assumes that .ibmdos_com follows .msdos_sys. mov si, -.org+.ibmdos_com
		mov cl, 11  ; .io_sys_end-.io_sys
		repe cmpsb
		je .do_msdos_sys_or_ibmdos_com
		; Fall through to .entry_done.
.entry_done:	pop di  ; Restore.
		pop cx  ; Restore the remaining number of rootdir sectors to read.
		;test bh, bh  ; Not needed, ZF is already correct because of `jne' or `and dh, ~...'.
		jz .found_both_sys_files
		add di, byte 0x20
		cmp di, 0x700+0x200
		jne .next_entry
		loop .next_rootdir_sector
		; Fall through to .fatal1.
.fatal1:	mov si, -.org+.errmsg
; Prints NUL-terminated message starting at SI, and halts.
.fatal:
		jmp strict near mbr.fatal+(.org-mbr.org)  ; Call library function within MBR, to save space. This one doesn't return.
		; Not reached.
.found_both_sys_files:
		mov ax, [0x51a]  ; AX := start cluster number of io.sys.
		push ax  ; Save it for MS-DOS v7 load protocol later.
		mov cl, 4  ; CX := Number of sectors to read from io.sys. (CH is already 0.) Only Windows ME needs 4. MS-DOS 6.22 needs only 3; Windows 98 SE already needs 3. Source code of these sectors: https://github.com/microsoft/MS-DOS/blob/main/v4.0/src/BIOS/MSLOAD.ASM
%if (%1)<4
		mov bx, 0x700  ; Destination address for .read_sector. CX sectors (see below) will be read to here consecutively.
		jmp short .have_cluster_in_ax
  %if (%1)==2
    .maybe_calc_next_cluster:
		cmp cl, 2  ; This value depends on the initial value of CL above.
		jne .read_next_sector_from_io_sys
  %endif
  .calc_next_cluster:
		push bx  ; Save.
		mov ax, [bp-.header+.var_fat_sec_ofs]
		mov dx, [bp-.header+.var_fat_sec_ofs+2]
		mov bx, di
		add al, bh
		adc ah, 0
		adc dx, byte 0
		mov bx, 0x7800  ; !! Add caching: don't load it if DX:AX was the same as above. (How many code bytes do we have for this?)
		call .read_sector
		mov bx, di
		mov bh, 0x78>>1  ; Base address will be 0x7800 after the `add bx, bx' below.
		add bx, bx
		mov ax, [bx]
		pop bx  ; Restore.
  .have_cluster_in_ax:
		mov di, ax  ; Save current cluster number for the next call to .calc_next_cluster.
  		xor dx, dx
		dec ax
		dec ax
%endif
%if (%1)==1
%elif (%1)==2
  		shl ax, 1
  		rcl dx, 1
%else
		dec ax
		dec ax
		mov bl, [bp-.header+.sectors_per_cluster]
		mov bh, 0
		mul bx
		mov bx, 0x700  ; Destination address for .read_sector. CX sectors (see below) will be read to here consecutively.
%endif
		add ax, [bp-.header+.var_clusters_sec_ofs]
		adc dx, [bp-.header+.var_clusters_sec_ofs+2]
		; Now: DX:AX == next to-read sector (LBA) of io.sys.
.read_next_sector_from_io_sys:
%if (%1)==1
		call .read_sector
		loop .calc_next_cluster
%elif (%1)==2
		call .read_sector
		loop .maybe_calc_next_cluster
%else
		call .read_sector
		loop .read_next_sector_from_io_sys
%endif
		mov dl, [bp-.header+.drive_number]
		; Fill registers according to MS-DOS v7 load protocol: https://pushbx.org/ecm/doc/ldosboot.htm#protocol-sector-msdos7
		pop di  ; DI = first cluster of load file if FAT12/FAT16; SI:DI = first cluster of load file if FAT32
		; Fill registers according to MS-DOS v6 load protocol: https://pushbx.org/ecm/doc/ldosboot.htm#protocol-sector-msdos6
		mov ch, [bp-.header+.media_descriptor]  ; Seems to be unused in MS-DOS 6.22 io.sys. MS-DOS 4.01 io.sys GOTHRD (in bios/msinit.asm) uses it, as media byte.
		pop bx  ; mov bx, [bp-.header+.var_clusters_sec_ofs]
		pop ax  ; mov ax, [bp-.header+.var_clusters_sec_ofs+2]
		; Fill registers according to MS-DOS v7 load protocol: https://pushbx.org/ecm/doc/ldosboot.htm#protocol-sector-msdos7
		; True by design: SS:BP -> boot sector with (E)BPB, typically at linear 0x7c00.
		push ax
		push bx  ; dword [ss:bp-4] = first data sector of first cluster, including hidden sectors.
		; (It's not modified by this boot sector.) Diskette Parameter Table (DPT) may be relocated, possibly modified. The DPT is pointed to by the interrupt 1eh vector. If dword [ss:sp] = 0000_0078h (far pointer to IVT 1eh entry), then dword [ss:sp+4] -> original DPT
		; !! Currently not: word [ss:bp+0x1ee] points to a message table. The format of this table is described in lDebug's source files msg.asm and boot.asm, around uses of the msdos7_message_table variable.

.jmp_far_inst:	jmp 0x70:0  ; Jump to boot code loaded from io.sys. The offset 0 has been changed to 0x200 for MS-DOS v7.
; Reads a single sector from drive. Halts with an error on failure.
; Inputs: DX:AX: sector number (LBA) on the drive; ES:BX: points to read buffer.
; Output: CF: indicates error. DX:AX: Incremented by 1. BX: incremented by 0x200.
; Ruins: flags.
.read_sector:
		push ax  ; Save.
		push dx  ; Save.
		push cx  ; Save.
		call mbr.read_sector+(.org-mbr.org)  ; Call library function within MBR, to save space.
		pop cx  ; Restore.
		pop dx  ; Restore.
		pop ax  ; Restore.
		add ax, byte 1
		adc dx, byte 0
		add bh, 2  ; add bx, [bp-.header+.bytes_per_sector]  ; Hardcoded 0x200.
		ret

.errmsg:	db 'Error loading DOS from FAT16.', 0
.io_sys:	db 'IO      SYS'  ; Must be followed by .ibmbio_com in memory.
.io_sys_end:
.ibmbio_com:	db 'IBMBIO  COM'  ; Must be followed by .msdos_sys in memory.
.ibmbio_com_end:
.msdos_sys:	db 'MSDOS   SYS'  ; Must be followed by .ibmdos_com in memory.
.msdos_sys_end:
.ibmdos_com:	db 'IBMDOS  COM'  ; Must follow .ibmdos_com in memory.
.ibmdos_com_end:

		times 0x1fe-($-.header) db '-'  ; Padding.
.boot_signature: dw BOOT_SIGNATURE
assert_at .header+0x200
%endm

assert_fofs 0x200
boot_sector_fat16_fspc1:
		fat16_boot_sector 1  ; fat_sectors_per_cluster.

assert_fofs 0x400
boot_sector_fat16_fspc2:
		fat16_boot_sector 2  ; fat_sectors_per_cluster.

assert_fofs 0x600
boot_sector_fat16_fspc4:
		fat16_boot_sector 4  ; fat_sectors_per_cluster.

; --- FAT32 boot sector.
;
; Features and requirements:
;
; * It is able to boot io.sys from Windows 95 OSR2 (earlier versions of
;   Windows 95 didn't support FAT32), Windows 98 FE, Windows 98 SE, and the
;   unofficial MS-DOS 8.0 (MSDOS8.ISO on http://www.multiboot.ru/download/)
;   based on Windows ME.
; * With some additions (in the future), it may be able to boot IBM PC DOS
;   7.1 (ibmbio.com and ibmdos.com), FreeDOS (kernel.sys), SvarDOS
;   (kernel.sys), EDR-DOS (drbio.sys), Windows NT 3.x (ntldr), Windows NT
;   4.0 (ntldr), Windows 2000 (ntldr), Windows XP (ntldr).
; * Autodetects EBIOS (LBA) and uses it if available. Otherwise it falls
;   back to CHS. LBA is for >8 GiB HDDs, CHS is for maximum compatibility
;   with old (before 1996) PC BIOS.
; * All the boot code fits to the boot sector (512 bytes). No need for
;   loading a sector 2 or 3 like how Windows 95--98--ME--XP boots.
; * Works with a 8086 CPU (no need for 386). (It's 25 bytes longer than
;   the 386 implementation).
; * Can boot only io.sys with the MS-DOS v7 protocol.
;   !! Add support for PC-DOS 7.10 (ibmbio.com and imbdos.com), maybe
;      concatenate them to io.sys. Is it even bootable on its own?
;
; History:

; * Based on the FreeDOS FAT32 boot sector.
; * Modified heavily by Eric Auer and Jon Gentle in July 2003.
; * Modified heavily by Tinybit in February 2004.
; * Snapshotted code starting at *Entry_32* in stage2/grldrstart.S in
;   grub4dos-0.4.6a-2024-02-26, by pts.
; * Adapted to the MS-DOS v7 load protocol (moved away from the
;   GRLDR--NTLDR load protocol) by pts in January 2025.
;
; You can use and copy source code and binaries under the terms of the
; GNU Public License (GPL), version 2 or newer. See www.gnu.org for more.
;
; Memory layout:
;
; * 0...0x400: Interrupt table.
; * 0x400...0x500: BIOS data area.
; * 0x500...0x700: Unused.
; * 0x700...0xf00: 4 sectors loaded from io.sys.
; * 0xf00...0x1100: Sector read from the FAT32 FAT.
; * 0x1100..0x7b00: Unused.
; * 0x7b00...0x7c00: Stack used by this boot sector.
; * 0x7c00...0x7e00: This boot sector.

assert_fofs 0x800
boot_sector_fat32:
		fat_header 1, 0, 2, 1, 1, 1, 1, 0  ; !! fat_reserved_sector_count, fat_sector_count, fat_fat_count, fat_sectors_per_cluster, fat_sectors_per_fat, fat_rootdir_sector_count, fat_32, partition_1_sec_ofs
		fat_boot_sector_common
.var_fat_sector: equ .header+0x44  ; last accessed FAT sector (dd) (overwriting unused bytes).
.var_fat_start: equ .header+0x48  ; first FAT sector (dd) (overwriting unused bytes).
.var_data_start: equ .header-4  ; first data sector (dd) (overwriting unused bytes).

		;mov [bp-.header+.drive_number], dl  ; MBR has passed drive number in CL. Our mbr.boot_code has also passed it in byte [bsXDrive].

		; Figure out where FAT and data areas start.
		mov [bp-.header+.var_fat_sector], ax   ; Assume AX == 0. Init buffer status.
		mov [bp-.header+.var_fat_sector+2], ax ; Assume AX == 0. Init buffer status.
		xchg dx, ax  ; DX := AX; AX := junk.
		mov ax, [bp-.header+.reserved_sector_count]
		add ax, [bp-.header+.hidden_sector_count]
		adc dx, [bp-.header+.hidden_sector_count+2]
		mov [bp-.header+.var_fat_start], ax
		mov [bp-.header+.var_fat_start+2], dx
		xor cx, cx
		mov cl, [bp-.header+.fat_count]
.add_fat:	add ax, [bp-.header+.sectors_per_fat_fat32]
		adc dx, [bp-.header+.sectors_per_fat_fat32+2]
		loop .add_fat
		push dx
		push ax  ; dword [bp-.header+.var_data_start] := DX:AX.

; Searches for the file in the root directory.
; Returns: EAX = first cluster of file
		mov ax, [bp-.header+.rootdir_start_cluster]
		mov dx, [bp-.header+.rootdir_start_cluster+2]

.next_rootdir_cluster:
		push dx
		push ax  ; Save cluster number (DX:AX).
		call .cluster_to_lba  ; Also sets CL to [bp-.header+.sectors_per_cluster].
		jnc .rootdir_cluster_ok
		mov si, -.org+.errmsg_missing   ; EOC in rootdir cluster. This means that kernel file was not found.
		jmp strict near mbr.fatal+(.org-mbr.org)  ; Call library function within MBR, to save space. This one doesn't return.
.rootdir_cluster_ok:  ; Now: CL is sectors per cluster; EAX is sector number.

.read_rootdir_sector:
		mov bx, 0x70  ; Load kernel (io.sys) starting at 0x70:0 (== 0x700).
		call .read_disk
		xor di, di  ; Points to next directory entry to compare filename against.
.next_entry:  ; Search for kernel file name, and find start cluster
		push cx  ; Save for CL.
		mov cx, 11  ; Number of bytes in a FAT filename.
		mov si, -.org+.io_sys
		push di
		repe cmpsb
		pop di
		pop cx  ; Restore for CL.
		je .found_entry ; Note that DI now is at directory entry + 11 bytes.
		lea di, [di+0x20]  ; DI := address of next directory entry.
		cmp di, [bp-.header+.bytes_per_sector]  ; 1 byte shorter than `cmp di, 0x200'.
		jnz .next_entry ; next directory entry
		dec cl
		jnz .read_rootdir_sector ; loop over sectors in cluster
		pop ax
		pop dx  ; Restore cluster number (DX:AX).
		call .next_cluster
		jmp short .next_rootdir_cluster  ; read next cluster

.found_entry:  ; Kernel directory entry is found.
		mov si, [es:di+0x14] ; get cluster number high word.
		mov di, [es:di+0x1a] ; get cluster number low word.
		; SI:DI will be used by the MS-DOS v7 load protocol later.
		mov ax, di
		mov dx, si
		; Read msload (first few sectors) of the kernel (io.sys).
		mov ch, 4  ; Load up to 4 sectors. MS-DOS 8.0 needs >=4, Windows 95 OSR2 and Windows 98 work with >=3.
.next_kernel_cluster:
		push dx
		push ax  ; Save cluster number (DX:AX).
		call .cluster_to_lba  ; Also sets CL to [bp-.header+.sectors_per_cluster].
		jnc .read_kernel_cluster
		; EOC encountered before we could read 4 sectors.
		jmp strict near mbr.fatal1+(.org-mbr.org)  ; Call library function within MBR, to save space. This one doesn't return.

.jump_to_msload_v7:
		; Fill registers according to MS-DOS v7 load protocol: https://pushbx.org/ecm/doc/ldosboot.htm#protocol-sector-msdos7
		mov dl, [bp-.header+.drive_number]
		; Already filled: SI:DI = first cluster of load file if FAT32.
		; Already filled: dword [ss:bp-4] = (== dword [bp-.header+.var_data_start]) first data sector of first cluster, including hidden sectors.
		; True by design: SS:BP -> boot sector with (E)BPB, typically at linear 0x7c00.
		; (It's not modified by this boot sector.) Diskette Parameter Table (DPT) may be relocated, possibly modified. The DPT is pointed to by the interrupt 1eh vector. If dword [ss:sp] = 0000_0078h (far pointer to IVT 1eh entry), then dword [ss:sp+4] -> original DPT
		; !! Currently not: word [ss:bp+0x1ee] points to a message table. The format of this table is described in lDebug's source files msg.asm and boot.asm, around uses of the msdos7_message_table variable.
		jmp 0x70:0x200  ; Jump to msload within io.sys.

.read_kernel_cluster:  ; Now: CL is sectors per cluster; EAX is sector number.
		call .read_disk
		lea bx, [bx+0x20]
		dec ch
		jz .jump_to_msload_v7
		dec cl ; initially DX holds sectors per cluster
		jnz .read_kernel_cluster  ; loop over sectors in cluster
		pop ax
		pop dx  ; Restore cluster number (DX:AX).
		call .next_cluster
		jmp short .next_kernel_cluster

; Given a cluster number, find the number of the next cluster in the FAT chain. Needs .var_fat_start.
; Inputs: DX:AX: cluster.
; Outputs: DX:AX: next cluster; ES: ruined.
.next_cluster:
		push bx  ; Save.
		mov bx, ax
		and bx, byte 0x7f  ; Assumes word [bp-.header+.bytes_per_sector] == 0x200.
		shl bx, 1
		shl bx, 1
		push cx
		mov cx, 7  ; Will shift DX:AX right by 7. Assumes word [bp-.header+.bytes_per_sector] == 0x200.
.shr7_again:	shr dx, 1
		rcr ax, 1
		loop .shr7_again
		pop cx
		add ax, [bp-.header+.var_fat_start]
		adc dx, [bp-.header+.var_fat_start+2]
		; Now: EAX is absolute sector number, BX is the byte offset within the sector.
		; Is it the last accessed and already buffered FAT sector?
		cmp ax, [bp-.header+.var_fat_sector]
		jne .fat_read_sector_now
		cmp dx, [bp-.header+.var_fat_sector+2]
		je .fat_sector_read
.fat_read_sector_now:
		mov [bp-.header+.var_fat_sector], ax
		mov [bp-.header+.var_fat_sector+2], dx  ; Mark sector DX:AX as buffered.
		push bx  ; Save.
		mov bx, 0xf0  ; Load FAT sector to 0xf00.
		call .read_disk ; read sector EAX to buffer
		pop bx  ; Restore.
.fat_sector_read:
		mov ax, [es:bx] ; read next cluster number
		mov dx, [es:bx+2]
		and dh, 0xf  ; Mask out top 4 bits, because FAT32 FAT pointers are only 28 bits.
		pop bx  ; Restore.
		ret

; Converts cluster number to the absolute sector number.
; Inputs: DX:AX - target cluster; .var_data_start, .sectors_per_cluster.
; Outputs on EOC: CF=1.
; Outputs on non-EOC: CF=0; DX:AX - absolute sector; CL: .sectors_per_cluster value.
.cluster_to_lba:
		cmp dx, 0x0fff  ; This is the maximum allowed value for DX, no need to do `ja .ret'.
		jb .no_eoc
		cmp ax, strict word 0xfff8
		jb .no_eoc
		stc
		ret
.no_eoc:	sub ax, byte 2
		sbb dx, byte 0
		; Sector := (cluster-2) * clustersize + data_start.
		mov cl, [bp-.header+.sectors_per_cluster]
		push cx  ; Save.
		jmp short .maybe_shift
.next_shift:	shl ax, 1
		rcl dx, 1
.maybe_shift:	shr cl, 1
		jnz .next_shift
		pop cx  ; Restore.
		add ax, [bp-.header+.var_data_start]
		adc dx, [bp-.header+.var_data_start+2]  ; Also CF := 0 for regular data.
		ret

; Read a sector from disk, using LBA or CHS.
; Inputs: DX:AX: sector offset (LBA); BX: BX:0 points to the destination buffer.
; Outputs: DX:AX incremented by 1, for next sector; ES: set to BX.
.read_disk:
		mov es, bx
		push ax  ; Save.
		push bx  ; Save.
		push cx  ; Save.
		push dx  ; Save.
		xor bx, bx  ; Use offset 0 in ES:BX.
		call mbr.read_sector+(.org-mbr.org)  ; Call library function within MBR, to save space. This one doesn't return.
		pop dx  ; Restore.
		pop cx  ; Restore.
		pop bx  ; Restore.
		pop ax  ; Restore.
		add ax, byte 1  ; Next sector.
		adc dx, byte 0
		ret

.errmsg_missing: db 'No '  ; Overlaps the following .io_sys.
.io_sys:	db 'IO      SYS', 0

		times 0x1fe-($-.header) db '-'  ; Padding.
.boot_signature: dw BOOT_SIGNATURE
assert_at .header+0x200

assert_fofs 0xa00

; __END__
