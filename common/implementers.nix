# Implementer hosts (decisions/implementer-host.md): host name -> wg-easy client
# address. They are not mesh nodes, so the vpn.nodes registry does not list them.
# The hub rule, the vhost deny lines and the fleet's ssh entry derive from this.
# null emits nothing, so the file changes no host until an address is filled in.
{
  # PLACEHOLDER (user, when adding the wg-easy client at vpn.dklaassen.de):
  # the client's address, "10.100.1.X".
  hephaestus = null;
}
