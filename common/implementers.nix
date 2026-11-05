# Implementer hosts (decisions/implementer-host.md): host name -> wg-easy client
# address. They are not mesh nodes, so the vpn.nodes registry does not list them.
# The hub rule, the vhost deny lines and the fleet's ssh entry derive from this.
# null emits nothing.
{
  hephaestus = "10.100.1.4";
}
