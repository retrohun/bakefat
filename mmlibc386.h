/* by pts@fazekas.hu at Sun Feb  9 15:37:04 CET 2025 */

#ifndef _MMLIBC386_H
#define _MMLIBC386_H 1

#ifndef __WATCOMC__
  #error OpenWatcom C compiler required.
#endif
#ifdef __cplusplus
  #error C compiler required rather than C++.
#endif
#ifndef __386__
  #error i386 CPU required.
#endif
#ifndef __FLAT__
  #error Flat memory model required.
#endif
#ifdef __COMDEF_H_INCLUDED
  #error OpenWatcom libc must not be used (__COMDEF_H_INCLUDED).
#endif
#ifdef _WCDATA
  #error OpenWatcom libc must not be used (_WCDATA).
#endif

/* Prevent subsequent #includes()s of some OpenWatcom libc headers. */
#define _IO_H_INCLUDED 1
#define _STDIO_H_INCLUDED 1
#define _STDLIB_H_INCLUDED 1
#define _STDDEF_H_INCLUDED 1
#define _STDARG_H_INCLUDED 1
#define _STDBOOL_H_INCLUDED 1
#define _STDEXCEPT_H_INCLUDED 1
#define _STDINT_H_INCLUDED 1
#define _STDIOBUF_H_INCLUDED 1
#define _UNISTD_H_INCLUDED 1
#define _LIMITS_H_INCLUDED 1
#define _FLOAT_H_INCLUDED 1
#define _MATH_H_INCLUDED 1
#define _CTYPE_H_INCLUDED 1
#define _STRING_H_INCLUDED 1
#define _STRINGS_H_INCLUDED 1
#define _FCNTL_H_INCLUDED 1
#define _ERRNO_H_INCLUDED 1
#define _SYS_TYPES_H_INCLUDED 1
#define _SYS_TIME_H_INCLUDED 1
#define _SYS_UTIME_H_INCLUDED 1
#define _SYS_SELECT_H_INCLUDED 1
#define _SYS_MMAN_H_INCLUDED 1
#define _SYS_IOCTL_H_INCLUDED 1
#define _SYS_WAIT_H_INCLUDED 1

/* For compatibility with GCC (__GNUC__). */
#if !defined(__i386__) && (defined(_M_I386) || defined(__386__))
#  define __i386__ 1  /* Matches __GNUC__. */
#endif
#if _M_IX86 >= 400 && !defined(__i486__) && _M_IX86 < 500
#  define __i486__ 1  /* Matches __GNUC__. */
#endif
#if _M_IX86 >= 500 && !defined(__i586__) && _M_IX86 < 600
#  define __i586__ 1  /* Matches __GNUC__. */
#endif
#if _M_IX86 >= 600 && !defined(__i686__)
#  define __i686__ 1  /* Matches __GNUC__. */
#endif
#define __extension__  /* Ignore __GNUC__ construct. */
#define __restrict__  /* Ignore __GNUC__ construct. */
#define __attribute__(x)  /* Ignore __GNUC__ construct. */
#define __inline__ __inline  /* Use OpenWatcom symtax for __GNUC__ construct. */
#define __signed__ signed
#ifdef _NO_EXT_KEYS  /* wcc386 -za */
#  define __STRICT_ANSI__ 1  /* `gcc -ansi' == `gcc -std=c89'. */
#endif

#define STDIN_FILENO 0
#define STDOUT_FILENO 1
#define STDERR_FILENO 2

#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2

#define O_RDONLY 0
#define O_WRONLY 1
#define O_RDWR   2
#define O_ACCMODE 3
/* Linux-specific, open(...) will translate them to FreeBSD if needed. */
#define O_CREAT 0100
#define O_EXCL  0200
#define O_TRUNC 01000
#define O_NOCTTY 0400
#define O_APPEND 02000
#define O_LARGEFILE 0100000

typedef unsigned char uint8_t;
typedef signed char int8_t;
typedef unsigned short uint16_t;
typedef short int16_t;
typedef unsigned uint32_t;
typedef int int32_t;
__extension__ typedef unsigned long long uint64_t;
__extension__ typedef long long int64_t;

typedef unsigned size_t;
typedef int ssize_t;
typedef long __off_t;
#if _FILE_OFFSET_BITS == 64  /* Specifgy -D_FILE_OFFSET_BITS=64 for GCC. */
  __extension__ typedef long long off_t;  /* __extension__ is to make it work with `gcc -ansi -pedantic'. */
#else
  typedef long off_t;
#endif
__extension__ typedef long long loff_t;  /* __extension__ is to make it work with `gcc -ansi -pedantic'. */
__extension__ typedef long long off64_t;  /* __extension__ is to make it work with `gcc -ansi -pedantic'. */
typedef unsigned mode_t;
typedef long time_t;

#define NULL ((void*)0)

#define EXIT_SUCCESS 0
#define EXIT_FAILURE 1

/* <stdarg.h> */
#ifndef __GNUC__  /* If always works for __WATCOMC__. For __GNUC__, this is a size optimizatio working on i386 and if the function  taking the `...' arguments is __attribute__((noinline)). */
  typedef char *va_list;
#  define va_start(ap, last) ((ap) = (char*)&(last) + ((sizeof(last)+3)&~3), (void)0)  /* i386 only. */
#  define va_arg(ap, type) ((ap) += (sizeof(type)+3)&~3, *(type*)((ap) - ((sizeof(type)+3)&~3)))  /* i386 only. */
#  define va_copy(dest, src) ((dest) = (src), (void)0)  /* i386 only. */
#  define va_end(ap) /*((ap) = 0, (void)0)*/  /* i386 only. Adding the `= 0' back doesn't make a difference. */
#endif

/* <string.h> */
void * __watcall memcpy(void *dest, const void *src, size_t n);
void * __watcall memset(void *s, int c, size_t n);
int __watcall strcmp(const char *s1, const char *s2);
int __watcall strcasecmp(const char *l, const char *r);
char * __watcall strcpy(char *dest, const char *src);
size_t __watcall strlen(const char *s);

/* <ctype.h> */
int __watcall isalpha(int c);
int __watcall islower(int c);
int __watcall isupper(int c);
int __watcall isalnum(int c);
int __watcall isspace(int c);
int __watcall isdigit(int c);
int __watcall isxdigit(int c);

__declspec(noreturn) void __watcall exit(int exit_code);
__declspec(noreturn) void __watcall _exit(int exit_code);

void __watcall putchar_ign(char c);
void __watcall fflush_stdout(void);
void __watcall maybe_fflush_stdout(void);
void __watcall printf_void(const char *format, ...);

ssize_t __watcall read(int fd, void *buf, size_t count);
ssize_t __watcall write(int fd, const char *buf, size_t count);
int __watcall isatty(int fd);
int __watcall open(const char *pathname, int flags, ...);  /* Optional 3rd argument: mode_t mode */
#if _FILE_OFFSET_BITS == 64
#  pragma aux open "open_largefile_"
#endif
int __watcall close(int fd);
int __watcall unlink(const char *pathname);
int __watcall remove(const char *pathname);
#pragma aux remove "unlink_"  /* Not necessary, the libc defines both. */
#if _FILE_OFFSET_BITS == 64
  off64_t __watcall lseek(int fd, off64_t offset, int whence);
#  pragma aux lseek "lseek64_"
#else
  __off_t __watcall lseek(int fd, __off_t offset, int whence);  /* 32-bit offset. See lseek64(...) for 64-bit offset. */
#endif
off64_t __watcall lseek64(int fd, off64_t offset, int whence);
#if _FILE_OFFSET_BITS == 64
  int __watcall ftruncate(int fd, off64_t length);
#  pragma aux ftruncate "ftruncate64_"
#else
  int __cdecl ftruncate(int fd, __off_t length);  /* 32-bit length. Use ftruncate64(...) for 64-bit length. */
#endif
int __watcall ftruncate64(int fd, off64_t length);

time_t __cdecl time(time_t *tloc);

/* Returns an unaligned pointer. There is no API to free it. Suitable for
 * many small allocations. Be careful: if you use this with unaligned
 * sizes, then regular malloc(...) and realloc(...) may also return
 * unaligned pointers.
 */
void * __cdecl malloc_simple_unaligned(size_t size);

extern int errno;
extern char **environ;
extern int stdout_fd;

#ifdef CONFIG_MMLIBC386_INTERNAL_DEFS
  off64_t __cdecl __M_lseek64_linux(int fd, off64_t offset, int whence);
  int __watcall __M_fopen_open(const char *pathname, int flags, ...);  /* Optional 3rd argument: mode_t mode */
  extern int __M_is_freebsd;
#endif

#endif  /* #define _MMLIBC86_H */
