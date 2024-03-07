#!/bin/sh

# Check if the script is being executed as root
if [ "$(id -u)" -ne 0 ]; then
  echo "Please execute this script as root."
  echo "It's only required for the 'cryptsetup status \"\${dev_mapper_device}\"' command."
  echo "This script is not designed to write any files, it shows example crypttab files with echo."
  exit 1
fi


# ************** beginning of the crypttab generator ***************
# root_uuid=$(awk '$2 == "/" {print $1}' /proc/mounts | xargs blkid -s UUID -o value)
root_uuid=$(blkid -s UUID -o value "$(awk '$2 == "/" {print $1}' /proc/mounts)")
matching_dev_mapper_devices=$(blkid | awk -v uuid="$root_uuid" '$0 ~ "UUID=\""uuid "\"" {gsub(":", "", $1); print $1}')

crypttab_file_example=""
crypttab_file_example_key=""

for dev_mapper_device in $matching_dev_mapper_devices; do

    if ! echo "${dev_mapper_device}" | grep -q "^/dev/mapper/"; then
     echo "ERROR: The device \"$dev_mapper_device\" is not in the /dev/mapper directory, this is confusing, stopping."
     exit 1
    fi
    
    mapped_device=$(cryptsetup status "${dev_mapper_device}" | awk '/device:/ { print $2 }')

    this_UUID=$(blkid -s UUID -o value "${mapped_device}")

    partition_name=$(basename "$dev_mapper_device")
    
    if [ -n "${this_UUID}" ]; then
        this_line_for_crypttab="$partition_name UUID=${this_UUID} none luks,discard,keyscript=decrypt_keyctl"
        this_line_for_crypttab_key="$partition_name UUID=${this_UUID} /mykeys/key.txt luks,discard"
        
        crypttab_file_example="${crypttab_file_example}${this_line_for_crypttab}\n"
        crypttab_file_example_key="${crypttab_file_example_key}${this_line_for_crypttab_key}\n"
        
    else
        echo "The UUID for \"$dev_mapper_device\" is not found. This is confusing, stopping."
        exit 1
    fi

done
# ************** end of the crypttab generator ***************

echo
echo "\033[4mExample for /etc/crypttab (all lines):\033[0m"
echo
echo "$crypttab_file_example"
echo
echo "\033[4mExample for /etc/crypttab.initrdlukskeychain.key (all lines):\033[0m"
echo
echo "$crypttab_file_example_key"


