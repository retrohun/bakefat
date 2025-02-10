;
; mmlibc386.nasm; a minimalistic libc implementation for Linux i386 and FreeBSD i386, using the OpenWatcom C compiler
; by pts@fazekas.hu at Sun Feb  9 16:02:03 CET 2025
;
; Based on https://github.com/pts/minilibc686/blob/3ea27aa40ebf827074155f6271c4399543543a0c/libc/minilibc/sys_freebsd.nasm
;
; Please note that _errno may still be OS-specific.
;
; Info: https://alfonsosiciliano.gitlab.io/posts/2021-01-02-freebsd-system-calls-table.html
;

%define CONFIG_I386  ; Always true, we don't use any 486+ instructions (e.g. 486, 586, 686 and later).
%define CONFIG_PRINTF_SUPPORT_HEX

%ifndef OS_LINUX
  %ifndef OS_FREEBSD
    %error MISSING_D_OS
    db 1/0
  %endif
%endif
%ifdef OS_LINUX
  %define __MULTIOS__
%endif
%ifdef OS_WIN32
  %ifdef OS_LINUX
    %error ERROR_OS_CONFLICT_WIN32_LINUX
    db 1/0
  %endif
  %ifdef OS_FREEBSD
    %error ERROR_OS_CONFLICT_WIN32_FREEBSD
    db 1/0
  %endif
  %error ERROR_UNSUPPORTED_OS_WIN32  ; !! Add support.
  db 1/0
%endif

%ifndef UNDEFSYMS
  %error ERROR_EXPECTING_UNDEFSYMS  ; 'Expecting UNDEFSYMS from minicc.'
  db 1/0
%endif
%macro _define_needs 0-*
  %rep %0
    %define __NEED_%1
    %rotate 1
  %endrep
%endmacro
_define_needs UNDEFSYMS

bits 32
cpu 386  ; Always true, we don't use any 486+ instructions (e.g. 486, 586, 686 and later).

section _TEXT  USE32 class=CODE align=1
section CONST  USE32 class=DATA align=4  ; OpenWatcom generates align=4.
section CONST2 USE32 class=DATA align=4
section _DATA  USE32 class=DATA align=4
section _BSS   USE32 class=BSS  align=4 NOBITS  ; NOBITS is ignored by NASM, but class=BSS works.
group DGROUP CONST CONST2 _DATA _BSS
section _TEXT

; These must be at the beginning of the very first .obj file seen by wlink(1).
section CONST
etxt_header:	db 'ETXT'  ; Used by rex2elf.pl.
section _TEXT
extern __edata
extern __end
mhdr_header:	db 'MHDR'  ; Used by rex2elf.pl.
		dd etxt_header, __edata, __end

%ifdef __NEED___I8LS
  %define __NEED___U8LS
%endif
%ifdef __NEED__environ
  %define __NEED___argc
%endif
%ifdef __NEED__cstart_
  %define __NEED_exit_
%endif
%ifdef __NEED_exit_
  %define __NEED__exit_
%endif
%ifdef __NEED__printf_void
  %define __NEED_printf_void_
%endif
%ifdef __NEED_printf_void_
  %define __NEED_fflush_stdout_
  %define __NEED_putchar_ign_
%endif
%ifdef __NEED_putchar_ign_
  %define __NEED_fflush_stdout_
%endif
%ifdef __NEED__stdout_fd
  %ifdef __NEED_printf_void_
    %define __NEED_maybe_fflush_stdout_
  %endif
%endif
%ifdef __NEED_maybe_fflush_stdout_
  %define __NEED_fflush_stdout_
%endif
%ifdef __NEED_fflush_stdout_
  %define __NEED__write
%endif
%ifdef __NEED__remove
  %define __NEED__unlink
%endif
%ifdef __NEED__isatty
  %define __NEED_simple_syscall3_AL
%endif
%ifdef __NEED__write
  %define __NEED_simple_syscall3_AL
%endif
%ifdef __NEED__read
  %define __NEED_simple_syscall3_AL
%endif
%ifdef __NEED__open_largefile
  %define __NEED__open
%endif
%ifdef __NEED__open
  %define __NEED_simple_syscall3_AL
%endif
%ifdef __NEED__close
  %define __NEED_simple_syscall3_AL
%endif
%ifdef __NEED__unlink
  %define __NEED_simple_syscall3_AL
%endif
%ifdef __NEED____M_fopen_open
  %define __NEED_simple_syscall3_AL
%endif
%ifdef __NEED__time
  %define __NEED_simple_syscall3_AL
%endif
%ifdef __NEED__lseek
  %define __NEED_simple_syscall3_AL
%endif
%ifdef __NEED__ftruncate
  %define __NEED_simple_syscall3_AL
%endif
%ifdef __NEED__ftruncate64
  %define __NEED_simple_syscall3_AL
  %ifdef __MULTIOS__
    %define __NEED____M_lseek64_linux
  %endif
%endif
%ifdef __NEED__malloc_simple_unaligned
  %define __NEED_simple_syscall3_AL
%endif
; TODO(pts): Add more if needed.

%ifdef __NEED__cstart_
  extern main_
  global _cstart_
  _cstart_:  ; Entry point (_start) of the Linux i386 executable. Same for SVR3 i386, SVR4 i386, FreeBSD i386 and macOS i386 up to the end of envp.
		; Now the stack looks like (from top to bottom):
		;   dword [esp]: argc
		;   dword [esp+4]: argv[0] pointer
		;   esp+8...: argv[1..] pointers
		;   NULL that ends argv[]
		;   environment pointers
		;   NULL that ends envp[]
		;   ELF Auxiliary Table
		;   argv strings
		;   environment strings
		;   program name
		;   NULL
		push byte 4  ; SYS_write for both Linux i386 and FreeBSD.
		pop eax
		xor edx, edx  ; Argument count of Linux i386 SYS_write.
		push edx  ; Argument count of FreeBSD SYS_write.
		xor ecx, ecx  ; Argument buf of Linux i386 SYS_write.
		push ecx  ; Argument buf of FreeBSD SYS_write.
		or ebx, byte -1  ; Argument fd of Linux i386 SYS_write.
		push ebx  ; Argument fd of FreeBSD SYS_write.
		push eax  ; Fake return address of FreeBSD syscall.
		int 0x80  ; Linux i386 and FreeBSD i386 syscall. It fails because of the negative fd.
		add esp, byte 4*4  ; Clean up syscall arguments above.
  %ifdef __MULTIOS__  ; Set by minicc.sh if Linux support is needed in addition to FreeBSD.
		not eax
		shr eax, 31  ; EAX := sign(EAX). Linux becomes 0 (because SYS_write has returned a negative errno value: -EBADF), FreeBSD becomes 1.
		mov [___M_is_freebsd], al
		; The previous detection used SYS_getpid and checked CF
		; after `int 0x80'. This worked on modern Linux kernels (who
		; don't change CF, but FreeBSD i386 sets CF=0 upon success),
		; but `int 0x80' Linux 1.0.4 sets CF=0, so it didn't work.
		; Checking the sign of the errno return value is more
		; robust.
  %else  ; Exit gracefully (without segmentation fault) if this FreeBSD i386 program is run on Linux i386.
		test eax, eax
		jns freebsd
		xor eax, eax
		inc eax  ; EAX := SYS_exit for Linux i386.
		;or ebx, byte -1  ; exit(255);  ; No need to set it it still has this value from above.
		int 0x80  ; Linux i386 sysall.
  freebsd:
  %endif
		;call ___M_start_isatty_stdin
		;call ___M_start_isatty_stdout
  %ifdef __NEED___argc  ; Emitted by wcc386(1) if main_ uses argc (and argv).
    global __argc
    __argc:  ; Referenced (but not used) by wcc386(1) if main_ is defined. Actual value doesn't matter.
		pop eax  ; argc.
		mov edx, esp  ; argv.
    %ifdef __NEED__environ
		lea ecx, [edx+eax*4+4]  ; envp.
		mov [_environ], ecx
    %endif
  %endif
		call main_
		; Fall through to _exit.
%endif  ; %ifdef __NEED_start
%ifdef __NEED_exit_
  global exit_
  exit_:  ; __attribute__((noreturn)) void __watcall exit(int status);
  %ifdef __NEED_fflush_stdout_
		call fflush_stdout_  ; Keeps all registers (except for EFLAGS) intact, sets dword [stdout_next] to 0.
  %endif
		; Fall through to __exit.
%endif  ; %ifdef __NEED_exit_
%ifdef __NEED__exit_
  global __exit
  __exit:  ; __attribute__((noreturn)) void __watcall _exit(int exit_code);
		push eax  ; Argument exit_code for FreeBSD i386.
		push eax  ; Fake return address for FreeBSD u386.
  %ifdef __MULTIOS__
		xchg ebx, eax  ; EBX := EAX (exit_code); EAX := junk. Linux i386 syscall needs the 1st argument in EBX. FreeBSD i386 needs it in [esp+4].
  %endif
		xor eax, eax
		inc eax  ; EAX := FreeBSD i386 and Linux i386 SYS_exit (1).
		int 0x80  ; FreeBSD i386 and Linux i386 syscall.
		; Not reached.
%endif  ; %ifdef __NEED__exit_

; --- C compiler support functions.

%ifdef __NEED___U8LS  ; For OpenWatcom.
  %ifdef __NEED___I8LS
    global __I8LS
    __I8LS:  ; long long __watcall_but_ruins_ecx __I8LS(long long a, int b) { return a << b; }
  %endif
  global __U8LS
  __U8LS:  ; unsigned long long __watcall_but_ruins_ecx __U8LS(unsigned long long a, int b) { return a << b; }
  ; Input: EDX:EAX == a; EBX == b.
  ; Output: EDX:EAX == (a << b); EBX == b; ECX == junk.
		mov ecx, ebx
		;and cl, 0x3f  ; Not needed, CL&0x1f is used by shift instructions.
		test cl, 0x20
		jnz short .3
		shld edx, eax, cl
		shl eax, cl
		ret
  .3:		mov edx, eax
		;sub cl, 0x20  ; Not needed, CL&0x1f is used by shift instructions.
		xor eax, eax
		shl edx, cl
		ret
%endif

; --- libc string functions.  ; !! Convert as many functions as possible from __cdecl to __watcall. Get short implementation from other libcs.

%ifdef __NEED__memcpy
  global _memcpy  ; Longer code than memcpy_.
  _memcpy:  ; void * __cdecl memcpy(void *dest, const void *src, size_t n);
		push edi
		push esi
		mov ecx, [esp+0x14]
		mov esi, [esp+0x10]
		mov edi, [esp+0xc]
		push edi
		rep movsb
		pop eax  ; Result: pointer to dest.
		pop esi
		pop edi
		ret
%endif

%ifdef __NEED_memcpy_
  global memcpy_
  memcpy_:  ; void * __watcall memcpy(void *dest, const void *src, size_t n);
		push edi
		xchg esi, edx
		xchg edi, eax  ; EDI := dest; EAX := junk.
		xchg ecx, ebx
		push edi
		rep movsb
		pop eax  ; Will return dest.
		xchg ecx, ebx  ; Restore ECX from REGARG3. And REGARG3 is scratch, we don't care what we put there.
		xchg esi, edx  ; Restore ESI.
		pop edi
		ret
%endif

%ifdef __NEED__memset
  global _memset  ; Longer code than memset_.
  _memset:  ; void * __cdecl memset(void *s, int c, size_t n);
		push edi
		mov edi, [esp+8]  ; Argument s.
		mov al, [esp+0xc]  ; Argument c.
		mov ecx, [esp+0x10]  ; Argument n.
		push edi
		rep stosb
		pop eax  ; Result is argument s.
		pop edi
		ret
%endif

%ifdef __NEED_memset_
  global memset_
  memset_:  ; void * __watcall memset(void *s, int c, size_t n);
		push edi  ; Save.
		xchg edi, eax  ; EDI := EAX (argument s); EAX := junk.
		xchg eax, edx  ; EAX := EDX (argument c); EDX := junk.
		xchg ecx, ebx  ; ECX := EBX (argument n); EBX := saved ECX.
		push edi
		rep stosb
		pop eax  ; Result is argument s.
		xchg ecx, ebx  ; ECX := saved ECX; EBX := 0 (unused).
		pop edi  ; Restore.
		ret
%endif

%ifdef __NEED__strcpy
  global _strcpy  ; Longer code than strcpy_.
  _strcpy:  ; char * __cdecl strcpy(char *dest, const char *src);
		push edi
		push esi
		mov edi, [esp+0xc]
		mov esi, [esp+0x10]
		push edi
  .next:	lodsb
		stosb
		test al, al
		jnz strict short .next
		pop eax  ; Result: pointer to dest.
		pop esi
		pop edi
		ret
%endif

%ifdef __NEED_strcpy_
  global strcpy_
  strcpy_:  ; char * __watcall strcpy(char *dest, const char *src);
		push edi
		xchg esi, edx
		xchg eax, edi  ; EDI := dest; EAX := junk.
		push edi
  .next:	lodsb
		stosb
		test al, al
		jnz short .next
		pop eax  ; Will return dest.
		xchg esi, edx  ; Restore ESI.
		pop edi
		ret
%endif

%ifdef __NEED__strlen
  global _strlen  ; Longer code than strlen_.
  _strlen:  ; size_t __cdecl strlen(const char *s);
		push edi
		mov edi, [esp+8]  ; Argument s.
		xor eax, eax
		or ecx, byte -1  ; ECX := -1.
		repne scasb
		sub eax, ecx
		dec eax
		dec eax
		pop edi
		ret
%endif

%ifdef __NEED_strlen_
  global strlen_
  strlen_:  ; size_t __watcall strlen(const char *s);
		push esi  ; Save.
		xchg eax, esi
		xor eax, eax
		dec eax
  .next:	cmp byte [esi], 1
		inc esi
		inc eax
		jnc short .next
		pop esi  ; Restore.
		ret
%endif

%ifdef __NEED__strcmp
  global _strcmp  ; Longer code than strcmp_.
  _strcmp:  ; int __cdecl strcmp(const char *s1, const char *s2);
		push esi
		push edi
		mov esi, [esp+0xc]  ; s1.
		mov edi, [esp+0x10]  ; s2.
  .5:		lodsb
		scasb
		jne short .6
		cmp al, 0
		jne short .5
		xor eax, eax
		jmp short .7
  .6:		sbb eax, eax
		or al, 1
  .7:		pop edi
		pop esi
		ret
%endif

%ifdef __NEED_strcmp_
  global strcmp_
  strcmp_:  ; int __watcall strcmp(const char *s1, const char *s2);
		push esi
		xchg eax, esi  ; ESI := s1, EAX := junk.
		xor eax, eax
		xchg edi, edx
  .5:		lodsb
		scasb
		jne short .6
		cmp al, 0
		jne short .5
		jmp short .7
  .6:		mov al, 1
		jnc short .7
		neg eax
  .7:		xchg edi, edx  ; Restore original EDI.
		pop esi
		ret
%endif

%ifdef __NEED__strcasecmp
  global _strcasecmp  ; Longer code than strcmp_.
  _strcasecmp:  ; int __cdecl strcasecmp(const char *l, const char *r);
		push esi
		push edi
		mov esi, [esp+3*4]  ; Start of string l.
		mov edi, [esp+4*4]  ; Start of string r.
		; ESI: Start of string l. Will be ruined.
		; EDI: Start of string r. Will be ruined.
		; ECX: Scratch. Will be ruined.
		; EDX: Scratch. Will be ruined.
		; EAX: Scratch. The result is returned here.
		xor eax, eax
		xor ecx, ecx
  .again:	lodsb
		mov dh, al
		sub dh, 'A'
		cmp dh, 'Z'-'A'
		mov dl, al
		ja .2a
		or al, 0x20
  .2a:		movzx eax, al
		mov cl, [edi]
		inc edi
		mov dh, cl
		sub dh, 'A'
		cmp dh, 'Z'-'A'
		mov dh, cl
		ja .2b
		or cl, 0x20
  .2b:		sub eax, ecx  ; EAX := tolower(*(unsigned char*)l) - tolower(*(unsigned char*)r), zero-extended.
		jnz .return
		test dh, dh
		jz .return
		test dl, dl
		jnz .again
  .return:	pop edi
		pop esi
		ret
%endif

%ifdef __NEED_strcasecmp_
  global strcasecmp_
  strcasecmp_:  ; int __watcall strcasecmp(const char *l, const char *r);
		push ecx  ; Save.
		push esi  ; Save.
		push edi  ; Save.
		xchg esi, eax  ; ESI := start of string l; EAX := junk.
		xchg edi, edx  ; EDI := start of string r; EDX := junk.
		; ESI: Start of string l. Will be ruined.
		; EDI: Start of string r. Will be ruined.
		; ECX: Scratch. Will be ruined.
		; EDX: Scratch. Will be ruined.
		; EAX: Scratch. The result is returned here.
		xor eax, eax
		xor ecx, ecx
  .again:	lodsb
		mov dh, al
		sub dh, 'A'
		cmp dh, 'Z'-'A'
		mov dl, al
		ja .2a
		or al, 0x20
  .2a:		movzx eax, al
		mov cl, [edi]
		inc edi
		mov dh, cl
		sub dh, 'A'
		cmp dh, 'Z'-'A'
		mov dh, cl
		ja .2b
		or cl, 0x20
  .2b:		sub eax, ecx  ; EAX := tolower(*(unsigned char*)l) - tolower(*(unsigned char*)r), zero-extended.
		jnz .return
		test dh, dh
		jz .return
		test dl, dl
		jnz .again
  .return:	pop edi  ; Restore.
		pop esi  ; Restore.
		pop ecx  ; Restore.
		ret
%endif

; --- libc <ctype.h> functions.

%ifdef __NEED_isalpha_
  global isalpha_
  isalpha_:  ; int __watcall isalpha(int c);
		or al, 0x20
		sub al, 'a'
		cmp al, 'z'-'a'+1
		sbb eax, eax
		neg eax
		ret
%endif

%ifdef __NEED_islower_
  global islower_
  islower_:  ; int __watcall islower(int c);
		sub al, 'a'
		cmp al, 'z'-'a'+1
		sbb eax, eax
		neg eax
		ret
%endif

%ifdef __NEED_isupper_
  global isupper_
  isupper_:  ; int __watcall isupper(int c);
		sub al, 'A'
		cmp al, 'Z'-'A'+1
		sbb eax, eax
		neg eax
		ret
%endif

%ifdef __NEED_isalnum_
  global isalnum_
  isalnum_:  ; int __watcall isalnum(int c);
		sub al, '0'
		cmp al, '9'-'0'+1
		jc short .found
		add al, '0'
		or al, 0x20
		sub al, 'a'
		cmp al, 'z'-'a'+1
  .found:	sbb eax, eax
		neg eax
		ret
%endif

%ifdef __NEED_isspace_
  global isspace_
  isspace_:  ; int __watcall isspace(int c);
		sub al, 9  ; '\t'
		cmp al, 5  ; '\r'-'\t'+1
		jb short .1
		sub al, ' '-9
		cmp al, 1
  .1:		sbb eax, eax
		neg eax
		ret
%endif

%ifdef __NEED_isdigit_
  global isdigit_
  isdigit_:  ; int __watcall isdigit(int c);
		sub al, '0'
		cmp al, 10
		sbb eax, eax
		neg eax
		ret
%endif

%ifdef __NEED_isxdigit_
  global isxdigit_
  isxdigit_:  ; int __watcall isxdigit(int c);
		sub al, '0'
		cmp al, 10
		jb short .2
		or al, 0x20
		sub al, 'a'-'0'
		cmp al, 6
  .2:		sbb eax, eax
		neg eax
		ret
%endif

; --- libc globals.

%ifdef __NEED__errno
  global _errno
  section _BSS
  _errno: resd 1  ; int errno;
  section _TEXT
%endif

%ifdef __NEED__environ
  section _BSS
  global _environ
  _environ: resd 1  ; char **environ;
  section_TEXT
%endif

; --- printf(3) etc.

%ifdef __NEED__stdout_fd
  section _DATA
  global _stdout_fd
  _stdout_fd: dd 1  ; STDOUT_FILENO.
  section _TEXT
%endif

%ifdef __NEED_maybe_fflush_stdout_
  global maybe_fflush_stdout_  ; void __watcall maybe_fflush_stdout(void);
  maybe_fflush_stdout_:  ; Outputs: keeps all registers (except EFLAGS) intact.
  %ifdef __NEED__stdout_fd
		cmp dword [_stdout_fd], byte 2  ; STDERR_FILENO.
		je .do  ; Flush only stderrr.
		ret
    .do:
		; Fall through to fflush_stdout_.
  %else
		ret
  %endif
%endif
%ifdef __NEED_fflush_stdout_
  global fflush_stdout_  ; void __watcall fflush_stdout(void);
  fflush_stdout_:  ; Outputs: keeps all registers (except EFLAGS) intact.
		pusha
		mov edx, stdout_buf
		mov eax, stdout_next
		mov ebx, [eax]
		sub ebx, edx
		pushf  ; Save for ZF.
		sub [eax], ebx ; dword [stdout_next] := stdout_buf.
		popf  ; Restore for ZF.
		jz short .done
		push ebx  ; EBX == arg3 (count) of _write.
		push edx  ; EDX == arg2 (buf) of _write.
  %ifdef __NEED__stdout_fd
		push dword [_stdout_fd]
  %else
		push byte 1  ; EAX := STDOUT_FILENO == 1 == arg1 (fd) of libcu_write.
  %endif
		call _write
		add esp, byte 3*4  ; Clean up arguments of _write above.
  .done:	popa
		ret

  section _DATA
  stdout_next: dd stdout_buf  ; Used by putchar_ign_, fflush_stdout_ and printf_void_.
  section _BSS
  stdout_buf: resb 0x200  ; Used by putchar_ign_, fflush_stdout_ and printf_void_.
  .end:
  section _TEXT
%endif  ; %ifdef __NEED_fflush_stdout_

%ifdef __NEED_putchar_ign_
  global putchar_ign_  ; void __watcall putchar_ign(char c);
  putchar_ign:  ; It does line buffering and (on T_WIN32_OR_DOS32) translation of LF (10, "\n") to CRLF. Inputs: byte [ESP+4]: character to write. Outputs: keeps all registers (except EFLAGS) intact. putchar(3) would indicate result in EAX (0 for success or -1 for error).
  %ifdef OS_WIN32  ; No need to this if OpenWatcom libc write_ is used (such as in T_DOS32), it does that translation by default (no setmode(1, O_BINARY)).
		cmp al, 10  ; LF.
		jne short .not_lf
		mov al, 13  ; CR.
		call .not_lf
		mov al, 10  ; LF.
  .not_lf:
  %endif
		push ebx  ; Save.
		push edx  ; Save.
		mov ebx, stdout_next
  .again:	mov edx, [ebx]
		cmp edx, stdout_buf.end
		jne short .has_space  ; Don't jump (but flush) on NL.
		call fflush_stdout_  ; Keeps all registers (except for EFLAGS) intact, sets dword [stdout_next] to 0.
		jmp short .again
  .has_space:	mov [edx], al  ; byte [stdout_next] := AL.
		inc dword [ebx]  ; dword [stdout_next] += 1.
		cmp al, 10  ; NL ("\n").
		jne short .done
		call fflush_stdout_  ; Keeps all registers (except for EFLAGS) intact, sets dword [stdout_next] to 0.
  .done:	pop edx  ; Restore.
		pop ebx  ; Restore.
		ret
%endif  ; %ifdef __NEED_putchar_ign_

%ifdef __NEED_printf_void_
  global printf_void_  ; void __watcall printf_void(const char *format, ...);
  printf_void_:  ; __cdecl (but also saves EDX and ECX), also __watcall-with-varargs. format and varargs on the stack. Outputs: keeps all registers (except EFLAGS) intact.
  %ifdef __NEED__print_void
    global _printf_void  ; void __cdecl printf_void(const char *format, ...);
    _printf_void:
  %endif
  ; Format specifiers supported: %%, %s, %c, %u, %lu (l is ignored), %d, %x (disabled by default), %05u (also without 0), %3d (for nonnegative only, also without 0), %-25s (for negative only).
  ; Maximum size modifier (e.g. %42u) is 63 for numbers (%63u, larger value crashes) and 128 for strings (%-128s, larger value produces incorrect output).
  %undef CONFIG_PRINTF_SUPPORT_HEX  ; Not needed in aPACK.
		pusha  ; Save.
		pusha  ; Make room for last  32 bytes of scratch buffer (for %u, %d, %x).
		pusha  ; Make room for first 32 bytes of scratch buffer (for %u, %d, %x).
		lea edi, [esp+10*4+8*4*2]  ; EDI := address of first argument after format.
		mov esi, [edi-4]  ; format.
  .next_fmt_char:
		lodsb
		cmp al, '%'
		je strict short .specifier
		cmp al, 0
		je strict short .done
  .write_char:	call putchar_ign
  .j_next_fmt_char:
		jmp strict short .next_fmt_char
  .done:	popa  ; EAX, EBX, ECX and EDX intactDiscard first 32 bytes of scratch buffer (for %u, %d, %x).
		popa  ; Discard last  32 bytes of scratch buffer (for %u, %d, %x).
		popa  ; Restore.
  %ifdef __NEED_maybe_fflush_stdout_
		call maybe_fflush_stdout_
  %endif
		ret
  .modifier_digit:
		shl ch, 1
		mov ah, ch
		shl ah, 2
		add ch, ah
		and eax, strict byte 0xf  ; Also AH := 0. Also AL := AL - '0'.
		add ch, al  ; CH :=  CH * 10 + modifier_digit.
		jmp strict short .specifier_nxt
  .specifier:	mov ebx, [edi]  ; EDI == Argument of the format specifier.
		push byte ' '
		pop ecx  ; CH := 0 (initial value of the number count modifier in the specifier); CL := ' ' (padding char).
		xor eax, eax  ; Keep high 24 bits 0, for the `add ecx, eax' below.
		add edi, strict byte 4
		push byte 10
		pop ebp  ; EBP := 10. Base divisor for .number below.
		cmp byte [esi], '0'
		jne strict short .specifier_nxt
		inc si
		mov cl, '0'  ; CL := '0' (default padding char).
  .specifier_nxt:
		lodsb
		cmp al, 'l'
		je strict short .specifier_nxt  ; Ignore modifier 'l'.
		cmp al, '-'
		je strict short .specifier_nxt  ; Ignore modifier '-'.
		cmp al, 's'
		je strict short .specifier_s
		cmp al, 'u'
		je strict short .specifier_u
  %ifdef CONFIG_PRINTF_SUPPORT_HEX
		cmp al, 'x'
		je strict short .specifier_x
  %endif
		cmp al, 'd'
		je strict short .specifier_d
		cmp al, 'c'
		je strict short .specifier_c
		cmp al, '1'
		jb strict short .specifier_nd
		cmp al, '9'
		jna strict short .modifier_digit
  .specifier_nd:
		sub edi, strict byte 4
		jmp strict short .write_char  ; The specifier '%' is handled implicitly here.
  .specifier_c:	mov al, bl
		jmp strict short .write_char
  .no_pad_str:	mov ch, 0
  .specifier_s:  ; Now: AH == 0.
  .next_str_char:
		mov al, [ebx]
		cmp al, 0
		je strict short .pad_str
		cmp ch, ah  ; AH == 0.
		je strict short .done_dec_ch
		dec ch
  .done_dec_ch:	inc ebx
		call putchar_ign
		jmp strict short .next_str_char
  .pad_str:	mov al, cl  ; AL := padding char.
  .pad_str_next:
		dec ch
		js strict short .j_next_fmt_char
		call putchar_ign
		jmp strict short .pad_str_next
  %ifdef CONFIG_PRINTF_SUPPORT_HEX
  .specifier_x:	add ebp, byte 0x10-10  ; EBP := 0x10. Base divisor for .number below.
		jmp strict short .number
  %endif
  .specifier_d:	test ebx, ebx
		jns strict short .specifier_u
		neg ebx
		mov al, '-'
		call putchar_ign
		; Fall through.
  .specifier_u:
  .number:	xchg eax, ebx  ; EAX := EBX (number to be printed); EBX := junk.
		lea ebx, [esp+8*4-1]  ; Last byte of the scratch buffer for %u.
		mov byte [ebx], 0  ; Trailing NUL. AH isn't 0 here to use.
  .next_digit:	xor edx, edx  ; Set high dword of the dividend. Low dword is in EAX.
		div ebp  ; Divide by 10 or 0x10.
		dec ebx
		dec ch
  %ifdef CONFIG_PRINTF_SUPPORT_HEX
		xchg eax, edx
		add al, '0'
		cmp al, '9'
		jna strict short .digit_char_ok
		add al, 'a'-('9'+1)
  .digit_char_ok:
		mov [ebx], al
		xchg eax, edx  ; EAX := quotient; EDX := remainder (junk).
  %else
		add dl, '0'
		mov [ebx], dl
  %endif
		test eax, eax  ; Put next digit to the scratch buffer.
		jnz strict short .next_digit
  .next_padding:  ; Now: AH == 0.
		dec ch
		js strict short .no_pad_str
		dec ebx
		mov [ebx], cl  ; Add CL, the padding char.
		jmp strict short .next_padding
%endif  ; %ifdef __NEED_printf_void

; --- syscalls.

%ifdef __NEED__lseek
global _lseek
_lseek:  ; off_t _lseek(int fd, off_t offset, int whence);
  %ifdef __MULTIOS__
		cmp byte [___M_is_freebsd], 0
		jne short .freebsd
		mov al, 19  ; Linux i386 SYS_lseek.
		jmp short simple_syscall3_AL
    .freebsd:
  %endif
		push dword [esp+3*4]  ; Argument whence of lseek and sys_freebsd6_lseek.
		mov eax, [esp+3*4]  ; Argument offset of lseek.
		cdq  ; Sign-extend EAX (32-bit offset) to EDX:EAX (64-bit offset).
		push edx  ; High dword of argument offset of sys_freebsd6_lseek.
		push eax  ; Low dword of argument offset of sys_freebsd6_lseek.
		push eax ; Dummy argument pad of sys_freebsd6_lseek.
		push dword [esp+5*4]  ; Argument fd of lseek and sys_freebsd6_lseek.
		mov al, 199  ; FreeBSD SYS_freebsd6_lseek (also available in FreeBSD 3.0, released on 1998-10-16), with 64-bit offset.
		call simple_syscall3_AL
		test eax, eax
		js short .bad
		test edx, edx
		jz short .done
  .bad:		or eax, byte -1  ; Report error unless result fits to 31 bits, unsigned.
		cdq  ; EDX := -1. Sign-extend EAX (32-bit offset) to EDX:EAX (64-bit offset).
  .done:	add esp, byte 5*4  ; Clean up arguments of sys_freebsd6_lseek(...) above from the stack.
		ret
%endif

%ifdef __NEED__time
global _time
_time:  ; time_t _time(time_t *tloc);
  %ifdef __MULTIOS__  ; Already done.
		cmp byte [___M_is_freebsd], 0
		jne short .freebsd
		mov al, 13  ; Linux i386 SYS_time.
		jmp short simple_syscall3_AL
		; Alternatively, Linux i386 SYS_gettimeofday would also work, but SYS_time may be faster.
    .freebsd:
  %endif
		push eax  ; tv_usec output.
		push eax  ; tv_sec output.
		mov eax, esp
		push byte 0  ; Argument tz of gettimeofday (NULL).
		push eax  ; Argument tv of gettimeofday.
		mov al, 116  ; FreeBSD i386 SYS_gettimeofday.
  ;%ifdef __MULTIOS__  ; Already done.
  ;		cmp byte [___M_is_freebsd], 0
  ;		jne short .freebsd
  ;		mov al, 78  ; Linux i386 SYS_gettimeofday.
  ;  .freebsd:
  ;%endif
		call simple_syscall3_AL
		pop eax  ; Argument tv of gettimeofday.
		pop eax  ; Argument tz of gettimeofday.
		pop eax  ; tv_sec.
		pop edx  ; tv_usec (ignored).
		mov edx, [esp+4]  ; tloc.
		test edx, edx
		jz .ret
		mov [edx], eax
.ret:		ret
%endif

%ifdef __NEED__open
  %ifndef __MULTIOS__
    %define __NEED____M_fopen_open
    %undef __NEED__open
    global _open
    _open:  ; int _open(const char *pathname, int flags, mode_t mode);
  %endif
%endif
%ifdef __NEED__open_largefile
  %ifndef __MULTIOS__
    %define __NEED____M_fopen_open
    %undef __NEED__open_largefile
    global _open_largefile
    _open_largefile:  ; int _open(const char *pathname, int flags, mode_t mode);
  %endif
%endif
%ifdef __NEED____M_fopen_open
  %ifndef __NEED__open
    global ___M_fopen_open
    ___M_fopen_open:  ; int ___M_fopen_open(const char *pathname, int flags, mode_t mode);
		mov al, 5  ; FreeBSD i386 and Linux i386 SYS_open.
    %ifdef __MULTIOS__
		cmp byte [___M_is_freebsd], 0
		je .flags_done
		lea edx, [esp+2*4]  ; Address of flags argument.
		; This only fixes the flags with which _fopen(...) calls _open(...). The other flags value is O_RDONLY, which doesn't have to be changed.
		cmp word [edx], 1101o  ; flags: Linux   (O_WRONLY | O_CREAT | O_TRUNC) == (1 | 100o | 1000o).
		jne .flags_done
		mov word [edx], 0x601  ; flags: FreeBSD (O_WRONLY | O_CREAT | O_TRUNC) == (1 | 0x200 | 0x400) == 0x601. In the SYSV i386 calling convention, it's OK to modify an argument on the stack.
      .flags_done:
    %endif
		jmp short simple_syscall3_AL
  %endif
%endif

%ifdef __NEED__ftruncate
global _ftruncate
_ftruncate:  ; int _ftruncate(int fd, off_t length);
  %ifdef __MULTIOS__
		cmp byte [___M_is_freebsd], 0
		jne short .freebsd
		mov al, 93  ; Linux i386 SYS_ftruncate. Supported on Linux >=1.0.
		jmp short simple_syscall3_AL
    .freebsd:
  %endif
		mov eax, [esp+2*4]  ; Argument length.
		cdq  ; EDX:EAX = sign_extend(EAX).
		push edx
		push eax
		push eax  ; Arbitrary pad value.
		push dword [esp+4*4]  ; Argument fd.
		;mov eax, 130  ; FreeBSD old ftruncate(2) wit 32-bit offset. int ftruncate(int fd, long length); }.
		mov al, 201  ; FreeBSD ftruncate(2) with 64-bit offset. FreeBSD 3.0 already had it. int ftruncate(int fd, int pad, off_t length); }
		call simple_syscall3_AL
		add esp, byte 4*4  ; Clean up arguments above.
		ret
%endif

; TODO(pts): Make at least one function fall through to simple_syscall3_AL.

%ifdef __NEED_simple_syscall3_AL
; Input: syscall number in AL, up to 3 arguments on the stack (__cdecl).
; It assumes same syscall number and behavior for FreeBSD i386 and Linux i386.
simple_syscall3_AL:
		movzx eax, al
  %ifdef __MULTIOS__
		cmp byte [___M_is_freebsd], 0
		jne short .freebsd
		push ebx  ; Save.
		mov ebx, [esp+2*4]  ; Argument fd.
		mov ecx, [esp+3*4]  ; Argument buf.
		mov edx, [esp+4*4]  ; Argument count.
		int 0x80  ; Linux i386 syscall.
		pop ebx  ; Restore.
		test eax, eax
		; Sign check is good for most syscalls, but not time(2) or mmap2(2).
		; For mmap2(2), do: cmp eax, -0x100 ++ jna .final_result
		jns .ok_linux
    %ifdef __NEED__errno
		neg eax
		mov [_errno], eax
    %endif
		or eax, byte -1  ; EAX := -1 (ignore -errnum value).
.ok_linux:	ret
.freebsd:
  %endif
		int 0x80  ; FreeBSD i386 syscall.
		jnc .ok
  %ifdef __NEED__errno
		mov [_errno], eax
  %endif
		sbb eax, eax  ; EAX := -1, indicating error.
.ok:
%endif
WEAK..___M_start_isatty_stdin:   ; Fallback, tools/elfofix will convert it to a weak symbol.
WEAK..___M_start_isatty_stdout:  ; Fallback, tools/elfofix will convert it to a weak symbol.
WEAK..___M_start_flush_stdout:   ; Fallback, tools/elfofix will convert it to a weak symbol.
WEAK..___M_start_flush_opened:   ; Fallback, tools/elfofix will convert it to a weak symbol.
		ret

%ifdef __NEED__write
global _write
_write:  ; ssize_t _write(int fd, const void *buf, size_t count);
		mov al, 4  ; FreeBSD i386 and Linux i386 SYS_write.
		jmp short simple_syscall3_AL
%endif

%ifdef __NEED__read
global _read
_read:  ; ssize_t _read(int fd, void *buf, size_t count);
		mov al, 3  ; FreeBSD i386 and Linux i386 SYS_read.
		jmp short simple_syscall3_AL
%endif

%ifdef __NEED__close
global _close
_close:  ; int _close(int fd);;
		mov al, 6  ; FreeBSD i386 and Linux i386 SYS_close.
		jmp short simple_syscall3_AL
%endif

%ifdef __NEED__remove
  global _remove
  _remove:  ; int _remove(const char *pathname);
  %define __DO__unlink
%endif
%ifdef __NEED__unlink  ; Also true if: ifdef __NEED__remove.
  global _unlink
  _unlink:  ; int _unlink(const char *pathname);
  %define __DO__unlink
%endif
%ifdef __DO__unlink
		mov al, 10  ; FreeBSD i386 and Linux i386 SYS_unlink.
		jmp short simple_syscall3_AL
%endif

; --- No more instances of `jmp short simple_syscall3_AL', so we don't have to enforce `short'.

%ifdef __NEED__open
  global _open
  _open:  ; int _open(const char *pathname, int flags, mode_t mode);
  %ifdef __NEED____M_fopen_open
    global ___M_fopen_open
    ___M_fopen_open:  ; int ___M_fopen_open(const char *pathname, int flags, mode_t mode);
  %endif
  %ifndef __MULTIOS__
    %error MULTIOS_NEEDED_FOR_MINI_OPEN
    db 1/0
  %endif
  ; !! Add CONFIG_SIMPLE_OPEN to support only O_RDONLY and O_WRONLY|O_CREAT|O_TRUNC (like in __NEED____M_fopen_open).
  ;
  ; Symbol       Linux   FreeBSD
  ; ----------------------------
  ; O_CREAT        0x40   0x0200
  ; O_TRUNC       0x200   0x0400
  ; O_EXCL         0x80   0x0800
  ; O_NOCTTY      0x100   0x8000
  ; O_APPEND      0x400        8
  ; O_LARGEFILE  0x8000        0
  %macro open_test_or 4
    test %1, %2
    jz short %%unset
    and %1, ~(%2)
    or %3, %4
    %%unset:
  %endm
		mov eax, [esp+2*4]  ; Get argument flags.
		mov edx, eax
		cmp byte [___M_is_freebsd], 0
		je .flags_done
		and edx, byte 3  ; O_ACCMODE.
		and eax, strict dword ~(0x8003)  ; ~(O_ACCMODE|O_LARGEFILE).
		open_test_or al, 0x40, dh, 2  ; O_CREAT.
		open_test_or al, 0x80, dh, 8  ; O_EXCL.
		xchg al, ah  ; Save a few bytes below: operations on al are shorter than on ah.
		open_test_or al, 1, dh, 0x80  ; O_NOCTTY.
		open_test_or al, 2, dh, 4  ; O_TRUNC.
		open_test_or al, 4, dl, 8  ; O_APPEND.
		test eax, eax
		jz short .flags_done  ; Jump if all flags converted correctly.
  %ifdef __NEED__errno
		push byte 22  ; Linux EINVAL.
		pop dword [_errno]
  %endif
		or eax, byte -1
		ret
    .flags_done:
		push dword [esp+3*4]  ; Copy argument mode.
		push edx  ; Modified argument flags.
		push dword [esp+3*4]  ; Copy argument pathname.
		mov al, 5
		call simple_syscall3_AL
		add esp, byte 3*4  ; Clean up stack of simple_syscall3_AL.
		ret
%endif

%ifdef __NEED__open_largefile
global _open_largefile
_open_largefile:  ; char *_open_largefile(const char *pathname, int flags, mode_t mode);  /* Argument mode is optional. */
		push dword [esp+3*4]  ; Argument mode.
		mov eax, [esp+3*4]  ; Argument flags.
		or ah, 0x80  ; Add O_LARGEFILE (Linux i386).
		push eax
		push dword [esp+3*4]  ; Argument pathname.
		call _open
		add esp, byte 3*4  ; Clean up arguments of open above.
		ret
%endif

%ifdef __NEED__isatty
global _isatty
_isatty:  ; int _isatty(int fd);
		sub esp, strict byte 0x2c  ; 0x2c is the maximum sizeof(struct termios) for Linux (0x24) and FreeBSD (0x2c).
		push esp  ; 3rd argument of ioctl TCGETS.
		push strict dword 0x402c7413  ; Change assumed Linux TCGETS (0x5401) to FreeBSD TIOCGETA (0x402c7413).
  %ifdef __MULTIOS__
		cmp byte [___M_is_freebsd], 0
		jne short .freebsd
		pop eax  ; Clean up previous push.
		push strict dword 0x5401  ; TCGETS. The syscall will change it to TIOCGETA for FreeBSD.
    .freebsd:
  %endif
		push dword [esp+0x2c+4+2*4]  ; fd argument of ioctl.
		mov al, 54  ; FreeBSD i386 and Linux i386 SYS_ioctl.
		call simple_syscall3_AL
		add esp, strict byte 0x2c+3*4  ; Clean up everything pushed.
		; Now convert result EAX: -1 to 0, everything else to 1. TODO(pts): Can we assume that FreeBSD TIOCGETA returns 0 here?
		inc eax
		jz .have_retval
		xor eax, eax
		inc eax
.have_retval:
%endif

%ifdef __NEED__lseek64
global _lseek64
_lseek64:  ; off64_t _lseek64(int fd, off64_t offset, int whence);
  %ifdef __MULTIOS__
		cmp byte [___M_is_freebsd], 0
		jne short .freebsd
		push ebx
		push esi
		push edi
		push ebx  ; High dword of result.
		push ebx  ; Low dword of result.
		xor eax, eax
		mov al, 140  ; Linux i386 SYS__llseek. Needs Linux >=1.2. We do a fallback later.
		mov ebx, [esp+0x14+4]  ; Argument fd.
		mov edx, [esp+0x14+8]  ; Argument offset (low dword).
		mov ecx, [esp+0x14+0xc]  ; Argument offset (high dword).
		mov esi, esp  ; &result.
		mov edi, [esi+0x14+0x10]  ; Argument whence.
		int 0x80  ; Linux i386 syscall.
		test eax, eax
		jns short .ok  ; It's OK to check the sign bit, SYS__llseek won't return negative values as success.
		cmp eax, byte -38  ; Linux -ENOSYS. We get it if the kernel doesn't support SYS__llseek. Typically this happens for Linux <1.2.
		jne short .bad_linux
		; Try SYS_lseek. It works on Linux 1.0. Only Linux >=1.2 provides SYS__llseek.
		mov eax, [esp+0x14+8]  ; Argument offset (low word).
		cdq  ; EDX:EAX = sign_extend(EAX).
		cmp edx, [esp+0x14+0xc]  ; Argument offset (high word).
		xchg ecx, eax  ; ECX := argument offset (low word); EAX := junk.
		push byte -22  ; Linux i386 -EINVAL.
		pop eax
		jne .bad_linux  ; Jump iff computed offset high word differs from the actual one.
		;mov ebx, [esp+0x14+4]  ; Argument fd. Not needed, it already has that value.
		mov edx, [esp+0x14+0x10]  ; Argument whence.
		push byte 19  ; Linux i386 SYS_lseek.
		pop eax
		int 0x80  ; Linux i386 syscall.
		test eax, eax
		jns short .done  ; It's OK to check the sign bit, SYS_llseek won't return negative values as success, because it doesn't support files >=2 GiB.
    .bad_linux:
  %ifdef __NEED__errno
		neg eax
		mov [_errno], eax  ; Linux errno.
  %endif
		or eax, byte -1  ; EAX := -1 (error).
		cdq  ; EDX := -1. Sign-extend EAX (32-bit offset) to EDX:EAX (64-bit offset).
		jmp short .bad_ret
    .ok:	lodsd  ; High dword of result.
		mov edx, [esi]  ; Low dword of result.
    .done:	pop ebx  ; Discard low word of SYS__llseek result.
		pop ebx  ; Discard high word of SYS__llseek result.
		pop edi
		pop esi
		pop ebx
		ret
    .freebsd:
  %endif
		push dword [esp+4*4]  ; Argument whence of lseek and sys_freebsd6_lseek.
		push dword [esp+4*4]  ; High dword of argument offset of lseek.
		push dword [esp+4*4]  ; Low dword of argument offset of lseek.
		push eax ; Dummy argument pad of sys_freebsd6_lseek.
		push dword [esp+5*4]  ; Argument fd of lseek and sys_freebsd6_lseek.
		xor eax, eax
		mov al, 199  ; FreeBSD SYS_freebsd6_lseek (also available in FreeBSD 3.0, released on 1998-10-16), with 64-bit offset.
		push eax  ; Dummy return address needed by FreeBSD i386 syscall.
		int 0x80  ; FreeBSD i386 syscall.
		lea esp, [esp+6*4]  ; Clean up arguments above from stack, without affecting the flags.
		jnc short .ret
  .bad:
  %ifdef __NEED__errno
		mov [_errno], eax  ; FreeBSD errno.
  %endif
  .bad_ret:	or eax, byte -1  ; EAX := -1. Report error unless result fits to 31 bits, unsigned.
		cdq  ; EDX := -1. Sign-extend EAX (32-bit offset) to EDX:EAX (64-bit offset).
  .ret:		ret
%endif

%ifdef __NEED____M_lseek64_linux
  global ___M_lseek64_linux
  %ifdef __NEED__lseek64
    ___M_lseek64_linux: equ _lseek64
  %else
    ___M_lseek64_linux:
		push ebx
		push esi
		push edi
		push ebx  ; High dword of SYS__llseek result.
		push ebx  ; Low  dword of SYS__llseek result.
		xor eax, eax
		mov al, 140  ; SYS__llseek.
		mov ebx, [esp+0x14+4]  ; Argument fd.
		mov edx, [esp+0x14+8]  ; Argument offset (low dword).
		mov ecx, [esp+0x14+0xc]  ; Argument offset (high dword).
		mov esi, esp  ; &result.
		mov edi, [esi+0x14+0x10]  ; Argument whence.
		int 0x80  ; Linux i386 syscall.
		test eax, eax
		js short .bad  ; It's OK to check the sign bit, SYS__llseek won't return negative values as success.
    .ok:	lodsd  ; High dword of result.
		mov edx, [esi]  ; Low dword of result.
		jmp short .done
    .bad:
  %ifdef __NEED__errno
		neg eax
		mov [_errno], eax  ; Linux errno.
  %endif
		or eax, byte -1  ; EAX := -1 (error).
		cdq  ; EDX := -1. Sign-extend EAX (32-bit offset) to EDX:EAX (64-bit offset).
    .done:	pop ebx  ; Discard low  word of SYS__llseek result.
		pop ebx  ; Discard high word of SYS__llseek result.
		pop edi
		pop esi
		pop ebx
		ret
  %endif
%endif

%ifdef __NEED__ftruncate64
  ;%define DEBUG_SKIP_SYS_FTRUNCATE64
  ;%define DEBUG_SKIP_SYS_FTRUNCATE
  global _ftruncate64
  _ftruncate64:  ; int _ftruncate64(int fd, off64_t length);
  %ifdef __MULTIOS__
		cmp byte [___M_is_freebsd], 0
		je short .linux
    .freebsd:
  %endif
		mov al, 201  ; FreeBSD ftruncate(2) with 64-bit offset. FreeBSD 3.0 already had it. int ftruncate(int fd, int pad, off_t length); }
		;mov eax, 130  ; FreeBSD old ftruncate(2) wit 32-bit offset. int ftruncate(int fd, long length); }.
		push dword [esp+3*4]  ; High word of argument length.
		push dword [esp+3*4]  ; Low word of argument length.
		push eax  ; Arbitrary pad value.
		push dword [esp+4*4]  ; Argument fd.
		call simple_syscall3_AL
		add esp, byte 4*4  ; Clean up arguments above.
		ret
  %ifdef __MULTIOS__
    .linux:	push ebx  ; Save.
		push esi  ; Save.
		push edi  ; Save.
		xor eax, eax
		mov al, 194  ; Linux i386 ftruncate64(2). Needs Linux >=2.4.
		mov ebx, [esp+4*4]  ; Argument fd.
		mov ecx, [esp+5*4]  ; Low  word of argument length.
		mov edx, [esp+6*4]  ; High word of argument length.
    %ifndef DEBUG_SKIP_SYS_FTRUNCATE64
		int 0x80  ; Linux i386 syscall.
		test eax, eax
		jns short .done_linux  ; It's OK to check the sign bit, SYS__llseek won't return negative values as success.
		cmp eax, byte -38  ; Linux -ENOSYS. We get it if the kernel doesn't support SYS__llseek. Typically this happens for Linux <1.2.
		jne short .bad_linux
    %endif
		; Try SYS_ftruncate. It works on Linux 1.0. Only Linux >=2.4 provides SYS_ftruncate(2).
		xchg ecx, eax  ; EAX := argument offset (low word); ECX := junk.
		cdq  ; EDX:EAX = sign_extend(EAX).
		cmp edx, [esp+6*4]  ; Argument offset (high word).
		xchg ecx, eax  ; ECX := argument offset (low word); EAX := junk.
		push byte -22  ; Linux i386 -EINVAL.
		pop eax
    %ifndef DEBUG_SKIP_SYS_FTRUNCATE
		je short .ftruncate_linux  ; Jump iff computed offset high word is the same as the actual one.
    %endif
    .fallback_linux:  ; Now we fall back to greowing the file using _lseek64(...) + SYS_write of 1 byte.
		push byte 1  ; Argument whence: SEEK_CUR.
		push byte 0  ; High word of argument length.
		push byte 0  ; Low  word of argument length.
		push ebx  ; Argument fd.
		call ___M_lseek64_linux
		add esp, byte 4*4  ; Clean up arguments of ___M_lseek64_linux above.
		test edx, edx
		js short .done_linux
		mov esi, edx
		xchg edi, eax  ; ESI:EDI := previous file position; EAX := junk.
		push byte 2  ; Argument whence: SEEK_END.
		push byte 0  ; High word of argument length.
		push byte 0  ; Low  word of argument length.
		push ebx  ; Argument fd.
		call ___M_lseek64_linux
		add esp, byte 4*4  ; Clean up arguments of ___M_lseek64_linux above.
		jmp short .fallback_linux2
    .ftruncate_linux:
		;mov ebx, [esp+2*4]  ; Argument fd. Not needed, it already has that value.
		;mov ecx, [esp+3*4]  ; Low word of argument length. Not needed, it already has that value.
		push byte 93  ; Linux i386 SYS_ftruncate.
		pop eax
		int 0x80  ; Linux i386 syscall.
		test eax, eax
		jns short .done_linux  ; It's OK to check the sign bit, SYS_llseek won't return negative values as success, because it doesn't support files >=2 GiB.
    .bad_linux:
    %ifdef __NEED__errno
		neg eax
		mov [_errno], eax  ; Linux errno.
    %endif
		or eax, byte -1  ; EAX := -1 (error).
    .done_linux:
		pop edi  ; Restore.
		pop esi  ; Restore.
		pop ebx  ; Restore.
		ret
    .fallback_linux2:
		test edx, edx
		js short .done_linux
		cmp edx, [esp+6*4]  ; High word of argument length.
		ja short .enosys_linux  ; The caller wants use to shrink the file, this fallback implementation can't do that.
		jne .grow_linux
		cmp eax, [esp+5*4]  ; Low word of argument length.
		ja short .enosys_linux  ; The caller wants use to shrink the file, this fallback implementation can't do that.
		je short .seek_back_linux
    .grow_linux:
		mov edx, [esp+6*4]  ; High word of argument length.
		mov eax, [esp+5*4]  ; Low word of argument length.
		dec eax
		jnz .cont1_linux
		dec edx
    .cont1_linux:
		push byte 0  ; Argument whence: SEEK_SET.
		push edx  ; High word of argument length.
		push eax  ; Low  word of argument length.
		push ebx  ; Argument fd.
		call ___M_lseek64_linux
		add esp, byte 4*4  ; Clean up arguments of ___M_lseek64_linux above.
		test edx, edx
		js short .done_linux
    .write1_linux:  ; Now write a NUL byte.
		push byte 0  ; Buffer containing a single NUL byte.
		mov ecx, esp
		push byte 1  ; Argument count of SYS_write.
		push ecx  ; Argument buf of SYS_write.
		push ebx  ; Argument fd of SYS_write.
		mov al, 4  ; Linux i386 SYS_write.
		call simple_syscall3_AL
		add esp, byte 3*4+4  ; Clean up arguments of simple_syscall3_AL above and also the buffer.
		test eax, eax
		js short .done_linux
    .seek_back_linux:
		push byte 0  ; Argument whence: SEEK_SET.
		push esi  ; High word of argument length.
		push edi  ; Low  word of argument length.
		push ebx  ; Argument fd.
		call ___M_lseek64_linux
		add esp, byte 4*4  ; Clean up arguments of ___M_lseek64_linux above.
		test edx, edx
		js short .done_linux
		xor eax, eax  ; Indicate success by returning 0 in EDX:EAX.
		jmp short .done_linux
    %ifdef __NEED__errno
      .enosys_linux:
		push byte -38  ; Linux i386 -ENOSYS.  ; !!! Omit this if no __NEED__errno.
		pop eax
		jmp short .bad_linux
    %else
      .enosys_linux: equ .bad_linux
    %endif
  %endif
%endif

%ifdef __NEED__malloc_simple_unaligned
extern _end  ; Set to end of .bss by GNU ld(1).
PROT:  ; Symbolic constants for Linux and FreeBSD mmap(2).
.READ: equ 1
.WRITE: equ 2
;
MAP:  ; Symbolic constants for Linux and FreeBSD mmap(2).
.PRIVATE: equ 2
.FIXED: equ 0x10
.ANONYMOUS_LINUX: equ 0x20
.ANONYMOUS_FREEBSD: equ 0x1000
global _malloc_simple_unaligned
_malloc_simple_unaligned:  ; void *_malloc_simple_unaligned(size_t size);
; Implemented using sys_brk(2). Equivalent to the following C code, but was
; size-optimized.
;
; A simplistic allocator which creates a heap of 64 KiB first, and then
; doubles it when necessary. It is implemented using Linux system call
; brk(2), exported by the libc as sys_brk(...). free(...)ing is not
; supported. Returns an unaligned address (which is OK on x86).
;
; void *_malloc_simple_unaligned(size_t size) {
;     static char *base, *free, *end;
;     ssize_t new_heap_size;
;     if ((ssize_t)size <= 0) return NULL;  /* Fail if size is too large (or 0). */
;     if (!base) {
;         if (!(base = free = (char*)sys_brk(NULL))) return NULL;  /* Error getting the initial data segment size for the very first time. */
;         new_heap_size = 64 << 10;  /* 64 KiB. */
;         goto grow_heap;  /* TODO(pts): Reset base to NULL if we overflow below. */
;     }
;     while (size > (size_t)(end - free)) {  /* Double the heap size until there is `size' bytes free. */
;         new_heap_size = (end - base) >= (1 << 20) ? (end - base) + (1 << 20) : (end - base) << 1;  /* Double it until 1 MiB. */
;       grow_heap:
;         if ((ssize_t)new_heap_size <= 0 || (size_t)base + new_heap_size < (size_t)base) return NULL;  /* Heap would be too large. */
;         if ((char*)sys_brk(base + new_heap_size) != base + new_heap_size) return NULL;  /* Out of memory. */
;         end = base + new_heap_size;
;     }
;     free += size;
;     return free - size;
; }
  %define _BASE edi
  %define _FREE edi+4
  %define _END edi+8
  %define _IS_FREEBSD esi
		mov eax, [esp+4]  ; Argument named size.
		push ebx
		push edi  ; Save.
		mov edi, _malloc_simple_base
  %ifdef __MULTIOS__
		push esi  ; Save.
		mov esi, ___M_is_freebsd
  %endif
		test eax, eax
		jle near .18
		mov ebx, eax
		cmp dword [_BASE], byte 0
		jne .7
		mov eax, _end  ; Address after .bss.
		add eax, 0xfff
		and eax, ~0xfff
		times 3 stosd  ; mov [_FREE], eax ++ mov [_BASE], eax ++ mov [_END], eax  ; Setting [_END] is needed by FreeBSD.
		sub edi, byte 3*4  ; Set it back to _BASE.
		mov eax, 0x10000  ; 64 KiB minimum allocation.
  .9:		add eax, [_BASE]
		jc .18
		push eax  ; Save new dword [_END] value.
		mov edx, [_END]
		push edx  ; Save old dword [_END] value.
		sub eax, edx
		xor ecx, ecx
  %ifdef __MULTIOS__
		cmp byte [_IS_FREEBSD], 0
		jne short .freebsd2
		push ecx  ; offset == 0.
		push strict byte -1 ; fd.
		push strict byte MAP.PRIVATE|MAP.ANONYMOUS_LINUX|MAP.FIXED  ; flags.
		push strict byte PROT.READ|PROT.WRITE  ; prot.
		push eax  ; length. Rounded to page boundary.
		push edx  ; addr. Rounded to page boundary.
		push esp  ; buffer, to be passed to sys_mmap(...).
		mov al, 90  ; Linux i386 SYS_mmap.
		call simple_syscall3_AL	; It destroys ECX and EDX.
		add esp, byte 7*4  ; Clean up arguments  of SYS_mmap above.
		jmp short .done2
  %endif
    .freebsd2:  ; caddr_t freebsd6_mmap(caddr_t addr, size_t length, int prot, int flags, int fd, int pad, off_t offset);  /* 197 for FreeBSD. */
		push ecx  ; High dword of argument offset of freebsd6_mmap == 0.
		push ecx  ; Low dword of argument offset of freebsd6_mmap == 0.
		push ecx  ; Argument pad of freebsd6_mmap == 0.
		push strict byte -1  ; Argument fd of freebsd6_mmap == -1.
		push strict dword MAP.PRIVATE|MAP.ANONYMOUS_FREEBSD|MAP.FIXED  ; Argument flags of freebsd6_mmap.
		push strict byte PROT.READ|PROT.WRITE  ; Argument prot of freebsd6_mmap.
		push eax  ; Argument length of freebsd6_mmap. No need to manually round up to page boundary for FreeBSD. But it's rounded anyway.
		push edx  ; Argument addr of freebsd6_mmap. Rounded to page boundary.
		mov al, 197  ; FreeBSD i386 SYS_freebsd6_mmap (also available in FreeBSD 3.0, released on 1998-10-16), with 64-bit offset.
		call simple_syscall3_AL	; It destroys ECX and EDX.
		add esp, byte 8*4  ; Clean up arguments  of SYS_mmap above.
  %ifdef __MULTIOS__
    .done2:
  %endif
		pop edx  ; Restore old dword [_END] value.
		cmp eax, edx  ; Compare actual return value (EAX) to expected old dword [_END] value.
		pop eax  ; Restore new dword [_END].
		jne .18
		mov [_END], eax
  .7:		mov edx, [_END]
		mov eax, [_FREE]
		mov ecx, edx
		sub ecx, eax
		cmp ecx, ebx
		jb .21
		add ebx, eax
		mov [_FREE], ebx
		jmp short .done
  .21:		sub edx, [_BASE]
		mov eax, 1<<20  ; 1 MiB.
		cmp edx, eax
  %ifdef CONFIG_I386
		jnbe .22
		mov eax, edx
    .22:
  %else
		cmovbe eax, edx
  %endif  ; else CONFIG_I386
		add eax, edx
		test eax, eax  ; ZF=..., SF=..., OF=0.
		jg .9  ; Jump iff ZF=0 and SF=OF=0. Why is this correct?
  .18:		xor eax, eax
  .done:
  %ifdef __MULTIOS__
		pop esi  ; Restore.
  %endif
		pop edi
		pop ebx
		ret
  %ifdef __NEED__malloc_simple_unaligned
    section _BSS
    _malloc_simple_base: resd 1  ; char *base;
    _malloc_simple_free: resd 1  ; char *free; Must come after _malloc_simple_base.
    _malloc_simple_end:  resd 1  ; char *end;  Must come after _malloc_simple_end.
    section _TEXT
  %endif
%endif

section _BSS  ; Put the 1-aligned entries to the end.
  %ifdef __MULTIOS__
    global ___M_is_freebsd
    ___M_is_freebsd: resb 1  ; Are we actually running under FreeBSD (rathar than Linux)?
  %endif
section _TEXT
