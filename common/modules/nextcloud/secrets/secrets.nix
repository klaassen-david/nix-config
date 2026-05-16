let
  # Your personal SSH key — used to decrypt secrets locally.
  # Replace with the output of: cat ~/.ssh/id_ed25519.pub
  dk = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIReplaceWithYourActualPublicKeydk@workstation";

  # Server host key — copy from the server with:
  #   ssh root@olympus cat /etc/ssh/ssh_host_ed25519_key.pub
  olympus = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIReplaceWithOlympusHostPublicKeyroot@olympus";

  users = [ dk ];
  systems = [ olympus ];
in
{
  "nextcloud-admin-pass.age".publicKeys = users ++ systems;
  "ssl-fullchain.age".publicKeys = users ++ systems;
  "ssl-key.age".publicKeys = users ++ systems;
}
