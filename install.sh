#!/bin/sh

# check syntax

sh -n ./lukskeychain
if [ $? -gt 0 ]; then # if not opened we will not retry
 echo "ERROR: Syntax error in lukskeychain."
 exit 1
fi

sh -n ./lukskeychainclose
if [ $? -gt 0 ]; then # if not opened we will not retry
 echo "ERROR: Syntax error in lukskeychainclose."
 exit 1
fi

sh -n ./lukskeychainfunctions
if [ $? -gt 0 ]; then # if not opened we will not retry
 echo "ERROR: Syntax error in lukskeychainfunctions."
 exit 1
fi

sh -n ./crypttabcopy
if [ $? -gt 0 ]; then # if not opened we will not retry
 echo "ERROR: Syntax error in crypttabcopy."
 exit 1
fi

sh -n ./mccopy
if [ $? -gt 0 ]; then # if not opened we will not retry
 echo "ERROR: Syntax error in mccopy."
 exit 1
fi

# Check if the script is being executed as root
if [ "$(id -u)" -ne 0 ]; then
  echo "Please execute this script as root. Installation aborted."
  exit 1
fi

if [ -r "/etc/crypttab" ]; then
  echo "File /etc/crypttab exists. Make sure it's updated before running update-initramfs."
else
  echo "ERROR: File /etc/crypttab not found. Installation aborted."
  exit 1
fi

if [ -r "/etc/crypttab.initrdlukskeychain.key" ]; then

    echo "File /etc/crypttab.initrdlukskeychain.key exists. Make sure it's updated before running update-initramfs."

    grep_command_output=$(grep " /mykeys/key.txt " /etc/crypttab.initrdlukskeychain.key)

    if [ -z "${grep_command_output}" ]; then
      echo "ERROR: File /etc/crypttab.initrdlukskeychain.key does not appear to be edited properly. Please include the key path."
      echo "Installation aborted."
      exit 1
    else
      echo "Looks like the key path is specified in /etc/crypttab.initrdlukskeychain.key, but make sure to review it"
      echo "because this script can only perform a very basic sanity check."
    fi

else
    echo 
    echo "WARNING: File /etc/crypttab.initrdlukskeychain.key not found."
    echo "         The crypttabcopy script will attempt to create a crypttab.key file."
    echo "         Please verify its accuracy."
    echo "         You can use the script make_crypttab.sh to generate an example."
    echo 
fi



# grep_command_output=$(grep " /mykeys/key.txt " /etc/crypttab)
# New version - ignoring comments:

# grep_command_output=$(grep -v "^#" /etc/crypttab | grep " /mykeys/key.txt ")

# More advanced version:

grep_command_output=$(sed 's/[[:space:]]*#.*//' /etc/crypttab | grep " /mykeys/key.txt ")
if [ -z "${grep_command_output}" ]; then
  echo "At first glance, it looks like /etc/crypttab is okay."
  echo "However, this script uses very basic sanity checks."
  echo "Make sure you understand how the system works to ensure"
  echo "the configuration will work properly."
else
  echo "ERROR: A key path /mykeys/key.txt is found in /etc/crypttab. Installation aborted."
  exit 1
fi

# I don't remember why the previous version was like this:
# grep_command_output=$(grep "cat /etc/crypttab | tr -s ' ' | cut -d ' ' -f 3 | sort -u | grep -v -P ^none$" /etc/crypttab)

# This looks more sane:
# grep_command_output=$(cat /etc/crypttab | tr -s ' ' | cut -d ' ' -f 3 | sort -u | grep -v -P ^none$)

# But here is advanced version that ignores the commendts:
# grep_command_output=$(sed 's/[[:space:]]*#.*//' /etc/crypttab | tr -s ' ' | cut -d ' ' -f 3 | sort -u | grep -v -P ^none$)

# Fixed it to be more POSIX-compliant:
# grep_command_output=$(sed 's/[[:space:]]*#.*//' /etc/crypttab | tr -s ' ' | cut -d ' ' -f 3 | sort -u | grep -v '^none$')

# Fixed it to get rid of the whitespace when the output is empty (only whitespace):
grep_command_output=$(sed 's/[[:space:]]*#.*//' /etc/crypttab | tr -s ' ' | cut -d ' ' -f 3 | sort -u | grep -v '^none$' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^[[:space:]]*$')

probably_conflicting_settings=""

if [ -z "${grep_command_output}" ]; then
  echo "Looks like /etc/crypttab is okay (we didn't find key paths), but make sure to review it"
  echo "because this script can only perform a very basic sanity check."
else
  echo "WARNING: We found key paths in /etc/crypttab. Please check if they are valid."
  probably_conflicting_settings="yes"
fi

# grep_command_output=$(grep "keyscript=decrypt_keyctl" /etc/crypttab)

# Fixed it - ignoring comments, cleaning whitespace.
grep_command_output=$(sed 's/[[:space:]]*#.*//' /etc/crypttab | grep "keyscript=decrypt_keyctl" |  grep -v '^[[:space:]]*$')

if [ -z "${grep_command_output}" ]; then
  echo "WARNING: No keyscript=decrypt_keyctl parameter found in /etc/crypttab."
  echo "         Are you booting from a non-mirrored root partition?"
else
  if [ -z "${probably_conflicting_settings}" ]; then
    echo "Looks like you have keyscript=decrypt_keyctl in /etc/crypttab (the default crypttab"
    echo "that will be used in case the key is not found)."
  else
    echo "WARNING: Mixed parameters in /etc/crypttab - you have key paths."
  fi
fi



# Get the UUID of the root filesystem
# root_uuid=$(awk '$2 == "/" {print $1}' /proc/mounts | xargs blkid -s UUID -o value)
root_uuid=$(blkid -s UUID -o value "$(awk '$2 == "/" {print $1}' /proc/mounts)")

# Find all partitions with the same UUID
matching_partitions=$(blkid | awk -v uuid="$root_uuid" '$0 ~ "UUID=\""uuid "\"" {gsub(":", "", $1); print $1}')
echo "Partitions with the same UUID as the root filesystem ($root_uuid):"
echo "$matching_partitions"

echo "Checking partitions if they are listed in crypttab files..."

error_count=0

for this_partition in $matching_partitions; do
    # partition_name="${this_partition##*/}"
    partition_name=$(basename "$this_partition")

    if grep -q "^[[:space:]]*$partition_name[[:space:]]" /etc/crypttab; then
        echo "$this_partition exists in /etc/crypttab"
    else
        echo "$this_partition does not exist in /etc/crypttab"
        error_count=$((error_count + 1))
    fi

    if [ -e "/etc/crypttab.initrdlukskeychain.key" ]; then
        if grep -q "^[[:space:]]*$partition_name[[:space:]]" /etc/crypttab.initrdlukskeychain.key; then
            echo "$this_partition exists in /etc/crypttab.initrdlukskeychain.key"
        else
            echo "$this_partition does not exist in /etc/crypttab.initrdlukskeychain.key"
            error_count=$((error_count + 1))
        fi
    fi

done

if [ $error_count -gt 0 ]; then

   echo "Total errors (missing partitions in crypttab files): $error_count"
   echo "Please correct the errors in the crypttab files. Installation aborted. "
   exit 1

fi


default_UUID="fcc2a7e6-8b26-4055-a473-53132bbeb56f"
grep_command_output=$(grep "${default_UUID}" lukskeychain)

if [ -z "${grep_command_output}" ]; then
 echo "ERROR: The expected string not found in lukskeychain. Installation aborted."
fi


default_UUID_txt_file="default_UUID.txt"

if [ -r "${default_UUID_txt_file}" ]; then
 new_default_UUID=$(cat default_UUID.txt | head -n 1)
else
 echo "ERROR: Can't read the file \'${default_UUID_txt_file}\'."
 exit 1
fi


if echo "${new_default_UUID}" | grep -Eq '^\{?[A-F0-9a-f]{8}-[A-F0-9a-f]{4}-[A-F0-9a-f]{4}-[A-F0-9a-f]{4}-[A-F0-9a-f]{12}\}?$'; then
  echo "Looks like a valid UUID."
else 
  if echo "${new_default_UUID}" | grep -Eq '^[A-F0-9a-f]{0,8}-?[A-F0-9a-f]{0,4}-?[A-F0-9a-f]{0,4}-?[A-F0-9a-f]{0,4}-?[A-F0-9a-f]{0,12}$'; then
    echo "Partially valid UUID detected."
  else    
    echo "ERROR: The value in default_UUID.txt is not a valid UUID nor a valid substring (portion) of a valid UUID."
    echo "       Installation aborted."
    exit 1
  fi
fi


if [ "${default_UUID}" = "${new_default_UUID}" ]; then
 echo "ERROR: The configuration file default_UUID.txt was not modified by the user.  Installation aborted."
 exit 1
fi


sed "s/${default_UUID}/${new_default_UUID}/g" "lukskeychain" > "lukskeychain.tmp"

grep_command_output=$(grep "${new_default_UUID}" lukskeychain.tmp)

if [ -z "${grep_command_output}" ]; then
 echo "ERROR: The new UUID not found in the modified file lukskeychain.tmp. Installation aborted."
 exit 1
fi

grep_command_output=$(grep "${default_UUID}" lukskeychain.tmp)

total_exit_status=0

if [ -z "${grep_command_output}" ]; then
  install -m 755 crypttabcopy /etc/initramfs-tools/hooks/crypttabcopy
  command_exit_status=$?
  total_exit_status=$(( command_exit_status + total_exit_status ))
  install -m 755 lukskeychainclose /etc/initramfs-tools/scripts/local-bottom/lukskeychainclose
  command_exit_status=$?
  total_exit_status=$(( command_exit_status + total_exit_status ))
  install -m 755 lukskeychainfunctions /etc/initramfs-tools/scripts/lukskeychainfunctions
  command_exit_status=$?
  total_exit_status=$(( command_exit_status + total_exit_status ))
  install -m 755 lukskeychain.tmp /etc/initramfs-tools/scripts/init-premount/lukskeychain
  command_exit_status=$?
  total_exit_status=$(( command_exit_status + total_exit_status ))
  rm lukskeychain.tmp
  install -m 755 mccopy /etc/initramfs-tools/hooks/mccopy
  command_exit_status=$?
  total_exit_status=$(( command_exit_status + total_exit_status ))
else
  echo "ERROR: The file lukskeychain.tmp was not modified properly by this script. Installation aborted."
  exit 1
fi


# Check for errors
if [ $total_exit_status -gt 0 ]; then
  echo
  echo "ERROR: Error(s) occurred during installation commands."
  echo
  exit 1
else
  echo "Looks like the installation was successful. Now you need to run update-initramfs."
  echo "This script will not run update-initramfs in case undetected errors occurred."
  echo "Please double check the configuration before running update-initramfs."
  echo "Example command: update-initramfs -u -b /root/testboot"
  echo "This updates the initrd.img file in the directory /root/testboot."
  echo "For example, the filename can be initrd.img-6.2.0-26-generic (it may be different"
  echo "due to a different version of your kernel)."
  echo "Use 'update-initramfs -u -k \$(uname -r)' if you don't want to update old initrd images."
fi

