let
  priv = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFezQKjTnD8MFIlnHubglFUJ1ePb9pLdzTCoIQoXn3F3 dk@hestia";
  olympus = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICC2ITqo7NHmJIn8Cgd3O5ezGJAmLSE/Srlq9l8Ix9io root@olympus";

  users = [ priv ];
  systems = [ olympus ];
  all = users ++ systems;
in
{
  "nextcloud-admin-pass.age".publicKeys = all;
  "ssl-fullchain.age".publicKeys = all;
  "ssl-key.age".publicKeys = all;
  "stalwart-admin-pass.age".publicKeys = all;
  "stalwart-dk-pass.age".publicKeys = all;
  "stalwart-nextcloud-pass.age".publicKeys = all;
  "nextcloud-general.age".publicKeys = all;
  "oauth2-client-secret.age".publicKeys = all;
  "oauth2-cookie-secret.age".publicKeys = all;
}
