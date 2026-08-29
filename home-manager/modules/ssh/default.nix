# ~/.ssh/config for the fleet. Lives in the base bundle, so olympus gets it too.
#
# Why an explicit IdentityFile is not optional: the shared user key is
# ~/.ssh/id_priv, and `id_priv` is not one of the filenames ssh probes by itself
# (id_rsa, id_ecdsa, id_ed25519, id_dsa, ...). With no block naming it, the
# client offers *no* key at all and falls straight through to the password
# prompt. That reads like a server-side rejection but never reaches sshd as a
# publickey attempt — the giveaway is the *absence* of a "Failed publickey" line
# in `journalctl -u sshd` while a password prompt still appears.
#
# `publickey,password` keeps the fallback deliberately: the desktops' sshd runs
# with PasswordAuthentication = true (common/modules/ssh-on-demand), so a
# password login is the intended way in when the key is unavailable. Drop the
# `,password` per host to make a failed key a hard failure instead.
#
# IdentitiesOnly is not redundant next to IdentityFile: IdentityFile *adds* to
# the candidate list rather than restricting it, and agent keys are tried ahead
# of anything named in the config. Once an agent holds a few keys, sshd's default
# MaxAuthTries of 6 can be spent before id_priv is ever offered, and the client
# reports the useless "Too many authentication failures". No agent is configured
# in this flake today, so this is insurance for the day one appears.
#
# Both the bare and the .local name are listed for each desktop because `Host`
# patterns match the string typed on the command line, not the resolved host —
# `ssh hestia` and `ssh hestia.local` are two different match subjects. (Bare
# names resolve over LLMNR, .local over mDNS; see common/desktop.nix.)
#
# Escape hatch for temporary/ad-hoc edits: the generated file is a read-only
# store symlink, so ~/.ssh/config.d/*.conf is pulled in for anything that should
# not be committed (a one-off ProxyJump, a colleague's box, a port forward while
# debugging). The Include is emitted *above* the managed blocks and ssh is
# first-match-wins per keyword, so a drop-in both adds new hosts and overrides
# directives on existing ones, while inheriting whatever it does not set. The
# directory need not exist — ssh ignores an include that matches nothing.
#
# Taking over the file: home-manager owns ~/.ssh/config from here on. The flake
# sets backupFileExtension, so a pre-existing hand-written config is moved to
# ~/.ssh/config.home-manager.bak on the first switch instead of failing
# activation. The github/tukl blocks are carried over from that file — they are
# not new, they just have to live here now or they would be dropped.

{ ... }:

{
  programs.ssh = {
    enable = true;

    # drop-in overrides, see the note above; relative paths are resolved
    # against ~/.ssh by ssh itself
    includes = [ "config.local" ];

    # the implicit `Host *` block only restates upstream ssh defaults, and
    # leaving it on emits a deprecation warning on every build
    enableDefaultConfig = false;

    settings = {
      "dklaassen.de hestia hestia.local hermes hermes.local" = {
        PreferredAuthentications = "publickey,password";
        IdentityFile = "~/.ssh/id_priv";
        IdentitiesOnly = true;
      };

      "github.com" = {
        PreferredAuthentications = "publickey";
        IdentityFile = "~/.ssh/id_github";
        IdentitiesOnly = true;
      };

      "softech-git.informatik.uni-kl.de" = {
        PreferredAuthentications = "publickey";
        IdentityFile = "~/.ssh/tukl";
        IdentitiesOnly = true;
      };
    };
  };
}
