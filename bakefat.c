/*
 * bakefat.c: bootable external FAT hard disk image creator for DOS and Windows 3.1--95--98--ME
 * by pts@fazekas.hu at Thu Feb  6 14:32:22 CET 2025
 *
 * Compilr with OpenWatcom C compiler, minilibc686 for Linux i386: minicc -march=i386 -Werror -Wno-n201 -o bakefat bakefat.c
 * Compile with GCC for Unix: gcc -ansi -pedantic -W -Wall -Wno-overlength-strings -Werror -s -O2 -o bakefat bakefat.c
 * Compile with OpenWatcom C compiler for Win32: owcc -bwin32 -Wl,runtime -Wl,console=3.10 -Os --fno-stack-check -march=i386 -W -Wall -Wno-n201 -o bakefat.exe bakefat.c
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

#ifdef __GNUC__
#  ifndef inline
#    define inline __inline__  /* For `gcc -ansi -pedantic'. */
#  endif
#endif

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

/* FAT12 preset indexes. */
enum fat12_preset_idx_t {
  P_160K = 0,
  P_180K = 1,
  P_320K = 2,
  P_360K = 3,
  P_720K = 4,
  P_1200K = 5,
  P_1440K = 6,
  P_2880K = 7
};

struct fat12_preset {
  const char *name;
  uw sector_count;
  uw head_count;
  ub sectors_per_track;
  ub media_descriptor;
  ub sectors_per_cluster;
  uw rootdir_entry_count;
  uw cluster_count;
  uw expected_sectors_per_fat;
};

static const struct fat12_preset fat12_presets[] = {
    /* P_160K: */  { "160k",  320, 1, 8, 0xfe, 1, 64, 313, 1 },
    /* P_180K: */  { "180k",  360, 1, 9, 0xfc, 1, 64, 351, 2 },
    /* P_320K: */  { "320k",  640, 2, 8, 0xff, 2, 112, 315, 1 },
    /* P_360K: */  { "360k",  720, 2, 9, 0xfd, 2, 112, 354, 2 },
    /* P_720K: */  { "720k",  1440, 2, 9, 0xf9, 2, 112, 713, 3 },
    /* P_1200K: */ { "1200k", 2400, 2, 15, 0xf9, 1, 224, 2371, 7 },
    /* P_1440K: */ { "1440k", 2880, 2, 18, 0xf0, 1, 224, 2847, 9 },
    /* P_2880K: */ { "2880k", 5760, 2, 36, 0xf0, 2, 240, 2863, 9 },
};

enum boot_signature_t { BOOT_SIGNATURE = 0xaa55, EXTENDED_BOOT_SIGNATURE = 0x29 };

static const char oem_name[] = "MSDOS5.0";

static void create_fat12(enum fat12_preset_idx_t pri) {
  const struct fat12_preset *pr = &fat12_presets[pri];
  const ud fat_volume_id = 0x1234abcd;  /* 1234-ABCD. !! Make it configurable. */
  const ud fat_sector_size = 0x200;
  const ub fat_fat_count = 2;  /* !! Make this configurable. */
  const ub fat_reserved_sector_count = 1;  /* Only the boot sector. */
  const ud fat_hidden_sector_count = 0;  /* No sectors preceding the boot sector. */
  const ud fat_sectors_per_fat = (((((ud)pr->cluster_count+2)*3+1)>>1)+0x1ff)>>9;  /* Good formula for FAT12. We have the +2 here because clusters 0 and 1 have a next-pointer in the FATs, but they are not stored on disk. */
  const ud fat_rootdir_sector_count = ((ud)pr->rootdir_entry_count+0xf)>>4;
  const ud fat_fat_sec_ofs = fat_hidden_sector_count+fat_reserved_sector_count;
  const ud fat_rootdir_sec_ofs = fat_fat_sec_ofs+fat_fat_count*fat_sectors_per_fat;
  const ud fat_clusters_sec_ofs = fat_rootdir_sec_ofs+fat_rootdir_sector_count;
  const ud fat_minimum_sector_count = fat_clusters_sec_ofs+(ud)pr->cluster_count*(ud)pr->sectors_per_cluster-fat_hidden_sector_count;
  const ud fat_maximum_sector_count = fat_minimum_sector_count+(ud)pr->sectors_per_cluster-1;

  if ((ud)pr->rootdir_entry_count & 0xf) {
    msg_printf("fatal: BAD_ROOTDIR_ENTRY_COUNT\n");  /* Rootdir entry count must be a multiple of 0x10.  ; Some DOS msload boot code relies on this (i.e. rounding down == rounding up). */
    exit(2);
  }
  if (fat_sectors_per_fat != pr->expected_sectors_per_fat) {
    msg_printf("fatal: BAD_SECTORS_PER_FAT\n");  /* Bad number of sectors per FAT. */
    exit(2);
  }
  if (pr->sector_count < fat_minimum_sector_count) {
    msg_printf("fatal: TOO_MANY_SECTORS\n");  /* Too many sectors. */
    exit(2);
  }
  if (pr->sector_count > fat_maximum_sector_count) {
    msg_printf("fatal: TOO_FEW_SECTORS\n");  /* Too few sectors. */
    exit(2);
  }
  if (sizeof(pr->sector_count) > 2 && pr->sector_count > 0xffff - (sizeof(pr->sector_count) <= 2)) {
    msg_printf("fatal: TOO_MANY_SECTOS_FOR_FAT12\n");  /* Too many sectors, not supported by our FAT12 boot code. */
    exit(2);
  }
  memcpy(sbuf, boot_bin + BOOT_OFS_FAT12, 0x200);
  /* .header: jmp strict short .boot_code */
  /* nop  ; 0x90 for CHS. Another possible value is 0x0e for LBA. Who uses it? It is ignored by .boot_code. */
  s = sbuf + 3;  /* More info about FAT12, FAT16 and FAT32: https://en.wikipedia.org/wiki/Design_of_the_FAT_file_system */
  memcpy(s, oem_name, 8); s += 8;
  dw(fat_sector_size);  /* The value 0x200 is hardcoded in boot_sector.boot_code, both explicitly and implicitly. */
  db(pr->sectors_per_cluster);
  dw(fat_reserved_sector_count);
  db(fat_fat_count);  /* Must be 1 or 2. MS-DOS 6.22 supports only 2. Windows 95 DOS mode supports 1 or 2. */
  dw(pr->rootdir_entry_count);  /* Each FAT directory entry is 0x20 bytes. Each sector is 0x200 bytes. */
  dw(sizeof(pr->sector_count) > 2 && pr->sector_count > 0xffff - (sizeof(pr->sector_count) <= 2)? 0 : pr->sector_count);  /* 0 doesn't happen for our FAT12. */
  db(pr->media_descriptor);   /* 0xf8 for HDD. 0xf8 is also used for some floppy disk formats as well. */
  dw(fat_sectors_per_fat);
  /* FreeDOS 1.2 `dir c:' needs a correct value for .sectors_per_track and .head_count. MS-DOS 6.22 and FreeDOS 1.3 ignore these values (after boot). */
  dw(pr->sectors_per_track);  /* Track == cylinder. Dummy nonzero value to pacify mtools(1). Here it is not overwritten with value from BIOS int 13h AH == 8. */
  dw(pr->head_count);  /* Dummy nonzero value to pacify mtools(1). Here it is not overwritten with value from BIOS int 13h AH == 8. */
  dd(fat_hidden_sector_count); /* Occupied by MBR and previous partitions. */
  dd(pr->sector_count);
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
  s = sbuf + gw(boot_bin + BOOT_OFS_FAT12_OFSS + 2); dw(pr->rootdir_entry_count);
  s = sbuf + gw(boot_bin + BOOT_OFS_FAT12_OFSS + 4); dw(fat_rootdir_sec_ofs);
  s = sbuf + gw(boot_bin + BOOT_OFS_FAT12_OFSS + 6); dw(fat_fat_sec_ofs);

  write_sector(0);
  memset(s = sbuf, 0, sizeof(sbuf));
  db(pr->media_descriptor);
  dw(-1);
  write_sector(fat_fat_sec_ofs);
  if (fat_fat_count > 1) write_sector(fat_fat_sec_ofs + fat_sectors_per_fat);
  set_file_size_scount(pr->sector_count);
}

int main(int argc, char **argv) {
  char is_help;
  (void)argc;
#  ifdef __MMLIBC386__
  stdout_fd = STDERR_FILENO;  /* For msg_printf(...). */
#  endif
  is_help = argv[1] && strcmp(argv[1], "--help") == 0;
  if (is_help || !argv[1] || !argv[2] || argv[3]) {
    msg_printf("Usage: %s <preset> <outfile.img>\n", argv[0]);
    exit(is_help ? 0 : 1);
  }
  if (strcasecmp(argv[1], "720k") != 0) {
    msg_printf("fatal: unknown preset: %s\n", argv[1]);
    exit(2);
  }
  sfn = argv[2];
  if ((sfd = open(sfn, O_WRONLY | O_CREAT | O_TRUNC | O_BINARY, 0666)) < 0) {
    msg_printf("fatal: error opening output file: %s\n", sfn);
    exit(2);
  }
  create_fat12(P_720K);
  close(sfd);
  return 0;
}
