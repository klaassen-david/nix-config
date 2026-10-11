# Where each hot-swapped app runs: the single source for the app modules (on
# `node`) and for olympus's vhosts (./vhosts.nix), which cannot read another
# host's config. Plain data, not a module. decisions/hot-swap.md.
{
  orchestrator = {
    node = "hestia";
    port = 3040;
  };
  coordinator = {
    node = "hestia";
    port = 7300;
  };
}
