let
  priv = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFezQKjTnD8MFIlnHubglFUJ1ePb9pLdzTCoIQoXn3F3 dk@hestia";
  # PLACEHOLDER (user, at install): the public half of the host key generated for
  # nixos-anywhere's --extra-files. age refuses this value, so encrypting fails
  # loudly until it is filled in.
  hephaestus = "ssh-ed25519 PLACEHOLDER-hephaestus-public-host-key root@hephaestus";
  files = [
    "ssl-fullchain.age"
    "ssl-key.age"
    "acme-env.age"
    "stalwart-admin-pass.age"
    "stalwart-dk-pass.age"
    "stalwart-nextcloud-pass.age"
    "stalwart-dkim-rsa.age"
    "nextcloud-admin-pass.age"
    "nextcloud-general.age"
    "nextcloud-cmd.age"
    "oauth2-client-secret.age"
    "oauth2-cookie-secret.age"
    "atticd-env.age"
    "attic-token.age"
    "attic-netrc.age"
    "wg-olympus.age"
    "wg-hermes.age"
    "wg-hestia.age"
    "wg-tukl-hermes.age"
    "wg-tukl-hestia.age"
    "smb-dk.age"
    "restic-repo-pass.age"
    "orch-proxy-key.age"
    "wg-fleet-hephaestus.age"
  ];
  # hephaestus never holds id_priv (decisions/implementer-host.md)
  extraRecipients."wg-fleet-hephaestus.age" = [ hephaestus ];
in
builtins.listToAttrs (
  map (f: {
    name = f;
    value.publicKeys = [ priv ] ++ (extraRecipients.${f} or [ ]);
  }) files
)
