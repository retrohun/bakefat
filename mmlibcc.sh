#! /bin/sh --
#
# mmlibcc.sh: compiler driver for mmlibc386
# by pts@fazekas.hu at Sun Feb  9 16:59:51 CET 2025
#

export LC_ALL=C  # For deterministic output. Typically not needed. Is it too late for Perl?
export TZ=GMT  # For deterministic output. Typically not needed. Perl respects it immediately.
if test "$1" != --sh-script-mydir; then
  mydir=.; test "$0" = "${0%/*}" || mydir="${0%/*}"
  while test "${mydir#./[^/]}" != "$mydir"; do mydir="${mydir#./}"; done
  if test "$1" != --sh-script; then
    export PATH=/dev/null/missing; exec "$mydir"/tools/busybox sh "$0" --sh-script-mydir "$mydir" "$@"; exit 1
  fi
  shift
else
  shift; mydir="$1"; shift
fi
test "$ZSH_VERSION" && set -y 2>/dev/null  # SH_WORD_SPLIT for zsh(1). It's an invalid option in bash(1), and it's harmful (prevents echo) in ash(1).
NL="
"  # A single newline.
IFS="$NL"  # Do word splitting only on newline.

perl="$mydir"/tools/miniperl-5.004.04.upx
nasm="$mydir"/tools/nasm-0.98.39.upx
wcc386="$mydir"/tools/wcc386-ow2023-03-04.upx
wlink="$mydir"/tools/wlink-ow1.8.upx
#busybox1="$mydir"tools/busybox-minicc-1.21.1.upx  # awk gsub(...) is not buggy here.

if test $# = 0 || test "$1" == --help; then
  echo "Usage: $0 [<flag> ...] -o <prog> <src.c> [...]" >&2
  test $# = 0 && exit 1
  exit  # Exit successfully on $help.
fi

os=freebsdx; osd="-DOS_LINUX$NL-DOS_FREEBSD"; oscd="-D__MULTIOS__"
confdefs=; cdefs=""
prog=
while true; do
  case "$1" in
   -blinux) os=linux; osd="-DOS_LINUX"; oscd="-D__LINUX__$NL-D__linux$NL-D__linux__$NL-D__gnu_linux__$NL-Dlinux" ;;
   -bfreebsd) os=freebsd; osd="-DOS_FREEBSD"; oscd="-D__FREEBSD__$NL-D__FreeBSD__" ;;
   -bfreebsdx) os=freebsdx; osd="-DOS_LINUX$NL-DOS_FREEBSD"; oscd="-D__MULTIOS__" ;;
   -bwin32) os=win32; osd="-DOS_WIN32"; oscd="-D__NT__$NL-D_WIN32" ;;
   -DCONFIG_*) case "$1" in *=*) confdefs="$confdefs$NL$1" ;; *) confdefs="$confdefs$NL$1=1" ;; esac ;;  # Adding =1 to make NASM behave like C.
   -UCONFIG_*) confdefs="$confdefs$NL$1" ;;
   -[DU]?*) cdefs="$cdefs$NL$1" ;;
   -o?*) prog="${1#-o}" ;;
   -o) prog="$2"; shift ;;  # Empty string if no such arg, will be checked later.
   -*) echo "fatal: unknown command-line flag: $1" >&2; exit 1 ;;
   *) break ;;
  esac
  shift
done
if test $# = 0; then
  echo "fatal: no source file specified" >&2; exit 1
fi
if test -z "$prog"; then
  echo "fatal: missing flag: -o <prog>" >&2; exit 1
fi

wlinkfargs=""
rmfns="$prog.wlinkerr$NL$prog.mu.obj$NL$prog.rex"
for src in "$@"; do
  obj="${src%.*}".obj
  case "${src##*/}" in *.obj) ;; *.*) rmfns="$rmfns$NL$obj" ;; *) echo "fatal: missing extension in source file: $src" >&2; exit 1 ;; esac
  case "$src" in
   -*) echo "fatal: source filename starts with -: $src" >&2; exit 1 ;;  # This may cause a problem in tools interpreting the filename as a flag.
   *.c)
    # -of+ == gcc -fno-omit-frame-pointer
    if ! "$wcc386" -q -s -we -j -ei -ec -bt=linux -fr -zl -zld -e=10000 -zp=4 -3r -os -wx -wce=308 -wcd=201 -D__MMLIBC386__ -D__OPTIMIZE__ -D__OPTIMIZE_SIZE__ $osd -U__LINUX__ $oscd -I"$mydir" -fo=.obj $confdefs $cdefs "$src"; then
      echo "fatal: wcc386 failed" >&2
      exit 2
    fi
    ;;
   *.nasm)
    read line <"$src" || exit 2
    # To disable NASM optimization in the source file, specify nasm:-O0 somewhere in the first line. The default is maximum optimization (-Oz).
    oflag="$(IFS=" 	"; oflag=-Oz; for spec in $line; do case "$spec" in nasm:-O[0-9z]*) oflag="${spec#*:}" ;; esac; done; test "$oflag" = -Oz && oflag=-O999999999; echo "$oflag")"
    if ! "$nasm" $oflag -w+orphan-labels -f obj $osd $confefs -o "$obj" "$src"; then
      echo "fatal: nasm failed" >&2
      exit 2
    fi
    ;;
   *) echo "fatal: unknown type of source file: $src" >&2; exit 1
  esac
  wlinkfargs="$wlinkfargs$NL""f$NL$obj"
done

rm -f -- "$prog"
if test "$os" = win32; then
  wlinkargs="form win nt ru con=3.10 op h=4K com h=0 op st=1024K com st=64K"  # TODO(pts): Make this configurable.
  wlinkoutfn="$prog"  # Expected extension: .exe.
else
  wlinkargs="form phar rex disable 1014"
  wlinkoutfn="$prog".rex
fi
"$wlink" op q op start=_cstart_ op noext op nou op nored op d $wlinkargs $wlinkfargs n "$wlinkoutfn" >"$prog".wlinkerr 2>&1 || exit_code="$?"
test "$exit_code" = 0 && test -s "$prog".wlinkerr && exit_code=-1
if test "$exit_code" != 0; then
  undefsyms="$(awk '{
      if(/^Error\! E2028: ([^ \t]+) is an undefined reference$/){printf"%c%s",c,$3;c=","}
      else if(/^file /&&/: undefined symbol /){}  # A subset of above.
      else{print>>"/dev/stderr";printf",?,"}
      }
      END{if(c&&c%16==0){printf",,"}}  # Work around segfault-for-16-argument-macro bug in NASM 0.98.39.
      ' <"$prog".wlinkerr)"
  if test "$?" != 0; then
    echo "fatal: wlink error parsing failed" >&2
  fi
  case "$undefsyms" in
   *,\?,*) exit 1 ;;  # Found some error messages other than undefined references.
   "") exit 1 ;;  # Linker failure without undefinded references. This is an internal logic error.
  esac
  if ! "$nasm" -O0 -w+orphan-labels -f obj -DUNDEFSYMS="$undefsyms" $osd $confdefs -o "$prog".mu.obj "$mydir"/mmlibc386.nasm; then
    echo "fatal: nasm failed" >&2
    exit 2
  fi
  # We must put  "$prog".mu.obj first, because of the 'ETXT' at the beginning of section CONST.
  if ! "$wlink" op q op start=_cstart_ op noext op nou op nored op d $wlinkargs f "$prog".mu.obj $wlinkfargs n "$wlinkoutfn"; then
    echo "fatal: wlink2 failed" >&2
    exit 2
  fi
fi
if test "$os" = win32; then
  if ! "$perl" -x "$mydir"/fixpe.pl "$prog"; then  # !!! write
    echo "fatal: fixpe failed" >&2
    exit 2
  fi
else
  if ! "$perl" -x "$mydir"/rex2elf.pl -b"$os" "$wlinkoutfn" "$prog"; then
    echo "fatal: rex2elf failed" >&2
    exit 2
  fi
  if ! chmod +x "$prog"; then
    echo "fatal: chmod failed" >&2
    exit 2
  fi
fi

# !! Remove temporary files even on failure.
rm -f -- $rmfns

: "$0" OK.
