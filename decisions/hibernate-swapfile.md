# Hibernation swapfile

**Ruling** [USER 2026-09-30]: hermes hibernates into a 32 GiB swapfile on `/`,
enabling `suspend-then-hibernate` on lid close.

**Docked** [USER 2026-09-30]: lid close with an external display connected
triggers neither suspend nor suspend-then-hibernate. `lid-suspend-delay`
(`common/modules/wifi/default.nix`) already exits on any connected non-eDP
connector before its final `systemctl` call, so swapping that call keeps this.

**Why** [AGENT 2026-09-26]: the swap partition (`nvme0n1p3`, 8.8 GiB) is
smaller than RAM (30.7 GiB) and than the kernel's 12.2 GiB `image_size` target,
so an image does not reliably fit; `/` is ext4 with 810 GiB free.

**Rejected**: repartitioning to grow the swap partition; a swapfile sized to
`image_size` only (fails exactly when memory is fullest).

**Revisit if**: `/` gets tight on space, or `/` moves to a filesystem where a
swapfile's `resume_offset` is not stable (e.g. btrfs without a nocow file).
