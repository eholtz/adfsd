# adfsd
Automated Distributed File System Decryption

# Description
This is a collection of scripts to automatically decrypt a file system when booting a linux system without the need of having the file locally on the system. The scripts are featured in a talk for Chemnitzer Linuxtage 2022 https://chemnitzer.linux-tage.de/2022/de/programm/beitrag/253 (The talk is german)

# Howtos
## How to generate a key for LUKS
Store that somewhere safe. Together with the LUKS header things can be decrypted.

`dd if=/dev/urandom of=/dev/shm/key bs=1M count=1`

## How to transform the key & split it into two pieces
Using base64 makes it a lot easier to handle the file. Transfer the splitted key to the remote systems.

`base64 /dev/shm/key /dev/shm/key_b64
split -n 2 /dev/shm/key_b64 key_`

## How to set up a LUKS encrypted container
There is only one key present in the LUKS container. And that one is not human readable.

`cryptsetup luksFormat --key-file /dev/shm/key /dev/vdb`

`cryptsetup luksOpen --key-file /dev/shm/key /dev/vdb lukscrypt`

`mkfs.ext4 /dev/mapper/lukscrypt`

## How to backup a LUKS header
Store that somewhere safe. Together with the key things can be decrypted.

`cryptsetup luksHeaderBackup /dev/vdb --header-backup-file /dev/shm/headerbackup`

## How to restore a LUKS header
Just for the sake of completeness. You should consider reading the LUKS manpage anyway.

`cryptsetup luksHeaderRestore /dev/vdb --header-backup-file /dev/shm/headerbackup`

## How to create & enable a systemd service
Works for most distributions.
`cp mount-enc-fs.service /etc/systemd/system/`
`systemctl daemon-reload`
`systemctl enable mount-enc-fs.service`

## How to create & enable knockd
Do at your own risk as this will overwrite an existing file. Remember to adjust /etc/default/knockd if needed.
`cp knockd.conf /etc/`

# Files
knockd.conf|Knock daemon configuration file, usually to be placed under /etc/knockd.conf. Remember that this file is only an example and has to be customized for every node.
mount_encrytped_filesystem.sh|Script to fetch all key parts and mount the encrypted filesystem. Header section has to be customized. This is where all the magic happens. Hsa to be placed under /root/ if you are using the vanilla service file (see below)
mount-enc-fs.service|Systemd unit file, usually to be placed under /etc/systemd/system
unmount_encrypted_filesystem.sh|Script to unmount the filesystem. Actually this is part of mount_encrypted_filesystem.sh and only there for convenience. Should be placed along mount_encrypted_filesystem.sh
