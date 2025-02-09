#! /bin/sh --
#
# compile.sh: compile script for bakefat
# by pts@fazekas.hu at Thu Feb  6 14:12:58 CET 2025
#
# Run it on Linux i386 or amd64: tools/busybox sh compile.sh
#

test "$0" = "${0%/*}" || cd "${0%/*}"
export LC_ALL=C  # For deterministic output. Typically not needed. Is it too late for Perl?
export TZ=GMT  # For deterministic output. Typically not needed. Perl respects it immediately.
if test "$1" != --sh-script; then export PATH=/dev/null/missing; exec tools/busybox sh "${0##*/}" --sh-script "$@"; exit 1; fi
shift
test "$ZSH_VERSION" && set -y 2>/dev/null  # SH_WORD_SPLIT for zsh(1). It's an invalid option in bash(1), and it's harmful (prevents echo) in ash(1).
set -ex

perl=tools/miniperl-5.004.04.upx
nasm=tools/nasm-0.98.39.upx
busybox1=tools/busybox-minicc-1.21.1.upx  # awk gsub(...) is not buggy here.

"$nasm" -O0 -w+orphan-labels -f bin -o boot.bin boot.nasm
"$nasm" -O0 -w+orphan-labels -f bin -DJUST_BS -o fat12b.bin fat12b.nasm

od -An -to1 -v boot.bin fat12b.bin >boot.od
"$busybox1" awk '{gsub(/ /,"\\");print"\""$0"\""}' <boot.od >boot.h  # awk gsub(...) in our busybox is buggy, use $busybox1 instead.
rm -f boot.od

sh mmlibcc.sh --sh-script-mydir . -o bakefat bakefat.c  # -march=i386 -Werror -Wno-n201

: "$0" OK.
