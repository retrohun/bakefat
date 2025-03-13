#! /bin/sh --
#
# compile.sh: compile script for bakefat
# by pts@fazekas.hu at Thu Feb  6 14:12:58 CET 2025
#
# Run it on Linux i386 or amd64: tools/busybox sh compile.sh
#

test "$0" = "${0%/*}" || cd "${0%/*}"
export LC_ALL=C  # For deterministic output. Typically not needed.
export TZ=GMT  # For deterministic output. Typically not needed. Perl respects it immediately.
if test "$1" != --sh-script; then export PATH=/dev/null/missing; exec tools/busybox sh "${0##*/}" --sh-script "$@"; exit 1; fi
shift
test "$ZSH_VERSION" && set -y 2>/dev/null  # SH_WORD_SPLIT for zsh(1). It's an invalid option in bash(1), and it's harmful (prevents echo) in ash(1).
set -ex

sh mmlibcc.sh --sh-script-mydir .         "$@" -o bakefat     bakefat.c boot.nasm  # -march=i386 -Werror -Wno-n201
sh mmlibcc.sh --sh-script-mydir . -bwin32 "$@" -o bakefat.exe bakefat.c boot.nasm

: "$0" OK.
