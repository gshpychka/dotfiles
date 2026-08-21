# parted /dev/sdc --script mklabel gpt mkart primary 0% 100%
# cryptsetup luksFormat --type luks2 --cipher aes-xts-plain64 --key-size 512 --sector-size 4096 /dev/sdc1
# cryptsetup config --label="hoard-alpha-enc" /dev/sdc1
# systemd-cryptenroll --tpm2-device=auto /dev/sdc1
# cryptsetup luksOpen /dev/sdc1 hoard-alpha
{
  # The volumes the hoard btrfs filesystem spans.
  arrayMembers = {
    hoard-alpha = "/dev/disk/by-label/hoard-alpha-enc";
    hoard-beta = "/dev/disk/by-label/hoard-beta-enc";
  };
}
