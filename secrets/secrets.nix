let
  priv = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFezQKjTnD8MFIlnHubglFUJ1ePb9pLdzTCoIQoXn3F3 dk@hestia";
  files = [
    "ssl-fullchain.age"
    "ssl-key.age"
    "stalwart-admin-pass.age"
    "stalwart-dk-pass.age"
    "stalwart-nextcloud-pass.age"
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
    "wg-tukl.age"
    "smb-dk.age"
  ];
in
builtins.listToAttrs (
  map (f: {
    name = f;
    value.publicKeys = [ priv ];
  }) files
)
