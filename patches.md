Feature matrix and patches of various DOS releases:

|functionality                        |MS 4.01|MS 5.00|MS 6.22|MS 7.0 |MS 7.1 |MS 8.0 |PC 2000|PC 7.1 |
|-------------------------------------|-------|-------|-------|-------|-------|-------|-------|-------|
|FAT count == 1 for HDD               |patched|patched|patched|yes    |yes    |yes    |patched|patched|
|FAT count == 1 for floppy            |patched|patched|patched|yes    |yes    |yes    |patched|yes    |
|reserved sectors > 1 for HDD         |patched|yes    |yes    |yes    |yes    |yes    |yes    |yes    |
|reserved sectors > 1 for floppy      |patched|yes    |yes    |yes    |yes    |yes    |yes    |yes    |
|boot io.sys from start cluster > 2   |patched|yes    |yes    |yes    |yes    |yes    |yes    |yes    |
|boot io.sys fragmented               |?? no  |?? no  |??  no |no     |no     |no     |?? no  |?? no  |
|boot io.sys from ~2 GiB with CHS     |new bs |new bs |new bs |??     |??     |yes    |??     |??     |
|boot msdos.sys fragmented            |yes    |yes    |yes    |N/A    |N/A    |N/A    |yes    |yes    |
|FAT32 boot and access                |no     |no     |no     |yes    |yes    |yes    |no     |yes    |
|HDD access with EBIOS LBA  (auto??)  |no     |no     |no     |yes    |yes    |yes    |??     |??     |
|access with wrong hidden sectors     |??     |??     |??     |??     |??     |??     |??     |??     |
|boot with wrong hidden sectors       |new bs |new bs |new bs |new bs |new bs |new bs |new bs |new bs |
|access with wrong cyls and heads     |??     |??     |??     |??     |??     |??     |??     |??     |
|boot FAT16 with wrong cyls and heads |new bs |new bs |new bs |??LBA  |??LBA  |LBA    |new bs |new bs |
|boot FAT32 with wrong cyls and heads |N/A    |N/A    |N/A    |??LBA  |??LBA  |LBA    |N/A    |LBA    |
|kernel and command.com are 8086 only |yes    |yes    |yes    |??     |??     |??     |yes    |yes    |
|FAT16 boot sector code is 8086 only  |yes    |yes    |yes    |yes    |yes    |no     |yes    |yes    |
|FAT32 boot sector code is 8086 only  |N/A    |N/A    |N?A    |??     |??     |no     |N/A    |yes    |
|msload (io.sys start) is 8086 only   |yes    |yes    |yes    |??     |no     |no     |yes    |yes    |

About *boot io.sys fragmented*:

* *MS 7.1* msload (first few sectors of io.sys) assumes that the first 4
  sectors of io.sys.sys are not fragmented. msloadv7i.nasm solves this.
* All original boot sectors assume that the first 3--4 sectors of io.sys are
  not fragmented. New boot sectors (e.g. boot.asm and iboot.asm) solve this.
