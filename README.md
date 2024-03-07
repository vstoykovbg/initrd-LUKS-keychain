# initrd-LUKS-keychain

## Overview

Securely unlock encrypted root (and other) partitions at boot time using passphrase-protected keys stored on a USB flash drive. Tested to work with a btrfs root mirror on two LUKS partitions (on Ubuntu 22.04.4).

## Features

### Automated Unlocking

During the boot process, the scripts automatically unlock multiple LUKS-encrypted partitions, requiring minimal manual intervention from users (typically only requiring the supply of a passphrase to decrypt the LUKS keychain).

### Separate Key Storage

The keys required for unlocking the encrypted partitions are stored separately on a removable USB flash drive. This separation of keys from the main system adds an additional layer of security, as access to the encrypted data relies on physical possession of the USB flash drive.

### Passphrase Protection

To enhance security, the keys stored on the USB flash drive are passphrase-protected. This ensures that even if the USB drive is lost or stolen, unauthorized access to the encrypted partitions is prevented without knowledge of the passphrase. Additionally, version 2 of the LUKS headers is the default for newer versions of cryptsetup, incorporating the Argon2 key stretching algorithm. This algorithm is highly effective with heavy key stretching settings, significantly enhancing protection against brute-force attacks, especially with large `--iter-time` settings. 

With this configuration, unauthorized access to the encrypted partitions remains highly improbable without knowledge of the passphrase, even if the removable USB device is compromised. However, it's important to note that while key stretching enhances security, it cannot compensate for very short or weak passphrases; therefore, it's essential to use a strong passphrase for optimal protection.

### RAM Wipe

At least one copy of the key is kept in volatile memory (we hope securely) to access the encrypted data, but we try to erase other copies from the RAM to reduce the risk (and remove from RAM the only copy of the key for the LUKS keychain after it's not needed).
 
After the encrypted partitions (root and others) are unlocked and the LUKS keychain (the encrypted container containing the keys) is closed, while still in the initial ram disk environment, disk caches are dropped using `echo 3 > /proc/sys/vm/drop_caches`. Additionally, the `sdmem` program is invoked to wipe the unused RAM, preventing the keys from being retained in the disk cache (within the RAM). It is assumed that the passphrase used to decrypt the LUKS keychain is securely handled by `cryptsetup`, as it is directly accepted by `cryptsetup` without intermediary applications. In the scenario where the encrypted LUKS keychain is used, there is no password caching with `keyscript=decrypt_keyctl`.

(Please note that these scripts do not handle the RAM wipe during shutdown; you should use other scripts for that purpose.)

### Flexible Configuration

Supports storing the LUKS keychain in either an encrypted partition or an encrypted container file.

## Configuration and Setup

1. **Prerequisites:**
   - Ubuntu 22.04 system with an LUKS-encrypted btrfs root filesystem. It may also work on other similar systems.
   - Basic familiarity with LUKS encryption and filesystem management.
   - USB flash drive or more (for mirrored btrfs configuration).
   - Another USB flsh drive (optional). As explained in more detail below, it's recommended to use a live system to prevent key and passphrase leaks. You may use the same USB flash drive for both the live Ubuntu and the LUKS keychain, but it's recommended not to edit the partition table of a live Ubuntu running from the same USB flash drive. Therefore, the USB flash drive should be partitioned in advance to make space for other partitions (LUKS keychains).

2. **Setup Process:**
   - Choose the desired mode for storing the LUKS keychain (encrypted partition or encrypted container file).
   - Follow the provided instructions below to set up the keychain accordingly.

3. **Installation:**
   - Edit the `default_UUID.txt` file to specify the default UUID that the script will search for. This UUID corresponds to the location where the LUKS keychain is stored.
   - Optional: Edit the `/etc/crypttab.initrdlukskeychain.key` file (if you want to unlock encrypted partitions other than the root). For reference you may use the output of the command `sudo ./make_crypttab.sh`.
   - Run `sudo ./install-and-update-initramfs.sh` to set up the LUKS keychain scripts and update the initramfs.

## Modes of Operation

The scripts support two modes for storing the LUKS keychain:

### Mode 1: Encrypted Partition

- **Description:** The LUKS keychain is stored within a dedicated encrypted partition.
- **Setup:** Involves creating a LUKS-encrypted partition, formatting it with ext4 filesystem, and placing a key file within the filesystem.

```bash
# Create an encrypted partition
cryptsetup luksFormat /dev/sdxn

# Open the encrypted partition
cryptsetup open /dev/sdxn newkeychainonlukspartition

# Format the partition with ext4
mkfs.ext4 /dev/mapper/newkeychainonlukspartition

# Mount the partition
mkdir /mnt/newkeychainonlukspartition
mount /dev/mapper/newkeychainonlukspartition /mnt/newkeychainonlukspartition

# Set appropriate permissions
chmod 700 /mnt/newkeychainonlukspartition

# After the keys are written unmount and close
umount /mnt/newkeychainonlukspartition
cryptsetup close newkeychainonlukspartition
```

### Mode 2: Encrypted Container File

- **Description:** The LUKS keychain is stored in an encrypted container file.
- **Setup:** Requires creating a container file using `dd` and `cryptsetup`, formatting it with ext4 filesystem, and storing the keychain within the container file. This mode has been extensively tested to work with encrypted container files stored on vfat, ext4, and btrfs filesystems.

```bash
# Create a file for the encrypted container
dd if=/dev/urandom of=lkskchn.dat count=20 bs=1M

# Format the file with LUKS encryption
cryptsetup luksFormat lkskchn.dat

# Open the encrypted container
cryptsetup open lkskchn.dat newkeychain

# Format the container with ext4
mkfs.ext4 /dev/mapper/newkeychain

# Mount the container
mkdir /mnt/newkeychain
mount /dev/mapper/newkeychain /mnt/newkeychain

# Set appropriate permissions
chmod 700 /mnt/newkeychain

# After the keys are written unmount and close
umount /mnt/newkeychain
cryptsetup close newkeychain
```
### Preferred Mode

Mode 2 is preferred over Mode 1 due to its portability and flexibility. The encrypted container can be stored on readily available vfat partitions without the need for repartitioning the drive. Additionally, using Mode 2 eliminates the annoying pop-up messages upon inserting the drive. Under GNOME, an annoying pop-up message appears upon inserting the drive formatted according to Mode 1: "Authentication Required", "A passphrase is needed to access encrypted data...".

It is advisable to set the partition as hidden. If the USB drive is accidentally inserted into a Windows system, Windows may prompt to format the partition.

It is recommended to set the partition in Mode 1 as hidden because if you insert the USB drive in Windows accidentally, Windows will ask to format the partition. I have not tested whether the recent version of GParted [correctly](https://serverfault.com/questions/591563/setting-the-hidden-attribute-on-a-partion-from-linux-parted-isnt-respected-b) sets up the hidden attribute. Also, I have not tested whether Windows will ask to format an ext4 or btrfs partition if they are not "hidden".

In the future, I may introduce a Mode 3: hiding the encrypted container within a partition without a signature (header) and with a hidden attribute.

### How the boot process works

First, the script `lukskeychain` searches for a partition with the default UUID. If it's not found, it looks for a partition with a name or filesystem label containing "lukskeychain". If the partition is found and contains a LUKS header, the script attempts to open it using `cryptsetup open`. If no LUKS header is found, the script tries to mount it as a filesystem partition (confirmed to work with vfat, ext4, and btrfs). If mounting fails, the script prompts the user for cryptsetup parameters (assuming it's not a filesystem but rather an encrypted container).

In the typical scenario, the correct partition is found right away by the default UUID (configured before installation in the `default_UUID.txt` file) or by the partition name or filesystem label "lukskeychain". The user only needs to enter the passphrase to open the LUKS keychain (the encrypted partition or the encrypted file container).

If the opening of the LUKS keychain is successful, the keys are accessible in the mount point `/mykeys` within the initial ramdisk. The default filename `key.txt` has a .txt extension because it's assumed that the key is in ASCII format. It can be 20-30 random words generated by a cryptographically secure random number generator (not by the human brain, as it's a [bad source of entropy](https://crypto.stackexchange.com/questions/87978/why-do-some-people-believe-that-humans-are-bad-at-generating-random-numbers-ch)), or a base64 string obtained by reading from `/dev/random` using `dd` (see the examples below).

During the boot process, the key files from the LUKS keychain are not written anywhere; they are used directly by `cryptsetup` from their specified location in `/etc/crypttab` (within the mountpoint `/mykeys`).

### Precautions

Especially if you boot from a [live system](https://en.wikipedia.org/wiki/Live_USB), ensure to seed the random number generator for added randomness. One simple method is to read random sounds from the microphone input and redirect the data to /dev/random. You can find methods for mixing randomness and generating random words [here](https://github.com/vstoykovbg/doublerandom).

To verify that the sound is coming from the microphone input, use the following command:

```bash
arecord  -t raw -f S16_LE -d 10 | aplay
```

To redirect 10 seconds of random data to /dev/random, use:

```bash
arecord  -t raw -f S16_LE -d 10 > /dev/random
```

Seeding may be unnecessary, but it's a precautionary measure.

If you want the key to be written on a single line you can do it like this:

```bash
echo -n $(dd if=/dev/random bs=128 count=1  | base64 -w 1000) > /mykeys/key123456.txt
```

If you don't care about new lines:

```bash
dd if=/dev/random bs=128 count=1  | base64 > /mykeys/key123456.txt
```

You can generate the key directly in a raw format using the following command:

```bash
dd if=/dev/random bs=128 count=1 of=/mykeys/key123456.dat
```

This is the best practice, especially if you do not intend to back up the unencrypted key, as it helps mitigate **potential risks associated with exposing the key visually** and inadvertently writing it into various storage mediums such as video RAM memory, clipboard manager files, and console history files.

128 bytes (1024 bits) may seem excessive, particularly considering that cryptsetup's new default format utilizes only 512 bits. However, it's crucial to acknowledge the potential shortcomings of poor seeding in the random number generator, which may lead to inadequate randomness and compromised security.

If you do not intend to make a paper backup of the key you can make it even larger (256 KiB = 262144 bytes = 2097152 bits):

```bash
dd if=/dev/random bs=256K count=1 of=/mykeys/key123456.dat
```

It's advisable to use a binary key if you do not plan to manually type it in case you lose the USB flash drive. A 256K passphrase cannot be typed manually.

The maximum interactive passphrase length is 512 characters. Therefore, if you want to have the ability to manually type the passphrase at boot time (without using the LUKS keychain scripts), the key must be in ASCII format, no more than 512 characters, with no newline at the end of the file, and in a format that is easy to read and write (such as BIP39 words). Be cautious of the risks associated with backing up the key in cleartext and typing it on a keyboard.

In the examples generated by the `make_crypttab.sh` script, the key path is set to `/mykeys/key.txt`. Therefore, avoid blindly copying these examples and ensure to adjust the paths according to your specific configuration.

Please note that certain text editors may mislead you by inserting a newline character even when they display '1' as the line number, resulting in two lines: one with content and one empty. Upon testing with gedit and mcedit, it was revealed that gedit misrepresents, while mcedit does not. When I save one line with gedit, I get two lines – the second line empty. However, when I save one line with mcedit, I get what I expect – only one line, without a newline character at the end.

Unless you intend to use a version of cryptsetup that handles newlines differently, or you plan to back up the key on paper and type it manually, the discussion about newlines is likely not relevant to you. Nevertheless, for the sake of security and consistency, it's recommended to use key files with only a single line and no trailing newline character.

I read somewhere that cryptsetup does only read the first line of a keyfile and ignores subsequent lines and newline characters. But this is not confirmed.

I tested it, and it reads the .txt file like a binary file. I can't open the container when I modify the file by removing the last line or adding/removing newline characters. This behavior may differ with different versions. I tested with cryptsetup 2.4.3 on my Ubuntu installation. I haven't tested how it will work in the initrd version of cryptsetup (I noticed the initrd version doesn't support ripemd160, so there may be other differences as well).

To simplify typing the key manually, consider creating a more human-readable key. For example, generate 20-30 words using a good random number generator. You can use a password manager or [my scripts](https://github.com/vstoykovbg/doublerandom) for this purpose.

It's preferably to set up the encrypted container in a live system environment (without swap file and without activating the feature for saving the session). Beware that some graphical environments may have clipboard managers saving the clipboard content on the disk and text editors saving backups on the disk.

Be cautious, as some graphical environments may have clipboard managers that save clipboard contents to disk, and text editors may save backups on disk. The key may also leak into the .bash_history file or the history file of the terminal emulator. To reduce the risk of leaking the keys, it's advisable to set up the encrypted container in a live system environment without a swap file and without activating any session-saving features. This ensures that data written in the user's home folder and the /tmp folder is stored only in RAM and not saved in non-volatile memory.

Be aware that the key may be stored not only in the main memory (RAM), but also in the video memory (VRAM) if it is displayed on the screen, making it potentially visible for someone to copy. As a result, a standard memory test like Memtest86+ may not be sufficient to completely wipe the key from memory. However, powering off the computer and removing all power sources for an extended period will ensure that the volatile memory, including both RAM and VRAM, is cleared.

The practice of displaying encryption keys on a monitor and transcribing them manually with a pencil onto paper is subject to debate regarding its effectiveness and security implications.

While this method introduces inherent risks, such as the possibility of human error, there are specialized formats like RFC1751 and BIP39 aimed at facilitating error-free transcription onto paper. These formats offer distinct advantages over directly copying keys from the screen:

1. Error correction: RFC1751 and BIP39 incorporate error-correction mechanisms, such as checksums, to identify and rectify transcription errors, particularly beneficial for lengthy and intricate keys.
2. Human-readable representation: By converting keys into word lists, these formats enhance ease of transcription and memorization compared to random character strings.
3. Offline storage: Paper-based backups enable offline key storage, potentially enhancing security in comparison to online alternatives.

Nevertheless, it's essential to recognize that despite these advantages, paper backups entail significant security considerations:

1. Physical security: Unauthorized access to the paper copy poses a risk of decryption. Implementing robust physical security measures is imperative to mitigate this threat.
2. Loss or damage: Paper backups are susceptible to loss, damage, or destruction. Therefore, maintaining a secure digital backup alongside the paper copy is strongly advised.

Rather than backing up the key directly, consider dividing it into multiple parts using tools such as [Shamir's secret sharing](https://en.wikipedia.org/wiki/Shamir%27s_secret_sharing) ([example implementation](https://github.com/iancoleman/shamir)).

Additionally, mirroring the keychain across multiple USB flash drives, utilizing technologies like btrfs raid1 or raid1c3 mirror, provides redundancy and protects against both data loss and hardware failure.

However, it's crucial to contemplate the consequences if you were to forget the passphrase of the LUKS keychain or lose all USB flash drives from the mirror.

It makes no sense to keep the unencrypted paper backup of the key alongside the encrypted LUKS keychain on a USB flash drive. If you choose to back up the keys on paper in cleartext, ensure they are kept hidden and stored separately from the computer. And definitely not inside the computer case.
