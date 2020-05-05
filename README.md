# DataDomain Recovery

## Disclaimer
This is for personal use and only for advanced users. If you still have support on your DataDomain - USE IT!
I don't work for DELLEMC or am trained in their products, so there might be wrong information following.
If you have improvements on this topic, please open a pull request.

## For whom
This is for you, if you **don't have support** on your EMC DataDomain and you ran into problems with running it.
The steps will most problably void your warranty.

## From what to recover
If DataDomain does not service your requests for the provided protocols anymore.
If you experience an error on the web interface like *An unknown error occurred. Please check your log files and try again.*
If you only have a *limited session* available via serial or normal tty console.

## Cause 1
There is most probably insufficient space on the */ddr* mount point.
Sometimes the reason can be huge log files, but the common problem is the too big historical database of the DataDomain (*dd_hd.db*).
There is a [knowledge base article (DOC-79510)](https://community.emc.com/docs/DOC-79510) which describes the problem resolution if you have a unit under support.
Definatly follow this guide if you still have support!

## Cause 2
The DataDomain saves core dumps of every unexpected shutdown or application crash. These dumps will never get cleaned up and will clog up the root filesystem. Follow the Resolution guide below, but instead mount **/dev/dd_dg0_0p13** and check the **core** directory.

## Resolution
The DataDomain is a pretty sealed environment. The is a password on the grub bootloader and every change to core files will be reverted after a succesful boot.
In this section I will describe how to gain access to the right partitions and how to reclaim space.

1.  Prepare two usb sticks

    On stick with live good live distribution like [GRML](https://grml.org/)
    The second with an **ext3** partition, the files from this repository and 4 GB of space, because the *dd_hd.db* can grow bigger than 2 GB.

2.  Plug the first usb stick into the DataDomain and boot from it.

    After booting plugin the second usb stick and mount it.
    You can get the device name of the second usb stick via dmesg.

        # get device name of second usb stick, e.g. /dev/sdb1
        $ dmesg | tail
        $ mkdir -p /mnt/stick
        $ mount /dev/sdb1 /mnt/stick

    At this point you can patch the initrd and the grub configuration.

        $ chmod u+x /mnt/patch.sh && /mnt/patch.sh

    The *patch.sh* script does a couple of things:

        1.  get the current initrd
        2.  copy it over to a working directory
        3.  unpack it
        4.  patch an rc.d script to get a bash before we switch the the root fs 
            (and also load usb drivers for the sticks)
        5.  pack the initrd
        6.  copy the initrd to every boot device and patch the grub.cfg
            (this is not strictly needed, but i liked to patch out the password for the next boot)
        7.  make backups of the initrd on the stick

3.  Reboot the DataDomain, the bash will come up

4.  Mount the second usb stick again (like in Step 2)

5.  Mount the */ddr* partition

    The */ddr* mount point is on my DD640 on the block device **/dev/dd_dg0_0p4**

        $ mkdir -p /mnt/ddr
        $ mount /dev/dd_dg0_0p4 /mnt/ddr

6.  Exploration phase

    Search for large files, use *du* for sizes of directories.
    Use *find* to search for log files and there size and make some space.

    If there is still no space left, than you have to tamper with the historical database,
    otherwise **reboot**

7.  Get the historical database

    Copy the historical database to you second usb stick.

        $ cp /mnt/ddr/hd/dd_hd.db /mnt/stick/
        $ umount /mnt/stick

8.  Modify the historical database

    This step has to be done on another system with install sqlite3 package.

    The database is a sqlite3 database with custom 40 Byte prefix. Standard sqlite3 tools will not recognise this file from the get got.
    So, we have to strip the header from the file.

    Header:
    ```
    00000000  25 04 dd 5f 00 10 00 00  2a 00 00 00 00 00 00 00  |%.._....*.......|
    00000010  00 00 00 00 00 00 00 00  ff ff ff ff ff ff ff ff  |................|
    00000020  2f 17 02 73 39 17 dc bf  53 51 4c 69 74 65 20 66  |/..s9...SQLite f|
    00000030  6f 72 6d 61 74 20 33 00  10 00 01 01 40 40 20 20  |ormat 3.....@@  |
    00000040  00 78 85 21 00 07 e7 96  00 00 00 00 00 00 00 00  |.x.!............|
    00000050  00 00 80 67 00 00 00 04  00 00 00 00 00 00 00 00  |...g............|
    ```

    Prerequisite: mounted usb stick, e.g. at /media/stick
 
        # make temporary directory
        $ mkdir -p $HOME/db
        # copy db
        $ cp /media/stick/dd_hd.db $HOME/db/
        # copy header to extra file
        $ dd if=$HOME/db/dd_hd.db of=$HOME/db/dd_hd.db.header bs=1 count=40
        # copy the actually sqlite db
        $ dd if=$HOME/db/dd_hd.db of=$HOME/db/dd_hd.db.sqlite bs=8 skip=5
        # clear the big relations in the database
        $ sqlite3 $HOME/db/dd_hd.db.sqlite "DELETE FROM HD_PERF_DISKS; DELETE FROM HD_PERF_NODES; DELETE FROM HD_PERF_MTREES; DELETE FROM HD_PERF_NETS; DELETE FROM HD_PERF_CPUS; DELETE FROM HD_PERF_COLS; DELETE FROM HD_PERF_REPL_THROTTLES; VACUUM;"
        # copy the resulting files back to the usb stick
        $ cat $HOME/db/dd_hd.db.header $HOME/db/dd_hd.db.sqlite > /media/stick/dd_hd.db
        # unmount the stick
        $ umount /media/stick
    
9.  Copy the altered historical database to the DataDomain

    We copy the historical database from the usb stick to the DataDomain

    Prerequisite:  mount the usb stick like in Step 2

        # copy the database
        $ cp /mnt/stick/dd_hd.db /mnt/ddr/hd/dd_hd.db
        # clean old copies and temp files
        $ rm -f /mnt/ddr/hd/*.gz
        # unmount stick and ddr partiton
        $ umount /mnt/stick /mnt/ddr

10. **reboot**
    
    Your DataDomain should boot again into the bash, just press Ctrl-D. After that the boot continuous normally.
    Voila, you have a working DataDomain, again.

## Other bits
I cracked the grub password with hashcat in a couple of hours. It is **ddrc0s**.
After that I googled the password and found a [tutorial](https://www.wikihow.com/Access-the-Bios,-Grub-Boot-Menu-and-Bash-Shell-of-a-Data-Domain-Appliance) to get to the bash without modifying the initrd (by appending **goto-bash** at the end of the kernel command line).
I gave it a try and it did not work for me.
