## Prerequisites

### Windows 11 (WSL)

Install WSL with an Arch Linux distribution. Use **Arch Linux**.

### Linux (WSL)

Open your Arch Linux terminal and install `sbctl`. Generate your Secure Boot keys if you haven't already.

Next, download and run the ArchGuard USB builder script:

```bash
curl -fsSLO https://raw.githubusercontent.com/WillemAchterhof/archguard-usb-builder/refs/heads/v0.1/create_archguard_usb.sh
chmod +x create_archguard_usb.sh
./create_archguard_usb.sh
```

### UEFI Configuration

Before booting from the USB, enter your UEFI firmware settings and make sure that:

- USB boot is enabled.
- Secure Boot is in **Setup Mode**.

### Important

Keep your Secure Boot private keys safe. The builder uses your existing `sbctl` keys to sign the ArchGuard ISO.
