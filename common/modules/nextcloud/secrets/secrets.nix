let
  dk = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFezQKjTnD8MFIlnHubglFUJ1ePb9pLdzTCoIQoXn3F3 dk@hestia";
  olympus = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICC2ITqo7NHmJIn8Cgd3O5ezGJAmLSE/Srlq9l8Ix9io root@olympus";

  users = [ dk ];
  systems = [ olympus ];
in
{
  "nextcloud-admin-pass.age".publicKeys = users ++ systems;
  "ssl-fullchain.age".publicKeys = users ++ systems;
  "ssl-key.age".publicKeys = users ++ systems;
}
