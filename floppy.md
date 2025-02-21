This is based on the *fd_formats* lookup table in
*qemu-2.11.1/hw/block/fdc.c* ([view
online](https://github.com/pengdonglin137/qemu-2.11.1/blob/32692f671e932ac915997b69bce56fc41da59f04/hw/block/fdc.c#L109-L158).

Floppy drives supported by QEMU 2.11.1:

|ID|physical|fantasy |type|rate  |
|--|--------|------- |----|------|
|D1|3.5"    | 1.44 MB| 144|  500K|
|D2|3.5"    | 2.88 MB| 288| 1000K|
|D3|3.5"    |  720 kB| 144|  250K|
|D4|5.25"   |  1.2 MB| 120|  500K|
|D5|5.25"   |  720 kB| 120|  250K|
|D6|5.25"   |  360 kB| 120|  300K|
|D7|5.25"   |  320 kB| 120|  250K|
|D8|3.5"    |  360 kB| 144|  250K|

Floppy sizes supported by QEMU 2.11.1:

|KiB    |MB alias|sectors|cyls|heads|secs|QEMU autodetect|mdesc|DOS support|
|-------|--------|-------|----|-----|----|---------------|-----|-----------|
|  1440K|1.44MB  |  2880S|  80|    2|  18|D1 (D4)        | 0xf0|DOS 3.30 added|
|  1600K|1.6MB   |  3200S|  80|    2|  20|D1 (D4)        | 0xf0||custom|
|  1680K|1.68MB  |  3360S|  80|    2|  21|D1             | 0xf0||custom|
|  1722K|1.722MB |  3444S|  82|    2|  21|D1             | 0xf0||custom|
|  1743K|1.743MB |  3486S|  83|    2|  21|D1             | 0xf0||custom|
|  1760K|1.76MB  |  3520S|  80|    2|  22|D1             | 0xf0||custom|
|  1840K|1.84MB  |  3680S|  80|    2|  23|D1             | 0xf0||custom|
|  1920K|1.92MB  |  3840S|  80|    2|  24|D1             | 0xf0||custom|
|  2880K|2.88MB  |  5760S|  80|    2|  36|D2             | 0xf0|DOS 5.00 added|
|  3120K|3.12MB  |  6240S|  80|    2|  39|D2             | 0xf0||custom|
|  3200K|3.2MB   |  6400S|  80|    2|  40|D2             | 0xf0||custom|
|  3520K|3.52MB  |  7040S|  80|    2|  44|D2             | 0xf0||custom|
|  3840K|3.84MB  |  7680S|  80|    2|  48|D2             | 0xf0||custom|
|   720K|--      |  1440S|  80|    2|   9|D3 (D5)        | 0xf9|DOS 3.20 added|
|   800K|--      |  1600S|  80|    2|  10|D3             | 0xf0||custom|
|   820K|--      |  1640S|  82|    2|  10|D3             | 0xf0||custom|
|   830K|--      |  1660S|  83|    2|  10|D3             | 0xf0||custom|
|  1040K|1.04MB  |  2080S|  80|    2|  13|D3             | 0xf0||custom|
|  1120K|1.12MB  |  2240S|  80|    2|  14|D3             | 0xf0||custom|
|  1200K|1.2MB   |  2400S|  80|    2|  15|D4             | 0xf9|DOS 3.00 added, in QEMU DOS >=3.20|
|  1476K|1.476MB |  2952S|  82|    2|  18|D4             | 0xf0||custom|
|  1494K|1.494MB |  2988S|  83|    2|  18|D4             | 0xf0||custom|
|   880K|--      |  1760S|  80|    2|  11|D5             | 0xf0||custom|
| (720K)|--      |  1440S|  80|    2|   9|(D5) D3        | 0xf8|Sanyo DOS-DOS 2.11 added for 5.25"|
|   360K|--      |   720S|  40|    2|   9|D6 (D8)        | 0xfd|DOS 2.00 added|
|   180K|--      |   360S|  40|    1|   9|D6             | 0xfc|DOS 2.00 added and dist|
|   410K|--      |   820S|  41|    2|  10|D6             | 0xf0||custom|
|   420K|--      |   840S|  42|    2|  10|D6             | 0xf0||custom|
|   320K|--      |   640S|  40|    2|   8|D7             | 0xff|DOS 1.10 added|
|   160K|--      |   320S|  40|    1|   8|D7             | 0xfe|DOS 1.00 added and dist|
| (360K)|--      |   720S|  80|    1|   9|(D8) D6        | 0xf8|DOS 3.10 added for 3.5"|

If the *QEMU autodetect* fields contains a parentesis, e.g. *(D8)
D6*, it means that QEMU never autodects this floppy disk as *D8* based on it
size, but it detects the floppy disk as *D6* instead.

The *mdesc* field is the media descriptor byte (boot sector byte 0x15, first
FAT sector byte 0, the two values must match).

According to
[Wikipedia](https://en.wikipedia.org/wiki/Design_of_the_FAT_file_system#media),
DOS 3.20 has supported the 1440K format with media descriptor 0xf9.

DOS support (MS-DOS and IBM PC DOS, with the same version numbers) info
based on:
https://web.archive.org/web/20220213193448/https://sites.google.com/site/pcdosretro/doshist

!! Check whether the 2880K format works in MS-DOS 5.00 running in QEMU 2.11.1

1.2MB virtual floppy disks don't work in DOS 3.00 and 3.10 running in QEMU
2.11.1: https://retrocomputing.stackexchange.com/q/31008/3494 . Solutions:
upgrade to DOS >=3.20 guest; or use a more recent QEMU (unverififed); or use
a different emulator (such as 86Box 4.2.1).

|preset              |   160K|   180K|   320K|   360K|   720K|   1200K|   1440K|   2880K|
|--------------------|-------|-------|-------|-------|-------|--------|--------|--------|
|image size (KiB)    |    160|    180|    320|    360|    720|    1200|    1440|    2880|
|image size (bytes)  | 163840| 184320| 327680| 368640| 737280| 1228800| 1474560| 2949120|
|sector count        |    320|    360|    640|    720|   1440|    2400|    2880|    5760|
|physical size       |5.25"  |5.25"  |5.25"  |5.25"  |3.5"   |5.25"   |3.5"    |3.5"    |
|CHS: cyls/heads/secs|40/1/8 |40/1/9 |40/2/8 |40/2/9 |80/2/9 |80/2/15 |80/2/18 |80/2/36 |
|minimum DOS version |   1.00|   2.00|   1.10|   2.00|   3.20|  ++3.00|    3.30|    5.00|
|filesystem          |FAT12  |FAT12  |FAT12  |FAT12  |FAT12  |FAT12   |FAT12   |FAT12   |
|media descriptor    |   0xfe|   0xfc|   0xff|   0xfd|   0xf9|    0xf9|    0xf0|    0xf0|
|sector size (bytes) |  0x200|  0x200|  0x200|  0x200|  0x200|   0x200|   0x200|   0x200|
|FAT count           |      2|      2|      2|      2|      2|       2|       2|       2|
|cluster size (bytes)|  0x200|  0x200|  0x400|  0x400|  0x400|   0x200|   0x200|   0x400|
|sectors per FAT     |      1|      2|      1|      2|      3|       7|       9|       9|
|rootdir entry count |     64|     64|    112|    112|    112|     224|     224|     240|
|cluster count       |    313|    351|    315|    354|    713|    2371|    2847|    2863|
|free space (bytes)  | 160256| 179712| 322560| 362496| 730112| 1213952| 1457664| 2931712|

The *++3.00* above means that in QEMU 2.11.1, DOS >=3.20 is needed, and in
other emulators (such as 86Box 4.2.1) DOS >=3.0 is enough.

On 2.88 MB and larger floppies: https://boginjr.com/it/hw/ps2/

* Mitsubishi MF356F-899MF, one of the types of 2.88MB drives used in later
  IBM PS/2 variants.
* Regular 1.44MB HD disk formatted to 3.12MB in a 2.88 drive (82 tracks, 39
  spt, sector/format gap 0x10/0x28, 1Mbps perpendicular mode)
* A 3.5″ extended density floppy had twice the number of sectors per track
  than a regular high density diskette.
* More info about the MegaFDC floppy controller: https://boginjr.com/it/hw/megafdc/

About the media descriptor byte:

* Single byte within the boot sector, at offset 0x15, part of the BPB. Also
  must match the FAT ID byte (byte 0 of the first FAT).
* https://en.wikipedia.org/wiki/Design_of_the_FAT_file_system#media
  This value must reflect the media descriptor stored (in the entry for
  cluster 0) in the first byte of each copy of the FAT. Certain operating
  systems before DOS 3.20 (86-DOS, MS-DOS/PC DOS 1.x and MSX-DOS version 1.0)
  ignore the boot sector parameters altogether and use the media descriptor
  value from the first byte of the FAT to choose among internally pre-defined
  parameter templates.
* https://en.wikipedia.org/wiki/Design_of_the_FAT_file_system#FATID
  Versions of DOS before 3.2 totally or partially relied on the media
  descriptor byte in the BPB or the FAT ID byte in cluster 0 of the first
  FAT in order to determine FAT12 diskette formats even if a BPB is present.
  Depending on the FAT ID found and the drive type detected they default to
  use one of the following BPB prototypes instead of using the values
  actually stored in the BPB.
* https://en.wikipedia.org/wiki/Design_of_the_FAT_file_system#FATID
  contains a FAT ID to geometry table.
* 0xf8: Also used by HDDs.
* 0xef: Designated for use with custom floppy and superfloppy formats where the geometry is defined in the BPB.
* !! Try 1.2MB (0xf9) it in QEMU 2.11, DOS 3.00 and 3.10.
