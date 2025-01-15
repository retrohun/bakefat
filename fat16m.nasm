;
; fat16m.nasm: empty FAT16 filesystem with MBR and partition table
; by pts@fazekas.hu at Thu Dec 26 01:51:51 CET 2024
;
; Compile with: nasm -O0 -w+orphan-labels -f bin -o fat16m.bin fat16m.nasm
; Minimum NASM version required to compile: 0.98.39
;
; Improvements over the MS-DOS 6.22 boot sector code:
;
; * MBR is also added (containing partition table, boot code and a copy of the FAT16 headers).
; * Provide FAT16 headers (BPB) in the MBR as well, for compatibility with
;   mtools(1) (`mdir -i hda.img`).
; * Autofill cyls (.sectors_per_track) and heads (.head_count) fields from
;   data returned by the BIOS in both the MBR and the FAT partition boot
;   sector.
; * Receive drive number (.drive_number) from the BIOS in both the MBR and
;   the FAT partition boot sector.
; * Code size optimizations without loss functionality.
; * Boot any of MS-DOS 4.01--6.22, Windows 95 (MS-DOS 7.0 and 7.1), Windows
;   98 (MS-DOS 7.1) patched Windows ME (MS-DOS 8.0), IBM PC DOS 4.01--7.1.
; * Allow io.sys and msdos.sys to be near the end of the 2 GiB partition
;   (i.e. work around the `div 63' limit).
; * Allow the directory entry of io.sys and msdos.sys be anywhere within the
;   root directory. (Previously io.sys had to be first, and msdos.sys had to
;   be second.)
; * Boot even if io.sys or msdos.sys is not contiguous on disk.
;   This is relevant only for cluster size 0x200 and 0x400, because for
;   >=0800 the first 3 sectors are already continuous, because they are in
;   the same cluster.
; * Write cyls (.sectors_per_track), heads (.head_count) and drive number
;   (.drive_number) values back to the boot sector BPB, in case DOS wants to
;   read it from there when initially mounting the filesystem.
; * Better cluster alignment (8 KiB) for faster host HDD access.
; * Better cylinder alignment for comaptibility with Mtools and QEMU.
; * Provide caching of last FAT sector.
;
; !! Set .sectors_per_track to 1 in the MBR only, for better Mtools integration (no need for MTOOLS_SKIP_CHECK=1).
; !! Patch MS-DOS 4.01 sources for non-cluster-2 io.sys booting, and .fat_count=1: https://fabulous.systems/posts/2024/05/a-minor-update-ms-dos-4-1-is-here/
; !! This may be false: MS-DOS/v4.0/src/BIOS/MSLOAD.ASM: MSLOAD can handle maximum FAT area size of 64 KB: it can handle 2 * 64 KiB. !! Double check by moving io.sys to the end. Or just replace it with MS-DOS 5.00 msload after testing.
; !! Add fast boot for Windows 95 RTL (https://retrocomputing.stackexchange.com/q/31115) in msdos.sys.
; !! Implement msload.nasm (as free software), for MS-DOS 4.01: make it work for FAT12, support .new_dipt.
; !! MS-DOS 4.01 reports if there is a HDD >32 MiB: WARNING! SHARE should be loaded for large media.
;    > https://www.os2museum.com/wp/dos/dos-4-0/
;    SHARE was not strictly required for DOS operation, but was needed for
;    applications using old-style FCBs (File Control Blocks). On large
;    partitions, DOS could not use FCBs directly and FCBs had to be
;    translated to SFT (System File Table) operations. The FCB to SFT
;    translation logic was implemented in SHARE.EXE.
; !! Docs about IBM PC DOS 7.1 (free to download): https://liam-on-linux.livejournal.com/59703.html
;    It's based off the same core as the embedded DOS in Windows 95B (OSR2)
;    and Windows 98. It supports FAT32, including the ability to boot from
;    them. It supports LBA hard disks, meaning it can handle volumes of over
;    8GB. It fixes a lot of bugs in the DOS codebase.
;
; FAT12, FAT16, FAT32 filesystem:
;
; * On a PC, each floppy and HDD sector is 512 bytes.
; * layout:
;   * hidden sectors:
;     * HDD MBR (including partition table), missing for floppy
;     * HDD other partitions, missing for floppy
;   * reserved sectors: (must be at least 16 for FAT32 for the multisector boot code installed by Windows XP)
;     * boot sector: including FAT headers (superblock, BPB) and boot code
;     * FAT32 filesystem information sector
;     * FAT32 backup boot sector
;     * other sectors
;   * first file allocation table (FAT)
;   * second file allocation table (FAT): can be missing
;   * root directory: fixed size, 32 bytes per entry
;   * clusters: same size each (any of 512, 1024, 2048, 4096, 8192, 16384 or 32768 bytes)
;   * unused data
; * alignment:
;   * Everything is aligned to sector size, nothing is aligned to cluster size.
;   * Alignment to cluster size greatly improves performance of RAIDs and large-sector HDDs.
;   * Hidden sectors usually start at the beginning of the device, so they are aligned.
;   * To align reserved sectors to cluster size, align the partition start.
;   * To align the first file allocation table to cluster size, increase the number of reserved sectors.
;   * There is no way to align the second file allocation table to cluster size. Maybe by increasing the number of clusters beyond the device.
;   * There is no way to align the root directory to cluster size. Maybe by increasing the number of clusters beyond the device.
;   * To align the clusters to cluster size, increase the number of root directory entries.
; * number of clusters:
;   * We take into Microsoft's EFI FAT32 specification (see below), Windows NT
;     4.0, mtools (https://github.com/Distrotech/mtools/blob/13058eb225d3e804c8c29a9930df0e414e75b18f/mformat.c#L222)
;     and Linux kernel 3.13 vfat.o.
;   * Microsoft's EFI FAT32 specification states that any FAT file system
;     with less than 4085 clusters is FAT12,
;     else any FAT file system with less than 65525 clusters is FAT16,
;     and otherwise it is FAT32 (up to 268435444 == 0xffffff4 clusters).
;   * FAT12: 1 .. 4078 (== 0xfee) clusters.
;   * FAT16: 4087 .. 65518 (== 0xffee) clusters.
;   * FAT32: 65525 .. 268435438 (== 0x0fffffee) clusters.
; * biggest HDD image with a single FAT16 filesystem:
;   * About 2 GiB == 2**31 bytes: 2**15 bytes per cluster, about 2**16 clusters.
;   * Still supported by MS-DOS.
;   * Geometry is compatible with QEMU 2.11.1.
;   * Compatible with mtools, even without MTOOLS_SKIP_CHECK=1: Total number of sectors must be a multiple of sectors per track.
;   * The y calculations above take into account the QEMU 2.11.1 bug that it reports 1 less cyls for logical disk geometry.
;   * Number of sectors per cluster: 64 (maximum for FAT).
;   * Number of clusters: 65518 (maximum for FAT16).
;   * Number of hidden sectors: 63 (must be divisble by secs, for MS-DOS).
;   * Number of reserved sectors: 57 (boot sector + 56, for the aligment of the clusters).
;   * Number of sectors per FAT: 2**16 * 2 / 2**9 == 2**8 == 256.
;   * Number of FATs: 1.
;   * Number of root directory entries: 128.
;   * Number of root directory sectors: 128 * 32 / 512 == 8.
;   * Number of sectors before the first cluster: 63+57+256+8 == 384 == 6*64.
;   * Total number of sectors including hidden sectors: 64*(6+65518) + (63-4) == 4193595 (+4 to round up to a multiple of secs==63, for MS-DOS and mtools).
;   * Logical disk geometry (as seen by MS-DOS with int 13h AH==2 and AH==8 in QEMU): cyls=521==z, heads=128, secs=63
;   * Physical disk geometry (as seen by int 13h AH==48h in QEMU): cyls=y, heads=16, secs=63; y*16*63 >= (z+1)*128*63; y >= (z+1)*128/16 == (521+1)*128/16; y == 4176.
;   * !! Try to force another in QEMU, with trans=1.
;   * Disk image size: 4176*16*63*512 == 2155216896 bytes.
;   * qemu-system-i386 says: `18675@1735137116.631602:hd_geometry_guess blk 0x5557df40d670 CHS 4176 16 63 trans 2`
;   * gdp.out (output of gdp.com, as hex): 00 bf 08 7f
;   * Logical disk geometry (as reported by int 13h AH==8): cyls=521, heads=128, secs=63
;   * Linux fdisk(1) `c`, `v` still reports: `Partition 1: does not end on cylinder boundary.`. MS-DOS still works. The partition table doesn't store the geometry (cyls, heads, secs).
;   * MS-DOS 6.22 boot sector code relies on the heads= (word at @0x1a) and secs= (word at @0x18) in the BPB; after booting, it ignores it
;   * ```
;     rm -f fat16.img && mkfs.vfat -a -C -D 0 -f 1 -F 16 -i abcd1234 -r 128 -R 57 -s 64 -S 512 -h 63 --invariant fat16.img 2096766
;     : Change number of heads to 128 (\x80\x00) at offset 26 in fat16.img.
;     dd if=fat16.img of=hda.img bs=512 count=58 seek=63 conv=notrunc,sparse
;     qemu-system-i386 -trace enable=hd_geometry_\* -fda t.img -drive file=hda.img,format=raw,id=hda,if=none -device ide-hd,drive=hda,cyls=4176,heads=16,secs=63 -boot a
;       dir c:
;       sys c:
;     qemu-system-i386 -trace enable=hd_geometry_\* -drive file=hda.img,format=raw,id=hda,if=none -device ide-hd,drive=hda,cyls=4176,heads=16,secs=63 -boot c
;     ```
; * !! MS-DOS 4.0 limitation: (msload.asm): MSLOAD can handle maximum FAT area size of 64 KB. (Is this true? Probably only msboot. Or maybe even not.)
;
; Accessing (`dir c:`) with wrong .sectors_per_track, .head_count or .hidden_sector_count:
;
; * FreeDOS 1.0..1.2: not supported.
; * FreeDOS 1.3: supported.
; * MS-DOS 6.22: supported.
; * !! Get more info.
; * !! Get info about booting.
; * !! Get separate info about .hidden_sector_count.
;
; .fat_count == 1 support:
;
; * MS-DOS <=6.22: not supported, not even `dir c:`.
; * IBM PC DOS 4.01..7.1: not supported, not even `dir c:`.
; * Windows 95 (MS-DOS 7.x), Windows 98 (MS-DOS 7.x), Windows ME (MS-DOS 8.0): supported.
; * FreeDOS 1.0..1.3: supported.
; * For some version of MS-DOS, there is a patch in this repo for HDDs, see
;   patchio*.nasm. (There is no patch for floppies.)
; * More info: https://retrocomputing.stackexchange.com/q/31080
; * !! Add a patch for MS-DOS 4.01 floppies, based on
;   https://retrocomputing.stackexchange.com/a/31082
;
; Sector layout of the 2-FAT, 512-byte-sector, 512-byte-cluster FAT16 HDD image:
;
; * !! Provide an option for 2048-byte (etc.) clusters.
; * 0: MBR, partition table, MBR boot code, early FAT16 headers
; * 1..62: unused, filled with NUL
; * 63: boot sector, FAT16 headers, boot sector boot code
; * 64..319: first FAT (aligned to 4 KiB) (starts with dw -8, -1; then next of the first cluster)
; * 320..575: second FAT (aiigned to 4 KiB) (starts with dw -8, -1; then next of the first cluster)
; * 576..583: root directory (128 entries) (aligned to 4 KiB)
; * 584..66101: clusters (0xffee == 65518 clusters) (aligned to 512 bytes) (first cluster has number 2)
; * 66102: padding for CHS geometry (typically 255*63 sectors), filled with NUL
;
; Sector layout of the 2-FAT, 512-byte-sector, 1-KiB-cluster FAT16 HDD image:
;
; * 0: MBR, partition table, MBR boot code, early FAT16 headers
; * 1..62: unused, filled with NUL
; * 63: boot sector, FAT16 headers, boot sector boot code
; * 64..319: first FAT (aligned to 4 KiB) (starts with dw -8, -1; then next of the first cluster)
; * 320..575: second FAT (aiigned to 4 KiB) (starts with dw -8, -1; then next of the first cluster)
; * 576..583: root directory (128 entries) (aligned to 4 KiB)
; * 584..131619: clusters (0xffee == 65518 clusters) (aligned to 1 KiB) (first cluster has number 2)
; * 131620: padding for CHS geometry (typically 255*63 sectors), filled with NUL
;
; Sector layout of the 2-FAT, 512-byte-sector, 2-KiB-cluster FAT16 HDD image:
;
; * 0: MBR, partition table, MBR boot code, early FAT16 headers
; * 1..62: unused, filled with NUL
; * 63: boot sector, FAT16 headers, boot sector boot code
; * 64..319: first FAT (aligned to 4 KiB) (starts with dw -8, -1; then next of the first cluster)
; * 320..575: second FAT (aiigned to 4 KiB) (starts with dw -8, -1; then next of the first cluster)
; * 576..583: root directory (128 entries) (aligned to 4 KiB)
; * 584..262655: clusters (0xffee == 65518 clusters) (aligned to 2 KiB) (first cluster has number 2)
; * 262656: padding for CHS geometry (typically 255*63 sectors), filled with NUL
;
; Sector layout of the 2-FAT, 512-byte-sector, 4-KiB-cluster FAT16 HDD image:
;
; * 0: MBR, partition table, MBR boot code, early FAT16 headers
; * 1..62: unused, filled with NUL
; * 63: boot sector, FAT16 headers, boot sector boot code
; * 64..319: first FAT (aligned to 4 KiB) (starts with dw -8, -1; then next of the first cluster)
; * 320..575: second FAT (aiigned to 4 KiB) (starts with dw -8, -1; then next of the first cluster)
; * 576..583: root directory (128 entries) (aligned to 4 KiB)
; * 584..524727: clusters (0xffee == 65518 clusters) (aligned to 4 KiB) (first cluster has number 2)
; * 524728: padding for CHS geometry (typically 255*63 sectors), filled with NUL
;
; Sector layout of the 2-FAT, 512-byte-sector, 8-KiB-cluster FAT16 HDD image:
;
; * 0: MBR, partition table, MBR boot code, early FAT16 headers
; * 1..62: unused, filled with NUL
; * 63: boot sector, FAT16 headers, boot sector boot code
; * 64..71: unused, filled with NUL, for alignment of the rest
; * 72..327: first FAT (aligned to 4 KiB) (starts with dw -8, -1; then next of the first cluster)
; * 328..583: second FAT (aiigned to 4 KiB) (starts with dw -8, -1; then next of the first cluster)
; * 584..591: root directory (128 entries) (aligned to 4 KiB)
; * 592..1048879: clusters (0xffee == 65518 clusters) (aligned to 8 KiB) (first cluster has number 2)
; * 1048880: padding for CHS geometry (typically 255*63 sectors), filled with NUL
;
; Sector layout of the 2-FAT, 512-byte-sector, 16-KiB-cluster FAT16 HDD image:
;
; * 0: MBR, partition table, MBR boot code, early FAT16 headers
; * 1..62: unused, filled with NUL
; * 63: boot sector, FAT16 headers, boot sector boot code
; * 64..87: unused, filled with NUL, for alignment of the rest
; * 88..343: first FAT (aligned to 4 KiB) (starts with dw -8, -1; then next of the first cluster)
; * 344..599: second FAT (aiigned to 4 KiB) (starts with dw -8, -1; then next of the first cluster)
; * 600..608: root directory (128 entries) (aligned to 4 KiB)
; * 608..2097183: clusters (0xffee == 65518 clusters) (aligned to 16 KiB) (first cluster has number 2)
; * 2097184: padding for CHS geometry (typically 255*63 sectors), filled with NUL
;
; Sector layout of the 2-FAT, 512-byte-sector, 32-KiB-cluster FAT16 HDD image:
;
; * 0: MBR, partition table, MBR boot code, early FAT16 headers
; * 1..62: unused, filled with NUL
; * 63: boot sector, FAT16 headers, boot sector boot code
; * 64..119: unused, filled with NUL, for alignment of the rest  !! make the root directory larger, just align to 8 KiB
; * 120..375: first FAT (aligned to 4 KiB) (starts with dw -8, -1; then next of the first cluster)
; * 376..631: second FAT (aiigned to 4 KiB) (starts with dw -8, -1; then next of the first cluster)
; * 632..639: root directory (128 entries) (aligned to 4 KiB)
; * 640..4193791: clusters (0xffee == 65518 clusters) (aligned to 32 KiB) (first cluster has number 2)
; * 4193792: padding for CHS geometry (typically 255*63 sectors), filled with NUL
;
; Sector layout of the 1-FAT, 512-byte-sector, 32-KiB-cluster FAT16 HDD image, not compatible with MS-DOS 6.22:
;
; * 0: MBR, partition table, MBR boot code, early FAT16 headers
; * 1..62: unused, filled with NUL
; * 63: boot sector, FAT16 headers, boot sector boot code
; * 64..119: unused, filled with NUL, for alignment of the rest
; * 120..375: first FAT (aligned to 4 KiB) (starts with dw -8, -1; then next of the first cluster)
; * 376..383: root directory (128 entries) (aligned to 4 KiB)
; * 384..4193535: clusters (0xffee == 65518 clusters) (aligned to 32 KiB) (first cluster has number 2)
; * 4193536: padding for CHS geometry (typically 255*63 sectors), filled with NUL
;
; Directory entry for hi.txt, pointing to the last cluster:
;
;    db 'HI      TXT'  ; File name and extension, space-padded.
;    db 0x20, 0x00, 0x00, 0x8a, 0x5d
;    db 0x21, 0x5a, 0x21, 0x5a, 0x00, 0x00, 0x8a, 0x5d, 0x21, 0x5a
;    dw 0xffef  ; Start cluster index. (first cluster would have number 2)
;    dd 0xf  ; File size in bytes.
;
; Constraints:
;
; * Cluster count is the count of on-disk clusters, which excludes unstored
;   clusters 0 and 1.
; * FAT16 cluster count must be at least 0x1000-2, to prevent DOS from
;   recognizing the filesystem as FAT12. And at most 0xffee.
; * FAT32 cluster count must be at least 0x10000-2, to prevent DOS from
;   recognizing the filesystem as FAT16. And at most 0xffffee.
; * .sectors_per_fat must be a multiple of 8, for alignment. Exception:
;   16M-8K with 2 FATs.
; * Maximum cluster size is 32 KiB (32K) for most DOS systems (including
;   Windows 95). Windows NT, Windows 98 and Windows ME support 64 KiB.
;   For simplicity and compatibility, we support only up to 32 KiB.
; * We limit filesystem size to <~2TiB, because that's the per-partition
;   maximum size supported by the MBR partition table.
; * !! What is the largest B...-512 supported by mkfs.vfat?
;
; With DOS-all compatibility:
;
; * 2M: 2M-512
; * 4M: 4M-1K
; * 8M: 8M-2K
; * 16M: 16M-4K
; * 32M: 32M-4K
; * 64M: 64M-4K
; * 128M: 128M-4K
; * 256M: 256M-4K
; * 512M: 512M-8K
; * 1G: 1G-16K
; * 2G: 2G-32K
;
; DOS-patched compatibility is like DOS-all compatibility, but with 1FAT.
;
; Windows compatibility (all 1FAT):
;
; * 2M: 2M-512
; * 4M: 4M-1K
; * 8M: 8M-2K
; * 16M: 16M-4K
; * 32M: 32M-4K
; * 64M: 64M-4K
; * 128M: 128M-4K
; * 256M: 256M-4K
; * 512M: B512M-4K
; * 1G: B1G-4K
; * 2G: B2G-4K
; * 4G: B4G-4K
; * 16G: B16G-4K
; * 32G: B32G-4K
; * 64G: B64G-8K
; * 128G: B128G-16K
; * 256G: B256G-32K
; * 512G: B512G-32K
; * 1T: B1T-32K
; * 2T: B2T-32K
;
; To-be supported filesystem size presets:
;
;                        2M-512  4M-512  4M-1K   8M-512  8M-1K   8M-2K
;   ---------------------------------------------------------------------
;   filesystem type      FAT16   FAT16   FAT16   FAT16   FAT16   FAT16
;   cluster count+2      0x1000  0x2000  0x1000  0x4000  0x2000  0x1000
;   cluster size          0x200   0x200   0x400   0x200   0x400   0x800
;   sectors per cluster       1       1       2       1       2       4
;   sectors per FAT        0x10    0x20    0x10    0x40    0x20      10
;
;                        16M-512  16M-1K  16M-2K  16M-4K  16M-8K
;   ------------------------------------------------------------
;   filesystem type      FAT16    FAT16   FAT16   FAT16   FAT16
;   cluster count+2      0x8000   0x4000  0x2000  0x1000  0x1000
;   cluster size          0x200    0x400   0x800  0x1000  0x2000
;   sectors per cluster       1        2       4       8    0x10
;   sectors per FAT        0x80     0x20    0x10       8      !4
;
;                        32M-512  32M-1K  32M-2K  32M-4K  32M-8K
;   ------------------------------------------------------------
;   filesystem type      FAT16    FAT16   FAT16   FAT16   FAT16
;   cluster count+2      0xfff0   0x8000  0x4000  0x2000  0x1000
;   cluster size          0x200    0x400   0x800  0x1000  0x2000
;   sectors per cluster       1        2       4       8    0x10
;   sectors per FAT       0x100     0x80    0x20    0x10       8
;
;                        64M-1K  64M-2K  64M-4K  64M-8K  64M-16K
;   ------------------------------------------------------------
;   filesystem type      FAT16   FAT16   FAT16   FAT16   FAT16
;   cluster count+2      0xfff0  0x8000  0x4000  0x2000   0x1000
;   cluster size          0x400   0x800  0x1000  0x2000   0x2000
;   sectors per cluster       2       4       8    0x10     0x20
;   sectors per FAT       0x100    0x80    0x20    0x10        8
;
;                        128M-2K  128M-4K  128M-8K  128M-16K  128M-32K
;   ------------------------------------------------------------------
;   filesystem type      FAT16    FAT16    FAT16    FAT16     FAT16
;   cluster count+2       0xfff0   0x8000   0x4000   0x2000     0x1000
;   cluster size           0x800   0x1000   0x2000   0x4000     0x8000
;   sectors per cluster        4       8      0x10     0x20       0x40
;   sectors per FAT        0x100     0x80     0x20     0x10          8
;
;                        256M-4K  256M-8K  256M-16K  256M-32K
;   ---------------------------------------------------------
;   filesystem type      FAT16    FAT16    FAT16     FAT16
;   cluster count+2       0xfff0   0x8000    0x4000    0x2000
;   cluster size          0x1000   0x2000    0x4000    0x8000
;   sectors per cluster        8     0x10      0x20      0x40
;   sectors per FAT        0x100     0x80      0x20      0x10
;
;                        512M-8K  512M-16K  512M-32K  1G-16K   1G-32K   2G-32K
;   --------------------------------------------------------------------------
;   filesystem type      FAT16    FAT16     FAT16     FAT16    FAT16    FAT16
;   cluster count+2       0xfff0    0x8000    0x4000  0xfff0   0x8000   0xfff0
;   cluster size          0x2000    0x4000    0x8000  0x4000   0x8000   0x8000
;   sectors per cluster     0x10      0x20      0x40    0x20     0x40     0x40
;   sectors per FAT        0x100      0x80      0x20   0x100     0x80    0x100
;
;                        B32M-512  B64M-512  B64M-1K  B128M-512  B128M-1K  B128M-2K
;   -------------------------------------------------------------------------------
;   filesystem type      FAT32     FAT32     FAT32    FAT32      FAT32     FAT32
;   cluster count+2       0x10000   0x20000  0x10000    0x40000   0x20000   0x10000
;   cluster size            0x200     0x200    0x400      0x200     0x400     0x800
;   sectors per cluster         1         1        2          1         2         4
;   sectors per FAT         0x200     0x400    0x200      0x800     0x400     0x200
;
;                        B256M-512  B256M-1K  B256M-2K  B256M-4K
;   ------------------------------------------------------------
;   filesystem type      FAT32      FAT32     FAT32     FAT32
;   cluster count+2        0x80000   0x40000   0x20000   0x10000
;   cluster size             0x200     0x400     0x800    0x1000
;   sectors per cluster          1         2         4         8
;   sectors per FAT         0x1000     0x800     0x400     0x200
;
;                        B512M-512  B512M-1K  B512M-2K  B512M-4K  B512M-8K
;   ----------------------------------------------------------------------
;   filesystem type      FAT32      FAT32     FAT32     FAT32     FAT32
;   cluster count+2       0x100000   0x80000   0x40000   0x20000   0x10000
;   cluster size             0x200     0x400     0x800    0x1000    0x2000
;   sectors per cluster          1         2         4         8      0x10
;   sectors per FAT         0x2000    0x1000     0x800     0x400     0x200
;
;                        B1G-512   B1G-1K    B1G-2K   B1G-4K   B1G-8K   B1G-16K
;   ---------------------------------------------------------------------------
;   filesystem type      FAT32     FAT32     FAT32    FAT32    FAT32    FAT32
;   cluster count+2      0x200000  0x100000  0x80000  0x40000  0x20000  0x10000
;   cluster size            0x200     0x400    0x800   0x1000   0x2000   0x4000
;   sectors per cluster         1         2        4        8     0x10     0x20
;   sectors per FAT        0x4000    0x2000   0x1000    0x800    0x400    0x200
;
;                        B2G-512   B2G-1K    B2G-2K    B2G-4K   B2G-8K   B2G-16K  B2G-32K
;   -------------------------------------------------------------------------------------
;   filesystem type      FAT32     FAT32     FAT32     FAT32    FAT32    FAT32    FAT32
;   cluster count+2      0x400000  0x200000  0x100000  0x80000  0x40000  0x20000  0x10000
;   cluster size            0x200     0x400     0x800   0x1000   0x2000   0x4000   0x8000
;   sectors per cluster         1         2         4        8     0x10     0x20     0x40
;   sectors per FAT        0x8000    0x4000    0x2000   0x1000    0x800    0x400    0x200
;
;                        B4G-512   B4G-1K    B4G-2K    B4G-4K    B4G-8K   B4G-16K  B4G-32K
;   --------------------------------------------------------------------------------------
;   filesystem type      FAT32     FAT32     FAT32     FAT32     FAT32    FAT32    FAT32
;   cluster count+2      0x800000  0x400000  0x200000  0x100000  0x80000  0x40000  0x20000
;   cluster size            0x200     0x400     0x800    0x1000   0x2000   0x4000   0x8000
;   sectors per cluster         1         2         4         8     0x10     0x20     0x40
;   sectors per FAT       0x10000    0x8000    0x4000    0x2000   0x1000    0x800    0x400
;
;                        B8G-512    B8G-1K    B8G-2K    B8G-4K    B8G-8K    B8G-16K  B8G-32K
;   ----------------------------------------------------------------------------------------
;   filesystem type      FAT32      FAT32     FAT32     FAT32     FAT32     FAT32    FAT32
;   cluster count+2      0x1000000  0x800000  0x400000  0x200000  0x100000  0x80000  0x40000
;   cluster size             0x200     0x400     0x800    0x1000    0x2000   0x4000   0x8000
;   sectors per cluster          1         2         4         8      0x10     0x20     0x40
;   sectors per FAT        0x20000   0x10000    0x8000    0x4000    0x2000   0x1000    0x800
;
;                        B16G-512   B16G-1K    B16G-2K   B16G-4K   B16G-8K   B16G-16K  B16G-32K
;   -------------------------------------------------------------------------------------------
;   filesystem type      FAT32      FAT32      FAT32     FAT32     FAT32     FAT32     FAT32
;   cluster count+2      0x2000000  0x1000000  0x800000  0x400000  0x200000  0x100000   0x80000
;   cluster size             0x200      0x400     0x800    0x1000    0x2000    0x4000    0x8000
;   sectors per cluster          1          2         4         8      0x10      0x20      0x40
;   sectors per FAT        0x40000    0x20000   0x10000    0x8000    0x4000    0x2000    0x1000
;
;                        B32G-512   B32G-1K    B32G-2K    B32G-4K   B32G-8K   B32G-16K  B32G-32K
;   --------------------------------------------------------------------------------------------
;   filesystem type      FAT32      FAT32      FAT32      FAT32     FAT32     FAT32     FAT32
;   cluster count+2      0x4000000  0x2000000  0x1000000  0x800000  0x400000  0x200000  0x100000
;   cluster size             0x200      0x400      0x800    0x1000    0x2000    0x4000    0x8000
;   sectors per cluster          1          2          4         8      0x10      0x20      0x40
;   sectors per FAT        0x80000    0x40000    0x20000   0x10000    0x8000    0x4000    0x2000
;
;                        B64G-512   B64G-1K    B64G-2K    B64G-4K    B64G-8K   B64G-16K  B64G-32K
;   ---------------------------------------------------------------------------------------------
;   filesystem type      FAT32      FAT32      FAT32      FAT32      FAT32     FAT32     FAT32
;   cluster count+2      0x8000000  0x4000000  0x2000000  0x1000000  0x800000  0x400000  0x200000
;   cluster size             0x200      0x400      0x800     0x1000    0x2000    0x4000    0x8000
;   sectors per cluster          1          2          4          8      0x10      0x20      0x40
;   sectors per FAT       0x100000    0x80000    0x40000    0x20000   0x10000    0x8000    0x4000
;
;                        B128G-512  B128G-1K   B128G-2K   B128G-4K   B128G-8K   B128G-16K  B128G-32K
;   ------------------------------------------------------------------------------------------------
;   filesystem type      FAT32      FAT32      FAT32      FAT32      FAT32      FAT32      FAT32
;   cluster count+2      0xffffff0  0x8000000  0x4000000  0x2000000  0x1000000   0x800000   0x400000
;   cluster size             0x200      0x400      0x800     0x1000     0x2000     0x4000     0x8000
;   sectors per cluster          1          2          4          8       0x10       0x20       0x40
;   sectors per FAT       0x200000   0x100000    0x80000    0x40000    0x20000    0x10000     0x8000
;
;                        B256G-1K   B256G-2K   B256G-4K   B256G-8K   B256G-16K  B256G-32K
;   -------------------------------------------------------------------------------------
;   filesystem type      FAT32      FAT32      FAT32      FAT32      FAT32      FAT32
;   cluster count+2      0xffffff0  0x8000000  0x4000000  0x2000000   0x100000   0x800000
;   cluster size             0x400      0x800     0x1000     0x2000     0x4000     0x8000
;   sectors per cluster          2          4          8       0x10       0x20       0x40
;   sectors per FAT       0x200000   0x100000    0x80000    0x40000    0x20000    0x10000
;
;                        B512G-2K   B512G-4K   B512G-8K   B512G-16K  B512G-32K
;   --------------------------------------------------------------------------
;   filesystem type      FAT32      FAT32      FAT32      FAT32      FAT32
;   cluster count+2      0xffffff0  0x8000000  0x4000000   0x200000  0x1000000
;   cluster size             0x800     0x1000     0x2000     0x4000     0x8000
;   sectors per cluster          4          8       0x10       0x20       0x40
;   sectors per FAT       0x200000   0x100000    0x80000    0x40000    0x20000
;
;                        B1T-4K     B1T-8K     B1T-16K    B1T-32K    B2T-8K     B2T-16K    B2T-32K
;   ------------------------------------------------------------------------------------------------
;   filesystem type      FAT32      FAT32      FAT32      FAT32      FAT32      FAT32      FAT32
;   cluster count+2      0xffffff0  0x8000000  0x4000000  0x2000000  0xffffe01  0x8000000  0x4000000
;   cluster size            0x1000     0x2000     0x4000     0x8000     0x2000     0x4000     0x8000
;   sectors per cluster          8       0x10       0x20       0x40       0x10       0x20       0x40
;   sectors per FAT       0x200000   0x100000    0x80000    0x40000   0x200000   0x100000    0x80000
;
; Number of sectors of B2T-8K (!! test that it works):
;
; * 1: MBR, partition table, MBR boot code, early FAT16 headers
; * 62: unused, filled with NUL
; * 1: boot sector, FAT32 headers, boot sector boot code
; * 8: unused reserved sectors
; * 0x200000: first FAT
; * 0x200000: second FAT (!! -3 wouldn't be aligned)
; * 8: root directory (256 entries)
; * !! (0xffffff0-495-2)*0x2000: data clusters
; * 0x1ffffffe050: total
; * 0x20000000000-1: maximum
;
; MS-DOS 4.01--6.22 (and PC-DOS) boot process from HDD:
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

PTYPE:  ; Partition type.
.EMPTY equ 0
.FAT12 equ 1
.FAT16_LESS_THAN_32MIB equ 4
.EXTENDED equ 5
.FAT16 equ 6
.HPFS_NTFS_EXFAT equ 7
.FAT32 equ 0xb
.FAT32_LBA equ 0xc
.FAT16_LBA equ 0xe
.EXTENDED_LBA equ 0xf
.MINIX_OLD equ 0x80
.MINIX equ 0x81
.LINUX_SWAP equ 0x82
.LINUX equ 0x83
.LINUX_EXTENDED equ 0x85
.LINUX_LVM equ 0x8e
.LINUX_RAID_AUTO equ 0xfd

PSTATUS:  ; Partition status.
.INACTIVE equ 0
.ACTIVE equ 0x80

BOOT_SIGNATURE equ 0xaa55  ; dw.

; !! For partition_entry_lba to fill the CHS values properly, values from qemu-system-i386.
pe_heads equ 16
pe_secs equ 63

; %1: status (PSTATUS.*: 0: inactive, 0x80: active (bootable))
; %2: CHS head of first sector; %3: CHS cylinder and sector of first sector
; %4: partition type (PTYPE.*)
; %5: CHS head of last sector; %6: CHS cylinder and sector of last sector
; %7: sector offset (LBA) of the first sector
; %8: number of sectors
%macro partition_entry 8
  db (%1), (%2)
  dw (%3)
  db (%4), (%5)
  dw (%6)
  dd (%7), (%8)
%endm
; Like partition_entry, but sets all CHS values to 0.
;
; (The following is verified only if DOS is not booted from this drive.)
; FreeDOS 1.0..1.3 displays a warning at boot time about a bad CHS value,
; but it works. MS-DOS 6.22 doesn't care about CHS values here.
;
; !! Check and add compatibility with MS-DOS 5.00, 6.00 and 6.20. Works: 4.01, 5.00, 6.22, 7.x, 8.0.
;
; %1: status (PSTATUS.*: 0: inactive, 0x80: active (bootable))
; %2: partition type (PTYPE.*)
; %3: sector offset (LBA) of the first sector
; %4: number of sectors
%macro partition_entry_lba 4
  partition_entry (%1), 0, 0, (%2), 0, 0, (%3), (%4)
%endm
%macro partition_entry_empty 0
  partition_entry PSTATUS.INACTIVE, 0, 0, PTYPE.EMPTY, 0, 0, 0, 0  ; All NULs.
%endm

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
%if (%7)  ; FAT32.
.rootdir_entry_count: dw 0
%else
.rootdir_entry_count: dw (%6)<<4  ; Each FAT directory entry is 0x20 bytes. Each sector is 0x200 bytes.
%endif
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
.sectors_per_fat: dw 0  ; IBM PC DOS 7.1 msload detects FAT32 by comparing this to 0.
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
.extended_boot_signature: db 0x29
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
.extended_boot_signature: db 0x29
assert_at .header+0x27
.volume_id: dd 0x1234abcd  ; 1234-ABCD.
assert_at .header+0x2b
.volume_label:	db 'NO NAME    '
assert_at .header+0x36
.fstype:	db 'FAT16   '
assert_at .header+0x3e
%endif
%endm

; ---

%ifndef FAT_32
  %define FAT_32 0  ; 0 or 1.
%endif
fat_32 equ FAT_32

partition_1_sec_ofs equ 0x3f  ; 63. For MS-DOS, this must be a multiple of the CHS secs (sectors per track).
%ifndef FAT_CLUSTER_COUNT
  %define FAT_CLUSTER_COUNT 0xffee
%endif
fat_cluster_count equ FAT_CLUSTER_COUNT  ; This is physical (stored on disk) cluster count. Valid values for FAT16 are: 0xffe..0xffee. Valid values for FAT32 are: 0xfffe..0xfffffee.
%ifndef FAT_COUNT  ; Must be 1 or 2 if defined.
  %define FAT_COUNT 2  ; For MS-DOS 6.22 compatibility. !! Make the filesystem image 128 KiB larger than.
%endif
fat_fat_count equ FAT_COUNT
%ifndef FAT_SECTORS_PER_CLUSTER
  %define FAT_SECTORS_PER_CLUSTER 0x40
%endif
fat_sectors_per_cluster equ FAT_SECTORS_PER_CLUSTER  ; Valid values: 1, 2, 4, 8, 0x10, 0x20, 0x40.

%if fat_32
  fat_reserved_sector_count equ 0x11
  fat_rootdir_sector_count equ 0
%else
  %if fat_sectors_per_cluster<0x10
    fat_reserved_sector_count equ 1 ; Only the boot sector.
  %else
    fat_reserved_sector_count equ 1+(fat_sectors_per_cluster-8)  ; !! Explain this because of alignment, after first FAT and second FAT. !! Also the -8 is related to the .rootdir_sector_count.
  %endif
  fat_rootdir_sector_count equ 8  ; 128 entries.
%endif
fat_sectors_per_fat equ (fat_cluster_count+2+(1<<(8-fat_32))-1)>>(8-fat_32)  ; Good formula for FAT16. We have the +2 here because clusters 0 and 1 have a next-pointer in the FATs, but they are not stored on disk.
fat_sector_count equ fat_reserved_sector_count+fat_fat_count*fat_sectors_per_fat+fat_rootdir_sector_count+fat_cluster_count*fat_sectors_per_cluster  ; Largest FAT16, close to 2 GiB.

assert_fofs 0
mbr:  ; Master Boot record, sector 0 (LBA) of the drive.
; More info about the MBR: https://wiki.osdev.org/MBR_(x86)
; More info about the MBR: https://en.wikipedia.org/wiki/Master_boot_record
; More info about the MBR: https://pushbx.org/ecm/doc/ldosboot.htm#protocol-rombios-sector
fat_header fat_reserved_sector_count, fat_sector_count, fat_fat_count, fat_sectors_per_cluster, fat_sectors_per_fat, fat_rootdir_sector_count, fat_32, partition_1_sec_ofs
.org: equ -0x7e00+.header
		times 0x5a-($-.header) db '+'  ; Pad FAT16 headers to the size of FAT32, for uniformity.
.boot_code:
		incbin 'boot.bin', 0x5a, 0x1b8-0x5a
assert_at .header+0x1b8
.disk_id_signature: dd 0x9876edcb
assert_at .header+0x1bc
.reserved_word_0: dw 0
.partition_1:
assert_at .header+0x1be  ; Partition 1.
%if fat_32
.ptype: equ PTYPE.FAT32_LBA  ; Windows 95 OSR2 cannot read the filesystem if PTYPE.FAT16 is (incorrectly) specified here.
%else
.ptype: equ PTYPE.FAT16
%endif
		partition_entry_lba PSTATUS.ACTIVE, .ptype, partition_1_sec_ofs, fat_sector_count
assert_at .header+0x1ce  ; Partition 2.
		partition_entry_empty
assert_at .header+0x1de  ; Partition 3.
		partition_entry_empty
assert_at .header+0x1ee  ; Partition 4.
		partition_entry_empty
assert_at .header+0x1fe
.boot_signature: dw BOOT_SIGNATURE
assert_at .header+0x200

; ---

assert_fofs 0x200
		times (partition_1_sec_ofs-1)<<9 db 0
assert_fofs partition_1_sec_ofs<<9

; ---

%macro fat_boot_sector 0
		fat_header fat_reserved_sector_count, fat_sector_count, fat_fat_count, fat_sectors_per_cluster, fat_sectors_per_fat, fat_rootdir_sector_count, fat_32, 0
.org: equ -0x7c00+.header
.boot_code:
%if fat_32
assert_at .header+0x5a
		incbin 'boot.bin', 0x25a, 0x1fe-0x5a
%else
assert_at .header+0x3e
		incbin 'boot.bin', 0x43e, 0x1fe-0x3e
%endif
.boot_signature: dw BOOT_SIGNATURE
assert_at .header+0x200
%endm
boot_sector:
		fat_boot_sector

; ---

assert_fofs (partition_1_sec_ofs+1)<<9
%if fat_32
fsinfo:  ; https://en.wikipedia.org/wiki/Design_of_the_FAT_file_system#FS_Information_Sector
.header:	db 'RRaA'
.reserved:	times 0x1e0 db 0
assert_at .header+0x1e4
.signature2:	db 'rrAa'
assert_at .header+0x1e8
.free_cluster_count: dd fat_cluster_count-1  ; -1 because the root directory occupies 1 cluster.
assert_at .header+0x1ec
.most_recently_allocated_cluster_ofs: dd 2  ; The root directory cluster.
assert_at .header+0x1f0
.reserved2:	times 0xc db 0
.signature3:	dw 0, BOOT_SIGNATURE
assert_at .header+0x200
assert_fofs (partition_1_sec_ofs+2)<<9

		times 4*0x200 db 0
backup_boot_sector:
		fat_boot_sector
%endif
		times (fat_reserved_sector_count-1-6*fat_32)<<9 db 0  ; Reserved sectors before FAT.
assert_fofs (partition_1_sec_ofs+fat_reserved_sector_count)<<9

assert_fofs (partition_1_sec_ofs+fat_reserved_sector_count)<<9
first_fat:
%if fat_32
		; !! Use fat_media_descriptor instead of 0xf8.
		dd 0xffffff8, 0xfffffff  ; 2 special cluster pointers, no used clusters in FAT16.
		dd 0xffffff8  ; Indicates empty root directory.
%else
		; !! Use fat_media_descriptor instead of 0xf8 of -8.
		dw -8, -1  ; 2 special cluster pointers, no used clusters in FAT16.
%endif
		times (first_fat-$)&0x1ff db 0  ; Align to multiple of sector size (0x200).

%if fat_fat_count>1
		times first_fat+(fat_sectors_per_fat<<9)-$ db 0
second_fat:
%if fat_32
		; !! Use fat_media_descriptor instead of 0xf8.
		dd 0xffffff8, 0xfffffff  ; 2 special cluster pointers, no used clusters in FAT16.
		dd 0xffffff8  ; Indicates empty root directory.
%else
		; !! Use fat_media_descriptor instead of 0xf8 of -8.
		dw -8, -1  ; 2 special cluster pointers, no used clusters in FAT16.
%endif
		times (second_fat-$)&0x1ff db 0  ; Align to multiple of sector size (0x200).
%endif
