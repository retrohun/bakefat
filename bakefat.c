/*
 * bakefat.c: bootable external FAT hard disk image creator for DOS and Windows 3.1--95--98--ME
 * by pts@fazekas.hu at Thu Feb  6 14:32:22 CET 2025
 *
 * Compile with OpenWatcom C compiler, minilibc686 for Linux i386: minicc -march=i386 -Werror -Wno-n201 -o bakefat bakefat.c
 * Compile with GCC for Unix: gcc -ansi -pedantic -W -Wall -Wno-overlength-strings -Werror -s -O2 -o bakefat bakefat.c
 * Compile with OpenWatcom C compiler for Win32: owcc -bwin32 -Wl,runtime -Wl,console=3.10 -Os --fno-stack-check -march=i386 -W -Wall -Wno-n201 -o bakefat.exe bakefat.c
 *
 * !! Add boot sector for booting Windows NT--2000--XP (ntldr) from FAT16 and FAT32.
 * !! Add DOS 8086 port (bakefat.exe). (Make sure it compiles with owcc -bpmodew etc.)
 * !! Write directly to device, clear existing FAT table (cluster chain pointers) and first root directory entry.
 */

#ifndef _FILE_OFFSET_BITS
#  define _FILE_OFFSET_BITS 64  /* __GLIBC__ and __UCLIBC__ use lseek64(...) instead of lseek(...), and use ftruncate64(...) instead of ftruncate(...). */
#endif
#define _LARGEFILE64_SOURCE  /* __GLIBC__ lseek64(...). */
#define _XOPEN_SOURCE  /* __GLIBC__ ftruncate64(...) with `gcc -ansi -pedantic. */
#define _XOPEN_SOURCE_EXTENDED  /* __GLIBC__ ftruncate64(...). */
#ifdef __MMLIBC386__
#  include <mmlibc386.h>
#else
#  include <fcntl.h>
#  include <stdint.h>
#  include <stdarg.h>
#  include <stdio.h>
#  include <string.h>
#  include <strings.h>  /* strcasecmp(...). */
#  include <stdlib.h>
#  if defined(_WIN32) || defined(MSDOS) || defined(__NT__)
#    include <io.h>
#  else
#    include <unistd.h>
#  endif
#endif

#ifndef BAKEFAT_VERSION
#  define BAKEFAT_VERSION 1
#endif

#undef noreturn
#ifdef __GNUC__
#  ifndef inline
#    define inline __inline__  /* For `gcc -ansi -pedantic'. */
#  endif
#  define noreturn __attribute__((__noreturn__))
#else
#  ifdef __WATCOMC__
#    define noreturn __declspec(noreturn)
#  else
#    define noreturn
#  endif
#endif

#undef  ARRAY_SIZE
#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))

#undef  ARRAY_END
#define ARRAY_END(a) ((a) + (sizeof(a) / sizeof((a)[0])))

#ifndef O_BINARY
#  define O_BINARY 0
#endif

#ifdef __MMLIBC386__
#  define msg_printf printf_void
#else
  static void msg_printf(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    (void)!vfprintf(stderr, fmt, ap);
  }
#endif

#if defined(__WATCOMC__) && defined(__NT__) && defined(_WCDATA)  /* OpenWatcom C compiler, Win32 target, OpenWatcom libc. */
  /* !! Create sparse file on Win32: https://web.archive.org/web/20220207223136/http://www.flexhex.com/docs/articles/sparse-files.phtml */
  /* OpenWatcom libc SetFilePointer: https://github.com/open-watcom/open-watcom-v2/blob/817428310bd22abeaf8a7018ce4c1c2578975543/bld/clib/handleio/c/__lseek.c#L97-L109 */
  /* Overrides lib386/nt/clib3r.lib / mbcupper.o
   * Source: https://github.com/open-watcom/open-watcom-v2/blob/master/bld/clib/mbyte/c/mbcupper.c
   * Overridden implementation calls CharUpperA in USER32.DLL:
   * https://docs.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-charuppera
   *
   * This function is a transitive dependency of _cstart() with main() in
   * OpenWatcom. By overridding it, we remove the transitive dependency of all
   * .exe files compiled with `owcc -bwin32' on USER32.DLL.
   *
   * This is a simplified implementation, it keeps non-ASCII characters intact.
   */
  unsigned int _mbctoupper(unsigned int c) {
    return (c - 'a' + 0U <= 'z' - 'a' + 0U)  ? c + 'A' - 'a' : c;
  }
#  define IS_WINNT() ((short)_osbuild >= 0)  /* https://github.com/open-watcom/open-watcom-v2/blob/b59d9d9ea5b9266e66efa305f970fe0a51892bb7/bld/lib_misc/h/osver.h#L43 */
#  define IS_WINNT_WIN32API() ((int)GetVersion() >= 0)  /* https://github.com/open-watcom/open-watcom-v2/blob/b59d9d9ea5b9266e66efa305f970fe0a51892bb7/bld/clib/startup/c/mainwnt.c#L138-L142 and https://github.com/open-watcom/open-watcom-v2/blob/b59d9d9ea5b9266e66efa305f970fe0a51892bb7/bld/lib_misc/h/osver.h#L43 */
  extern int __stdcall kernel32_SetEndOfFile(int handle);
#  pragma aux kernel32_SetEndOfFile "_SetEndOfFile@4"
  static const char nul_buf[0x1000];
  /* It assumes that the current position is new_ofs, and upon success, it
   * will be the same when it returns. The return value is new_ofs on
   * success, and -1 on error.
   */
  static int64_t fill_fd_with_nul(int64_t new_ofs, int fd, int64_t size) {
    int got;
#  if 0
    msg_printf("info: fill_fd_with_nul: new_ofs=0x%llx size=0x%llx\n", new_ofs, size);
#  endif
    if (!IS_WINNT() && size < new_ofs) {
      if (_lseeki64(fd, size, SEEK_SET) != size) return -1;
      got = -(unsigned)size & (sizeof(nul_buf) - 1);  /* The initiali write would align the file size to a multiple of sizeof(nul_buf). This is for speed. */
      size = new_ofs - size;
      if (!got || (unsigned)got > (uint64_t)size) goto new_got;
      do {
        if ((got = (int)write(fd, nul_buf, got)) <= 0) return -1;
#  if 0
        msg_printf("info: fill_fd_with_nul: got=0x%x\n", got);
#  endif
        size -= (unsigned)got;
       new_got:
        got = (uint64_t)size > sizeof(nul_buf) ? (unsigned)sizeof(nul_buf) : (unsigned)size;
      } while (size > 0);
    }
    return new_ofs;
  }
  /* We fix it because OpenWatcom libc _lseeki64 adds undefined bytes
   * (rather than NUL) bytes when growing the file. This has been verified
   * on Windows 95 OSR2 and WDOSX. (The default syscall (int 21h with
   * AH==40h) on MS-DOS (tested with 6.22 and 7.1) also adds undefined
   * bytes.) SetFilePointer(...) and SetEndOfFile(...) on Windows NT 3.1 and
   * above and derivatives add NUL bytes.
   *
   * This function is not POSIX, because sometimes it explicitly grows the
   * file if seeking beyond EOF, and POSIX would grow it later, after the
   * first non-empty write(2). But it's good enough for bakefat.
   */
  static int64_t bakefat_lseek64(int fd, int64_t offset, int whence) {
    int64_t old_ofs, size, new_ofs;
    if ((old_ofs = _lseeki64(fd, 0, SEEK_CUR)) < 0 ||
        (size = _lseeki64(fd, 0, SEEK_END)) < 0 ||
        (new_ofs = _lseeki64(fd, offset, whence)) < 0) return -1;
    return fill_fd_with_nul(new_ofs, fd, size);  /* Force NUL for newly added bytes. https://stackoverflow.com/q/9809512/97248 */
  }
  /* We fix it because OpenWatcom libc _lseeki64 adds undefined bytes
   * (rather than NUL) bytes when growing the file. This has been verified
   * on Windows 95 OSR2 and WDOSX. (The default syscall (int 21h with
   * AH==40h) on MS-DOS (tested with 6.22 and 7.1) also adds undefined
   * bytes.) SetFilePointer(...) and SetEndOfFile(...) on Windows NT 3.1 and
   * above and derivatives add NUL bytes.
   *
   * Also we have to implement this because OpenWatcom libc doesn't provide
   * a 64-bit chsize(...) or ftruncate(...).
   */
  int bakefat_ftruncate64(int fd, int64_t length) {
    int64_t old_ofs, size;
    if ((old_ofs = _lseeki64(fd, 0, SEEK_CUR)) < 0 ||
        (size = _lseeki64(fd, 0, SEEK_END)) < 0) return -1;
    if (length != size) {
      if (_lseeki64(fd, length, SEEK_SET) != length ||
          !kernel32_SetEndOfFile(_get_osfhandle(fd))) return -1;
      if (!IS_WINNT() && fill_fd_with_nul(length, fd, size) != length) return -1;  /* Force NUL for newly added bytes. https://stackoverflow.com/q/9809512/97248 */
    }
    if (old_ofs != length && _lseeki64(fd, old_ofs, SEEK_SET) != old_ofs) return -1;
    return 0;
  }
#else
  /* FreeBSD and musl have 64-bit off_t, lseek(2) and ftruncate(2) by default. Linux libcs (uClibc, EGLIBC, minilibc686) have it with -D_FILE_OFFSET_BITS=64. */
#  define bakefat_lseek64(fd, offset, whence) lseek(fd, offset, whence)
#  define bakefat_ftruncate64(fd, length) ftruncate(fd, length)
#endif

static const char boot_bin[] =
#  include "boot.h"
;

#define BOOT_OFS_MBR 0
#define BOOT_OFS_FAT32 0x200
#define BOOT_OFS_FAT16 0x400
#define BOOT_OFS_FAT12 0x600
#define BOOT_OFS_FAT12_OFSS 0x800

typedef char assert_sizeof_int[sizeof(int) >= 4 ? 1 : -1];  /* TODO(pts): make printf(3) use the length specifier "l" if int is shorter. */
typedef char assert_sizeof_uint32_t[sizeof(uint32_t) == 4 ? 1 : -1];
typedef char assert_sizeof_boot_bin[sizeof(boot_bin) == 4 * 0x200 + 4 * 2 + 1 ? 1 : -1];

typedef uint8_t ub;
typedef uint16_t uw;
typedef uint32_t ud;

/* GCC >= 4.6 and Clang >= 3.2 have __BYTE_ORDER__ defined. */
#if defined(__i386) || defined(__i386__) || defined(__amd64__) || defined(__x86_64__) || defined(_M_X64) || defined(_M_AMD64) || defined(__386) || \
    defined(__X86_64__) || defined(_M_I386) || defined(_M_I86) || defined(_M_X64) || defined(_M_AMD64) || defined(_M_IX86) || defined(__386__) || \
    defined(__X86__) || defined(__I86__) || defined(_M_I86) || defined(_M_I8086) || defined(_M_I286)
#  define IS_X86 1
#endif
#if defined(__BIG_ENDIAN__) || (defined(__BYTE_ORDER__) && defined(__ORDER_LITTLE_ENDIAN__) && __BYTE_ORDER__ != __ORDER_LITTLE_ENDIAN__) || \
    defined(__ARMEB__) || defined(__THUMBEB__) || defined(__AARCH64EB__) || defined(_MIPSEB) || defined(__MIPSEB) || defined(__MIPSEB__) || \
    defined(__powerpc__) || defined(_M_PPC) || defined(__m68k__) || defined(_ARCH_PPC) || defined(__PPC__) || defined(__PPC) || defined(PPC) || \
    defined(__powerpc) || defined(powerpc) || (defined(__BIG_ENDIAN) && (!defined(__BYTE_ORDER) || __BYTE_ORDER == __BIG_ENDIAN +0)) || \
    defined(_BIG_ENDIAN)
#else
#  if defined(__LITTLE_ENDIAN__) || (defined(__BYTE_ORDER__) && defined(__ORDER_LITTLE_ENDIAN__) && __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__) || \
      defined(__ARMEL__) || defined(__THUMBEL__) || defined(__AARCH64EL__) || defined(_MIPSEL) || defined (__MIPSEL) || defined(__MIPSEL__) || \
      defined(__ia64__) || defined(__LITTLE_ENDIAN) || defined(_LITTLE_ENDIAN) || defined(MSDOS) || defined(__MSDOS__) || IS_X86
#    define IS_LE 1
#  endif
#endif

static char sbuf[0x200];  /* A single sector. */
static char *s;  /* Output pointer within sbuf. */

static int sfd;
static const char *sfn;

static inline void db(ub x) { *s++ = x; }
#ifdef IS_LE
  static inline void dw(uw x) { *(uw*)s = x; s += 2; }
  static inline void dd(ud x) { *(ud*)s = x; s += 4; }
  static inline uw gw(const char *p) { return *(const uw*)p; }
#else
  static uw gw(const char *p) { return ((const unsigned char*)p)[0] | ((const unsigned char*)p)[1] << 8; }
  static void dw(uw x) { *s++ = x & 0xff; *s++ = x >> 8; }
  static void dd(ud x) { *s++ = x & 0xff; *s++ = (x >> 8) & 0xff; *s++ = (x >> 16) & 0xff; *s++ = x >> 24; }
#endif

static void write_sector(ud sofs) {
  const uint64_t ofs = (uint64_t)sofs << 9;
  if ((uint64_t)bakefat_lseek64(sfd, ofs, SEEK_SET) != ofs) {
    msg_printf("fatal: error seeking to sector 0x%x in output file: %s\n", (unsigned)sofs, sfn);
    exit(2);
  }
  if ((size_t)write(sfd, sbuf, sizeof(sbuf)) != sizeof(sbuf)) {
    msg_printf("fatal: error writing to output file: %s\n", sfn);
    exit(2);
  }
}

/* It doesn't seek (i.e. it doesn't modify the file pointer). If it grows the file, it fills with NULs. */
static void set_file_size_scount(ud scount) {
  const uint64_t ofs = (uint64_t)scount << 9;
  if (bakefat_ftruncate64(sfd, ofs) != 0) {  /* It doesn't seek (i.e. it doesn't modify the file pointer). If it grows the file, it fills with NULs. */
    msg_printf("fatal: error setting the size of output file to 0x%x sectors: %s\n", (unsigned)scount, sfn);
    exit(2);
  }
}

/* FAT12 preset indexes. Negative to distinguish from log2_hdd_size. */
enum fat12_preset_idx_t {
  P_160K = -1,
  P_180K = -2,
  P_320K = -3,
  P_360K = -4,
  P_720K = -5,
  P_1200K = -6,
  P_1440K = -7,
  P_2880K = -8
};

struct fat_common_params {
  ud sector_count;
  ud cluster_count;
  uw head_count;
  uw sectors_per_track;
  uw rootdir_entry_count;
  ub media_descriptor;
  ub log2_sectors_per_cluster;  /* Initial, unspecified value: (ub)-1. Valid specified value: 0, ..., 6. */
};

struct fat_params {
  struct fat_common_params fcp;
  ud hidden_sector_count;
  ud volume_id;
  uw reserved_sector_count;
  uw sectors_per_fat;
  uw default_rootdir_entry_count;
  uw default_reserved_sector_count;
  ub default_log2_sectors_per_cluster;
  ub default_fat_count;
  ub fat_count;  /* 0 (unspecified), 1 or 2. */
  ub fat_fstype;  /* 0 (unspecified), 12, 16 or 32. */
};

struct fat12_preset {
  const char *name;
  struct fat_common_params fcp;
  uw expected_sectors_per_fat;
};

/* !! Add superfloppy formats. */
static const struct fat12_preset fat12_presets[] = {
    /* ~P_160K: */  { "160K",  {  320,  313, 1,  8,  64, 0xfe, 0 }, 1 },
    /* ~P_180K: */  { "180K",  {  360,  351, 1,  9,  64, 0xfc, 0 }, 2 },
    /* ~P_320K: */  { "320K",  {  640,  315, 2,  8, 112, 0xff, 1 }, 1 },
    /* ~P_360K: */  { "360K",  {  720,  354, 2,  9, 112, 0xfd, 1 }, 2 },
    /* ~P_720K: */  { "720K",  { 1440,  713, 2,  9, 112, 0xf9, 1 }, 3 },
    /* ~P_1200K: */ { "1200K", { 2400, 2371, 2, 15, 224, 0xf9, 0 }, 7 },
    /* ~P_1440K: */ { "1440K", { 2880, 2847, 2, 18, 224, 0xf0, 0 }, 9 },
    /* ~P_2880K: */ { "2880K", { 5760, 2863, 2, 36, 240, 0xf0, 1 }, 9 },
};

enum boot_signature_t { BOOT_SIGNATURE = 0xaa55, EXTENDED_BOOT_SIGNATURE = 0x29 };

static const char oem_name[] = "MSDOS5.0";

static noreturn void fatal0(const char *msg) {
  msg_printf("fatal: %s\n", msg);
  exit(2);
}

static void check_rootdir_entry_count(uw rootdir_entry_count) {
  /* Rootdir entry count must be a multiple of 0x10.  ; Some DOS msload boot code relies on this (i.e. rounding down == rounding up). */
  if ((ub)rootdir_entry_count & 0xf) fatal0("BAD_ROOTDIR_ENTRY_COUNT");
}

static void check_log2_sectors_per_cluster(ub log2_sectors_per_cluster) {
  /* Rootdir entry count must be between 0 (512B) and 6 (32K). */
  if (log2_sectors_per_cluster > 6) fatal0("BAD_SECTORS_PER_CLUSTER");
}

static void create_fat12(enum fat12_preset_idx_t pri) {
  const struct fat12_preset *pr = &fat12_presets[~pri];
  const ud fat_volume_id = 0x1234abcd;  /* 1234-ABCD. !! Make it configurable. */
  const ud fat_sector_size = 0x200;
  const ub fat_fat_count = 2;  /* !! Make this configurable. */
  const ub fat_reserved_sector_count = 1;  /* Only the boot sector. */
  const ud fat_hidden_sector_count = 0;  /* No sectors preceding the boot sector. */
  const ud fat_sectors_per_fat = (((((ud)pr->fcp.cluster_count + 2) * 3 + 1) >> 1) + 0x1ff) >> 9;  /* Good formula for FAT12. We have the +2 here because clusters 0 and 1 have a next-pointer in the FATs, but they are not stored on disk. */
  const ud fat_rootdir_sector_count = ((ud)pr->fcp.rootdir_entry_count + 0xf) >> 4;
  const ud fat_fat_sec_ofs = fat_hidden_sector_count + fat_reserved_sector_count;
  const ud fat_rootdir_sec_ofs = fat_fat_sec_ofs + fat_fat_count * fat_sectors_per_fat;
  const ud fat_clusters_sec_ofs = fat_rootdir_sec_ofs + fat_rootdir_sector_count;
  const ud fat_minimum_sector_count = fat_clusters_sec_ofs + ((ud)pr->fcp.cluster_count << pr->fcp.log2_sectors_per_cluster) - fat_hidden_sector_count;
  const ud fat_maximum_sector_count = fat_minimum_sector_count + (ud)(1 << pr->fcp.log2_sectors_per_cluster) - 1;

#  ifdef DEBUG
    msg_printf("info: sector_count %lu <= %lu <= %lu\n", (unsigned long)fat_minimum_sector_count, (unsigned long)pr->fcp.sector_count, (unsigned long)fat_maximum_sector_count);
#  endif
  check_rootdir_entry_count(pr->fcp.rootdir_entry_count);
  check_log2_sectors_per_cluster(pr->fcp.log2_sectors_per_cluster);
  /* Bad number of sectors per FAT. */
  if (fat_sectors_per_fat != pr->expected_sectors_per_fat) fatal0("BAD_SECTORS_PER_FAT");
  /* Too many sectors. */
  if (pr->fcp.sector_count < fat_minimum_sector_count) fatal0("TOO_MANY_SECTORS");
  /* Too few sectors. */
  if (pr->fcp.sector_count > fat_maximum_sector_count) fatal0("TOO_FEW_SECTORS");
  /* Too many sectors, not supported by our FAT12 boot code. */
  if (sizeof(pr->fcp.sector_count) > 2 && pr->fcp.sector_count > 0xffff - (sizeof(pr->fcp.sector_count) <= 2)) fatal0("TOO_MANY_SECTORS_FOR_FAT12");
  /* Some operating systems detect more clusters than this as FAT16. */
  if (pr->fcp.cluster_count > 0xfee) fatal0("TOO_MANY_CLUSTERS_FOR_FAT12");

  memcpy(sbuf, boot_bin + BOOT_OFS_FAT12, 0x200);
  /* .header: jmp strict short .boot_code */
  /* nop  ; 0x90 for CHS. Another possible value is 0x0e for LBA. Who uses it? It is ignored by .boot_code. */
  s = sbuf + 3;  /* More info about FAT12, FAT16 and FAT32: https://en.wikipedia.org/wiki/Design_of_the_FAT_file_system */
  memcpy(s, oem_name, 8); s += 8;
  dw(fat_sector_size);  /* The value 0x200 is hardcoded in boot_sector.boot_code, both explicitly and implicitly. */
  db((ub)1 << pr->fcp.log2_sectors_per_cluster);
  dw(fat_reserved_sector_count);
  db(fat_fat_count);  /* Must be 1 or 2. MS-DOS 6.22 supports only 2. Windows 95 DOS mode supports 1 or 2. */
  dw(pr->fcp.rootdir_entry_count);  /* Each FAT directory entry is 0x20 bytes. Each sector is 0x200 bytes. */
  dw(sizeof(pr->fcp.sector_count) > 2 && pr->fcp.sector_count > 0xffff - (sizeof(pr->fcp.sector_count) <= 2)? 0 : pr->fcp.sector_count);  /* 0 doesn't happen for our FAT12. */
  db(pr->fcp.media_descriptor);   /* 0xf8 for HDD. 0xf8 is also used by some nonstandard floppy disk formats. */
  dw(fat_sectors_per_fat);
  /* FreeDOS 1.2 `dir c:' needs a correct value for .sectors_per_track and .head_count. MS-DOS 6.22 and FreeDOS 1.3 ignore these values (after boot). */
  dw(pr->fcp.sectors_per_track);  /* Track == cylinder. Dummy nonzero value to pacify mtools(1). Here it is not overwritten with value from BIOS int 13h AH == 8. */
  dw(pr->fcp.head_count);  /* Dummy nonzero value to pacify mtools(1). Here it is not overwritten with value from BIOS int 13h AH == 8. */
  dd(fat_hidden_sector_count); /* Occupied by MBR and previous partitions. */
  dd(pr->fcp.sector_count);
  if (0) {  /* These are already correct in boot_bin. */
    db(0);  /* fat_drive_number. */
    db(0);  /* fat_var_unused. Can be used as a temporary variable in .boot_code. */
    db(EXTENDED_BOOT_SIGNATURE);
    dd(fat_volume_id);
    memcpy(s, "NO NAME    ", 11); s += 11;  /* volume_label. */
    memcpy(s, "FAT12   ", 8); s += 8;  /* fstype. */
  }

  /* Patch some constants in the boot code. */
  s = sbuf + gw(boot_bin + BOOT_OFS_FAT12_OFSS + 0); dw(fat_clusters_sec_ofs);
  s = sbuf + gw(boot_bin + BOOT_OFS_FAT12_OFSS + 2); dw(pr->fcp.rootdir_entry_count);
  s = sbuf + gw(boot_bin + BOOT_OFS_FAT12_OFSS + 4); dw(fat_rootdir_sec_ofs);
  s = sbuf + gw(boot_bin + BOOT_OFS_FAT12_OFSS + 6); dw(fat_fat_sec_ofs);

  write_sector(0);
  memset(s = sbuf, 0, sizeof(sbuf));
  db(pr->fcp.media_descriptor);
  dw(-1);
  write_sector(fat_fat_sec_ofs);
  if (fat_fat_count > 1) write_sector(fat_fat_sec_ofs + fat_sectors_per_fat);
  set_file_size_scount(pr->fcp.sector_count);
}

static const char *hdd_size_presets_m_21[] = {
    "2M", "4M", "8M", "16M", "32M", "64M", "128M", "256M", "512M", "1024M",
    "2048M", "4096M", "8192M", "16384M", "32768M", "65536M", "131072M",
    "262144M", "524288M", "1048576M", "2097152M",
};

static const char *hdd_size_presets_g_30[] = {
    "1G", "2G", "4G", "8G", "16G", "32G", "64G", "128G", "256G", "512G",
    "1024G", "2048G",
};

static const char *hdd_size_presets_t_40[] = {
    "1T", "2T",
};

static const char *sectors_per_cluster_presets_b_9[] = {
    "512B", "1024B", "2048B", "4096B", "8192B", "16384B", "32768B",
};

static const char *sectors_per_cluster_presets_s_9[] = {
    "1S", "2S", "4S", "8S", "16S", "32S", "64S",
};

static const char *sectors_per_cluster_presets_k_10[] = {
    "1K", "2K", "4K", "8K", "16K", "32K",
};

static noreturn void usage(ub is_help, const char *argv0) {
  char *p = sbuf;  /* TODO(pts): Check for overflow below. */
  const char **csp;
  const char *q, *cluster_size_flags, *hdd_image_size_flags;
  const struct fat12_preset *prp;
  /* TODO(pts): Precompute this help message, making the code shorter. */
  for (prp = fat12_presets; prp != ARRAY_END(fat12_presets); ++prp) {
    for (q = prp->name, *p++ = ' '; *q != '\0'; *p++ = *q++) {}
  }
  *p++ = '\0';
  hdd_image_size_flags = p;
  for (csp = hdd_size_presets_m_21; csp != ARRAY_END(hdd_size_presets_m_21); ++csp) {
    if (strcmp(*csp, "1024M") == 0) break;
    for (q = *csp, *p++ = ' '; *q != '\0'; *p++ = *q++) {}
  }
  for (csp = hdd_size_presets_g_30; csp != ARRAY_END(hdd_size_presets_g_30); ++csp) {
    if (strcmp(*csp, "1024G") == 0) break;
    for (q = *csp, *p++ = ' '; *q != '\0'; *p++ = *q++) {}
  }
  for (csp = hdd_size_presets_t_40; csp != ARRAY_END(hdd_size_presets_t_40); ++csp) {
    for (q = *csp, *p++ = ' '; *q != '\0'; *p++ = *q++) {}
  }
  *p++ = '\0';
  cluster_size_flags = p;
  for (csp = sectors_per_cluster_presets_k_10; csp != ARRAY_END(sectors_per_cluster_presets_k_10); ++csp) {
    for (q = *csp, *p++ = ' '; *q != '\0'; *p++ = *q++) {}
  }
  *p = '\0';
  /* This help message doesn't contain some alternate spellings of some flags. */
  msg_printf("bakefat: bootable external FAT disk image creator v%d\n"
             "Usage: %s <flag> [...] <outfile.img>\n"
             "Floppy image size flags:%s\n"
             "HDD image size flags:%s\n"
             "Cluster size flags: 512B%s\n"
             "Filesystem type flags: FAT12 FAT16 FAT32\n"
             "FAT count flags: 1FAT 2FATS\n",
             BAKEFAT_VERSION, argv0, sbuf, hdd_image_size_flags, cluster_size_flags);
  exit(is_help ? 0 : 1);
}

static noreturn void bad_usage0(const char *msg) {
  msg_printf("fatal: %s\n", msg);
  exit(1);
}

int main(int argc, char **argv) {
  const char **arg, **arge, **argfn = NULL;
  const char *flag;
  ub is_help;
  int log2_size = 0;  /* Unspecified. */
  const struct fat12_preset *prp;
  const char **csp;
  struct fat_params fp;
  int min_log2_spc;
  uw old_sectors_per_fat;

  (void)argc;
#  ifdef __MMLIBC386__
  stdout_fd = STDERR_FILENO;  /* For msg_printf(...). */
#  endif
  memset(&fp, '\0', sizeof(fp));
  fp.fcp.log2_sectors_per_cluster = (ub)-1;  /* Unspecified. */
  fp.volume_id = 0x1234abcd;  /* !! Add command-line flag to make it configurable. */
  is_help = argv[1] && strcasecmp(argv[1], "--help") == 0;
  for (arge = (const char **)argv + 1; ; ++arge) {
    if (!*arge) {  /* The last argument is the output image file name (<outfile.img>). */
      argfn = --arge;
      if ((char**)argfn != argv && argfn[0][0] == '-') argfn = ++arge;
      break;
    }
    if (strcmp(*arge, "--") == 0) {
      argfn = arge + 1;
      break;
    }
  }
  if (is_help || (char**)argfn == argv) usage(is_help, argv[0]);
  for (arg = (const char **)argv + 1; arg != arge; ++arg) {
    /* !! Add number-of-FATs flag. */
    /* !! Add operating system compatibility flag (e.g. FAT32, 1FAT). */
    /* !! Make fat_rootdir_entry_count configurable. */
    /* !! Make floppy parameters configurable. */
    for (flag = *arg; *flag == '-' || *flag == '/'; ++flag) {}  /* Skip leading - and / characters in flag. */
    for (prp = fat12_presets; prp != ARRAY_END(fat12_presets); ++prp) {
      if (strcasecmp(flag, prp->name) == 0) {
        if (log2_size != 0) { error_multiple_size:
          bad_usage0("multiple image sizes specified");
        }
        log2_size = ~(prp - fat12_presets);  /* !! Get rid of this. */
        fp.fcp = prp->fcp;  /* This is a memcpy(). */
        fp.default_fat_count = 2;
        fp.default_reserved_sector_count = 1;
        fp.default_rootdir_entry_count = fp.fcp.rootdir_entry_count;
        fp.default_log2_sectors_per_cluster = fp.fcp.log2_sectors_per_cluster;
        fp.fcp.rootdir_entry_count = 0;  /* Can be changed. */
        fp.fcp.log2_sectors_per_cluster = (ub)-1;  /* Can be changed. */
        fp.fat_fstype = 12;
        goto next_flag;
      }
    }
    for (csp = hdd_size_presets_m_21; csp != ARRAY_END(hdd_size_presets_m_21); ++csp) {
      if (strcasecmp(flag, *csp) == 0) { if (log2_size) goto error_multiple_size; log2_size = csp - hdd_size_presets_m_21 + 21; goto next_flag; }
    }
    for (csp = hdd_size_presets_g_30; csp != ARRAY_END(hdd_size_presets_g_30); ++csp) {
      if (strcasecmp(flag, *csp) == 0) { if (log2_size) goto error_multiple_size; log2_size = csp - hdd_size_presets_g_30 + 30; goto next_flag; }
    }
    for (csp = hdd_size_presets_t_40; csp != ARRAY_END(hdd_size_presets_t_40); ++csp) {
      if (strcasecmp(flag, *csp) == 0) { if (log2_size) goto error_multiple_size; log2_size = csp - hdd_size_presets_t_40 + 40; goto next_flag; }
    }
    for (csp = sectors_per_cluster_presets_b_9; csp != ARRAY_END(sectors_per_cluster_presets_b_9); ++csp) {
      if (strcasecmp(flag, *csp) == 0) {
        if (fp.fcp.log2_sectors_per_cluster != (ub)-1) { error_multiple_spc:
          bad_usage0("multiple sectors-per-cluster specified");
        }
        fp.fcp.log2_sectors_per_cluster = csp - sectors_per_cluster_presets_b_9 + 9 - 9;
        goto next_flag;
      }
    }
    for (csp = sectors_per_cluster_presets_s_9; csp != ARRAY_END(sectors_per_cluster_presets_s_9); ++csp) {
      if (strcasecmp(flag, *csp) == 0) { if (fp.fcp.log2_sectors_per_cluster) goto error_multiple_spc; fp.fcp.log2_sectors_per_cluster = csp - sectors_per_cluster_presets_s_9 + 9 - 9; goto next_flag; }
    }
    for (csp = sectors_per_cluster_presets_k_10; csp != ARRAY_END(sectors_per_cluster_presets_k_10); ++csp) {
      if (strcasecmp(flag, *csp) == 0) { if (fp.fcp.log2_sectors_per_cluster) goto error_multiple_spc; fp.fcp.log2_sectors_per_cluster = csp - sectors_per_cluster_presets_k_10 + 10 - 9; goto next_flag; }
    }
    if (strcasecmp(flag, "FAT12") == 0) {
      if (fp.fat_fstype && fp.fat_fstype != 12) { error_multiple_fat_fstype:
        bad_usage0("multiple FAT type flags specified");
      }
      fp.fat_fstype = 12;
    } else if (strcasecmp(flag, "FAT16") == 0) {
      if (fp.fat_fstype && fp.fat_fstype != 16) goto error_multiple_fat_fstype;
      fp.fat_fstype = 16;
    } else if (strcasecmp(flag, "FAT32") == 0) {
      if (fp.fat_fstype && fp.fat_fstype != 32) goto error_multiple_fat_fstype;
      fp.fat_fstype = 32;
    } else if (strcasecmp(flag, "1FAT") == 0 || strcasecmp(flag, "1F") == 0) {
      if (fp.fat_fstype && fp.fat_fstype != 12) { error_multiple_fat_count:
        bad_usage0("multiple FAT FAT counts specified");
      }
      fp.fat_count = 1;
    } else if (strcasecmp(flag, "2FATS") == 0 ||strcasecmp(flag, "2F") == 0) {
      if (fp.fat_fstype && fp.fat_fstype != 16) goto error_multiple_fat_count;
      fp.fat_count = 2;
    } else {
      msg_printf("fatal: unknown command-line flag: %s\n", flag);
      exit(1);
    }
   next_flag: ;
  }
  if (!*argfn) bad_usage0("output filename not specified");
  if (argfn[1]) bad_usage0("multiple output filenames specified");
  sfn = *argfn;

  if (!fp.fat_fstype) {  /* Autodetect. FAT12 is already enabled above for floppies. */
    fp.fat_fstype = log2_size <= 31 ? 16 : 32;  /* Use FAT16 for up to 2 GiB, use FAT32 for anything larger. FAT16 doesn't support more than 2 GiB. */
  }
  if (!fp.fat_count) {  /* Autodetect. */
    if ((fp.fat_count = fp.default_fat_count) == 0) {
      fp.fat_count = fp.fat_fstype == 32 ? 1 : 2;  /* 2 for compatibility with MS-DOS <=6.22. */
    }
  }
  if (!fp.reserved_sector_count) {  /* Autodetect. */
    if ((fp.reserved_sector_count = fp.default_reserved_sector_count) == 0) {
      fp.reserved_sector_count = fp.fat_fstype == 32 ? 17 : 1;  /* 17 for compatibility with the Windows XP FAT32 boot sector code, which loads additional boot code from sector 8. */
    }
  }
  if (!fp.fcp.rootdir_entry_count) {
    if ((fp.fcp.rootdir_entry_count = fp.default_rootdir_entry_count) == 0) {  /* Autodetect. */
      fp.fcp.rootdir_entry_count = 256;
    }
    fp.fcp.rootdir_entry_count = (fp.fcp.rootdir_entry_count + 0xf) & ~0xf;  /* Round up to a multiple of 16. */
  }
  if (fp.fat_fstype == 32) fp.fcp.rootdir_entry_count = 0;
  if (fp.fcp.log2_sectors_per_cluster == (ub)-1) fp.fcp.log2_sectors_per_cluster = fp.default_log2_sectors_per_cluster;  /* Can still be (ub)-1 (unspecified) for non-floppy. */
  if (log2_size < 0) {  /* Floppy FAT12. */
    /* This is ensured above: if (fp.fat_fstype != 12) bad_usage0("only FAT12 is supported for floppy images"); */
    if (fp.fcp.rootdir_entry_count != fp.default_rootdir_entry_count ||
        fp.fcp.log2_sectors_per_cluster != fp.default_log2_sectors_per_cluster ||
        fp.reserved_sector_count != fp.default_reserved_sector_count ||
        fp.fat_count != fp.default_fat_count ||
        0) fp.fcp.cluster_count = 0;  /* Recalculate from fp.sector_count below. */
  } else {
    fp.hidden_sector_count = 63;  /* Partition 1 starts here. */
    if (!log2_size) bad_usage0("image size not specified");
#    ifdef DEBUG
      if (log2_size < 21) fatal0("ASSERT_IMAGE_TOO_SMALL");
      if (log2_size > 43) fatal0("ASSERT_IMAGE_TOO_LARGE");
#    endif
    if (fp.fat_fstype == 12) {
      bad_usage0("FAT12 is not supported for hard disk images");  /* Because boot code is not implemented. */
    } else if (fp.fat_fstype == 16) {
      /* No need to check `if (log2_size < 12 + 9) bad_usage0("FAT16 too small");', because we we have log_size >= 21 (2M) here, we don't support smaller values. */
      if (log2_size > 16 + 15) bad_usage0("FAT16 too large");
    } else /* if (fp.fat_fstype == 32) */ {
      if (log2_size < 16 + 9) bad_usage0("FAT32 too small");
      /* No need to check `if (log2_size > 28 + 15) bad_usage0("FAT32 too large");', because we we have log_size <= 41 (2T) <= 43 here, we don't support larger values. */
    }
    /* Cluster count limits:
     * For FAT16: 12 <= log2_size - (log2_spc + 9) <= 16.  log2_size - 25 <= log2_spc <= log2_size - 21.
     * For FAT32: 16 <= log2_size - (log2_spc + 9) <= 28.  log2_size - 37 <= log2_spc <= log2_size - 25.
     */
    if (fp.fcp.log2_sectors_per_cluster == (ub)-1) {
      if (fp.fat_fstype == 16) {
        min_log2_spc = (int)log2_size - 25;
        fp.fcp.log2_sectors_per_cluster = min_log2_spc >= 0 ? min_log2_spc : 0;
      } else {
        min_log2_spc = (int)log2_size - 37;
        /* Use 4K clusters if possible. */
        fp.fcp.log2_sectors_per_cluster = log2_size == 26 ? 1 : log2_size == 27 ? 2 : log2_size - 28U <= 40U - 28U ? 3 : min_log2_spc >= 0 ? min_log2_spc : 0;
      }
    } else {
      min_log2_spc = log2_size - fp.fcp.log2_sectors_per_cluster - (fp.fat_fstype == 16 ? 16U + 9U : 28U + 9U);
      if (min_log2_spc < 0) bad_usage0("sectors-per-cluster too large for this FAT size");
      if (min_log2_spc > 6) bad_usage0("sectors-per-cluster too small for this FAT size");
    }
    if (!fp.fcp.cluster_count) {
      fp.fcp.cluster_count = ((ud)1 << (log2_size - (fp.fcp.log2_sectors_per_cluster + 9U))) - 2;  /* -2 is for the 2 special cluster entries at the beginning of the FAT table. */
      fp.sectors_per_fat = fp.fat_fstype == 32 ? (ud)0 : /* fat16: */ (fp.fcp.cluster_count + (2U + 0xffU)) >> 8;
      /* fp.fcp.cluster_count = (fp.fat_fstype == 16 ? auto_fat16_cluster_counts_12 - 12 : auto_fat32_cluster_counts_16 - 16)[log2_size - (fp.fcp.log2_sectors_per_cluster + 9U)]; */
      if (fp.fat_fstype && fp.fcp.cluster_count == 0x10000 - 2) fp.fcp.cluster_count -= 0x10;  /* Maximum 0xffee clusters on a FAT16 filesystem, to avoid detection as FAT32. !! Is this needed? Where is it documented? */
    }
    bad_usage0("!! FAT16--32 not supported");
  }
  if (!fp.fcp.cluster_count) {  /* !! Also consider alignment. */  /* !! Test floppy presets. */
#  if DEBUG
    if (fp.fat_fstype != 12) fatal0("ASSERT_FAT12");
    if (!fp.fcp.sector_count) fatal0("ASSERT_SECTORS");
    if (fp.sectors_per_fat) fatal0("ASSERT_SECTORS_PER_FAT");
#  endif
    do {
      old_sectors_per_fat = fp.sectors_per_fat;
      fp.fcp.cluster_count = (fp.fcp.sector_count - fp.hidden_sector_count - fp.reserved_sector_count - ((ud)fp.sectors_per_fat << (fp.fat_count - 1)) - (fp.fcp.rootdir_entry_count >> 4)) >> fp.fcp.log2_sectors_per_cluster;
      fp.sectors_per_fat = ((((fp.fcp.cluster_count + 2) * 3 + 1) >> 1) + 0x1ff) >> 9;  /* FAT12. */
    } while (fp.sectors_per_fat != old_sectors_per_fat);  /* Repeat until a fixed point is found for (fp.fcp.cluster_count, fp.sectors_per_fat). */
    fatal0("!! custom FAT12 not supported");
  }
  if ((sfd = open(sfn, O_WRONLY | O_CREAT | O_TRUNC | O_BINARY, 0666)) < 0) {
    msg_printf("fatal: error opening output file: %s\n", sfn);
    exit(2);
  }
  if (log2_size < 0) {  /* FAT12 floppy image. */
    create_fat12(log2_size);
  } else {
    bad_usage0("FAT16 and FAT32 not supported yet");
  }
  close(sfd);
  return 0;
}
