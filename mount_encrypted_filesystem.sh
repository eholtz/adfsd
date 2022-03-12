#!/bin/bash

# these are the nodes holding the key parts. can be accessed via 
# dns name or ip as the network should already be up. The 
# sequence obviously has to be aligned with knockd.conf on the 
# actual nodes.
kcli="192.168.122.80 192.168.122.39"
kseq="7001 7002 7003;22"
kmet="knock;ssh"

# just example values
encrypted_device="/dev/vdb"
mounted_filesystem="/crypt/"

# as we have some timeouts that depend on each other we use
# a sleep base to calulate tha actual sleep values. Three
# turns ot fine for me but if your connection is particularly
# slow it might be necessary to increase that
sleep_base=3

# putting this into a memory file system is a good idea.
# most people will presumably not change this. it should be
# writeable though ...
incoming_key_dir="/dev/shm/splittedkeys/"

# if you are using ssh we need a private key to use and the
# user name on the destination machine
ssh_private_key="/root/.ssh/id_getkey.priv"
ssh_remote_user="eh"


## it should not be necessary to change anything below this line
## do so at your own risk
###########################################################################
###########################################################################

## additional variables that come in handy
incoming_key_dir_sub="$incoming_key_dir/parts"
luksName=$(echo $mounted_filesystem | base64)

## functions start

# this loop goes on forever and tries to fetch the key parts
function wait_for_keyparts() {
	numkeys=$(echo $kcli | wc -w)
	while [ $(ls $incoming_key_dir_sub | wc -l) -ne $numkeys ] ; do
		echo "got $(ls $incoming_key_dir_sub | wc -l) out of $numkeys key parts"
		knock_and_get_key_loop
		sleep $((sleep_base * 2))
	done
}

# this loop checks if any key part is missing and if so
# starts the fetching
function knock_and_get_key_loop() {
	counter=0
  for client in $kcli ; do
		counter=$((counter + 1))
    # if the key is already there we skip
    [ -e $incoming_key_dir_sub/$counter ] && continue
		method=$(echo $kmet | cut -d ';' -f $counter)
		[ "$method" == "knock" ] && knock_and_get_key $counter $client &
		[ "$method" == "ssh" ] && get_key_via_ssh $counter $client &
	done
}

# this function copys the key part via ssh from a remote system
function get_key_via_ssh() {
	keypart=$1
	client=$2
	timeout $((sleep_base * 2)) scp -i $ssh_private_key $ssh_remote_user@$client:/home/$ssh_remote_user/keypart $incoming_key_dir_sub/$keypart || rm $incoming_key_dir_sub/$keypart
}

# this function knocks to the nth system (given as first parameter
# and grabs the key that will be sent over
function knock_and_get_key() {
	keypart=$1
	client=$2
	# get the knock sequence
	sequence=$(echo $kseq | cut -d ';' -f $keypart)
	# the last port of the sequence is important, as the transport port is
	# based on that
	lastport=$(echo $sequence | sed "s/.*\ \([0-9]*$\)/\1/")
	knock $client $sequence
	sleep $sleep_base
	timeout $((sleep_base * 2)) netcat $client $((lastport + 1)) > $incoming_key_dir_sub/$keypart || rm $incoming_key_dir_sub/$keypart
}

## functions end

# should we unmount and close?
if [ -n "$1" ] ; then
	fuser -km $mounted_filesystem
	umount $mounted_filesystem
	cryptsetup luksClose $luksName
	exit 0
fi

# before we even start we check if there is already a crypt device with the name we want to use
[ -n "$(mount | grep $luksName)" ] && echo "$mounted_filesystem seems to be mounted already ?!" && exit 1

# do a cleanup just in case & create the directories needed
[ -e $incoming_key_dir ] && rm -rf $incoming_key_dir
mkdir -p $incoming_key_dir_sub || exit 1
mkdir -p $mounted_filesystem || exit 1

# wait for the key parts to arrive
# we do not exit any function when an arror occurs
# this in on purpose, so we can clean up
wait_for_keyparts

echo "all key parts are there, assembling and mounting ..."

# assemble the key
cat $incoming_key_dir_sub/* | base64 -d > $incoming_key_dir/key

# open the crypted device
cryptsetup luksOpen $encrypted_device $luksName --key-file=$incoming_key_dir/key

# be sure to throw away the incoming keys => cleanup
find $incoming_key_dir -type f -exec shred -u {} \;
rm -rf $incoming_key_dir

# now mount the file system
mount /dev/mapper/$luksName $mounted_filesystem && echo "mount has been successful" && exit 0
echo "ERROR: failed to mount $mounted_filesystem for some reason"
exit 1
