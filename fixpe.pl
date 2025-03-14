#!/bin/sh --
eval 'PERL_BADLANG=x;export PERL_BADLANG;exec perl -x "$0" "$@";exit 1'
#!perl  # Start marker used by perl -x.
+0 if 0;eval("\n\n\n\n".<<'__END__');die$@if$@;__END__

#
# fixpe.pl: fix Win32 PE .exe program file, outout of wlink(1)
# by pts@fazekas.hu at Mon Feb 10 15:26:25 CET 2025
#
# This script works with Perl 5.004.04 (1997-10-15) or later.
#
# !! Instead of a patcher, write a better PE linker (or relinker), which omits sections other than .text and .data, and overlaps sections, and avoids the 0x200 padding.
# !! Move CONST and CONST2 from DGROUP to _TEXT.
# !! Make PE .exe smaller by making the PE header <=512 bytes and merging .idata to .data
# !! also make sure that only __imp__ pointers are imported (don't use wlink(1) import).
#

BEGIN { $ENV{LC_ALL} = "C" }  # For deterministic output. Typically not needed. Is it too late for Perl?
BEGIN { $ENV{TZ} = "GMT" }  # For deterministic output. Typically not needed. Perl respects it immediately.
BEGIN { $^W = 1 }  # Enable warnings.
use integer;
use strict;

my $v = 0;
for (my $i = 0; $i < @ARGV; ++$i) {
  my $arg = $ARGV[$i];
  if ($arg eq "--") { splice(@ARGV, 0, $i + 1); last }
  elsif ($arg eq "-" or $arg !~ m@^-@) { splice(@ARGV, 0, $i); last }
  elsif ($arg eq "-v") { ++$v }  # More verbose.
  else { die("fatal: unknown command-line flag: $arg\n") }
}
die("Usage: $0 [<flag> ...] <input.rex> <output>\n") if @ARGV != 1 or $ARGV[0] eq "--help";
my $infn = $ARGV[0];

sub fnopenq($) { $_[0] =~ m@[-+.\w]@ ? $_[0] : "./" . $_[0] }
die("fatal: open: $infn: $!\n") if !open(F, "+< " . fnopenq($infn));
$_ = undef;
die("fatal: read: $infn: $!\n") if !defined(sysread(F, $_, 0x1000));
die("fatal: not an MZ .exe file: $infn\n") if length($_) < 0x18 or substr($_, 0, 2) ne "MZ";
my $pe_fofs;
die("fatal: not a PE .exe file: $infn\n") if length($_) < 0x40 or ($pe_fofs = unpack("V", substr($_, 0x3c, 4))) + 0x78 > length($_) or $pe_fofs < 4 or substr($_, $pe_fofs, 4) ne "PE\0\0";
my($PeSignature, $Machine, $NumberOfSections, $TimeDateStamp,
   $PointerToSymbolTable, $NumberOfSymbols, $SizeOfOptionalHeader,
   $Characteristics, $Magic, $MajorLinkerVersion, $MinorLinkerVersion,
   $SizeOfCode, $SizeOfInitializedData, $SizeOfUninitializedData,
   $AddressOfEntryPoint, $BaseOfCode, $BaseOfData, $ImageBase,
   $SectionAlignment, $FileAlignment, $MajorOperatingSystemVersion,
   $MinorOperatingSystemVersion, $MajorImageVersion, $MinorImageVersion,
   $MajorSubsystemVersion, $MinorSubsystemVersion, $Win32VersionValue,
   $SizeOfImage, $SizeOfHeaders, $CheckSum, $Subsystem, $DllCharacteristics,
   $SizeOfStackReserve, $SizeOfStackCommit, $SizeOfHeapReserve,
   $SizeOfHeapCommit, $LoaderFlags, $NumberOfRvaAndSizes,
  ) = unpack("a4vvVVVvvvCCVVVVVVVVVvvvvvvVVVVvvVVVVVV", substr($_, $pe_fofs, 0x78));
$TimeDateStamp = 1;  # Hardcode a fixed timestamp for reproducible builds.
#$SizeOfStackReserve = 1024 << 10;  # Not needed. wlink op st=1024K
#$SizeOfStackCommit = 64 << 10;  # Not needed. wlink com st=64K
$SizeOfHeapReserve = 0;  # This is not needed for wlink-ow2023-03-04, but need for wlink-ow1.8 and wlink-ow1.9.
#$SizeOfHeapCommit = 0;  # Not needed. wlink com h=0
die("fatal: error seeking in PE .exe file: $infn\n") if (sysseek(F, $pe_fofs, 0) or 0) != $pe_fofs;
my $s = pack(
    "a4vvVVVvvvCCVVVVVVVVVvvvvvvVVVVvvVVVVVV",
    $PeSignature, $Machine, $NumberOfSections, $TimeDateStamp,
    $PointerToSymbolTable, $NumberOfSymbols, $SizeOfOptionalHeader,
    $Characteristics, $Magic, $MajorLinkerVersion, $MinorLinkerVersion,
    $SizeOfCode, $SizeOfInitializedData, $SizeOfUninitializedData,
    $AddressOfEntryPoint, $BaseOfCode, $BaseOfData, $ImageBase,
    $SectionAlignment, $FileAlignment, $MajorOperatingSystemVersion,
    $MinorOperatingSystemVersion, $MajorImageVersion, $MinorImageVersion,
    $MajorSubsystemVersion, $MinorSubsystemVersion, $Win32VersionValue,
    $SizeOfImage, $SizeOfHeaders, $CheckSum, $Subsystem, $DllCharacteristics,
    $SizeOfStackReserve, $SizeOfStackCommit, $SizeOfHeapReserve,
    $SizeOfHeapCommit, $LoaderFlags, $NumberOfRvaAndSizes);
die("fatal: error writing PE header to PE .exe file: $infn\n") if (syswrite(F, $s, 0x78) or 0) != 0x78;
#close(F);  # Not needed, the operating system will close it at process exit.

__END__
