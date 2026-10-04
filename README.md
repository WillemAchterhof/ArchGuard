# ArchGuard v0.1

## Goal

A bootable USB that works with the ArchGuard custom Secure Boot keys.

If the keys are already enrolled in UEFI, the USB boots normally.

If they are not:

1. Enter UEFI and put Secure Boot into Setup Mode.
2. Boot the ArchGuard USB.
3. ArchGuard detects Setup Mode and enrolls the custom PK, KEK and db keys.
4. ArchGuard reboots back into UEFI.
5. Configure and lock down UEFI as desired, keeping TPM PCR measurements in mind.
6. Enable Secure Boot and boot the ArchGuard USB again.

**v0.1 is only concerned with establishing the Secure Boot trust chain.**
