# VM test of the wireguard mesh (common/modules/wireguard) on a small fake
# internet. Topology, addressing and the test-only registry are below; add
# nodes to `nodes` and subtests to `testScript` as the design grows.
#
#   vlan 1 "internet" 203.0.113.0/24: internet .1 (+ 198.51.100.1/32 with a
#       web server echoing the client address), olympus .10 (hub, uplink eth1),
#       homerouter .20 (WAN side), hermes .30
#   vlan 2 "home" 192.168.178.0/24: homerouter .2 (NAT), hestia .32
{ pkgs, inputs }:

let
  inherit (pkgs) lib;

  # Throwaway keypairs, generated for this test only. Never used anywhere else.
  keys = {
    olympus = {
      private = "SBlkPsbmSNHabdcM+A0BmD8kZgn15G4E7PcmH31eN1U=";
      public = "0OeIxoPrEfum6h97Nm5Ia+9Wd6NTQKwSYv6oUpN5blU=";
    };
    hestia = {
      private = "WKYpQa1uaUP0lPTXsT6Z3tcSrZN2/U8bRRQ398yWK0w=";
      public = "gAVpZ+y9HY3lcx5sqke7kWy/blIdndibXZT1WyQJSjY=";
    };
    hermes = {
      private = "ADSmw32e6DfDiEIY1YkpR8N9sJY8T9d63ugCSNgycUs=";
      public = "dxcyErYkUyyxcXz0/iNnrSGwkCeZpVWmZB4IO0NeUy8=";
    };
  };

  # Same octets/flags/lan as production, test keys, no tukl.
  registry = {
    olympus = {
      octet = 1;
      publicKey = keys.olympus.public;
      hub = true;
    };
    hestia = {
      octet = 2;
      publicKey = keys.hestia.public;
      exit = true;
      lan = "192.168.178.0/24";
    };
    hermes = {
      octet = 3;
      publicKey = keys.hermes.public;
      exit = true;
    };
  };

  # Stand-in for common/host.nix (which drags in home-manager).
  hostStub =
    { lib, ... }:
    {
      options.host = {
        hostName = lib.mkOption { type = lib.types.str; };
        role = lib.mkOption { type = lib.types.str; };
        userManagedUnits = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
      };
    };

  # A mesh member: wireguard module, test keys, static addressing.
  meshNode =
    name:
    {
      role,
      vlans,
      addresses,
      gateway ? null,
      extra ? { },
    }:
    {
      imports = [
        ../common/modules/wireguard
        inputs.agenix.nixosModules.default
        hostStub
        extra
      ];
      _module.args.secretsPath = ../secrets;

      host = {
        hostName = name;
        inherit role;
      };
      age.secrets = lib.mkForce { };
      vpn = {
        nodes = lib.mkForce registry;
        endpoint = "203.0.113.10:51820";
        uplink = "eth1";
        probe = "198.51.100.1";
        privateKeyFile = "/etc/vpn-test.key";
      };
      environment.etc."vpn-test.key" = {
        text = keys.${name}.private;
        mode = "0400";
      };

      # config.local is installed into ~dk/.ssh
      users.users.dk.isNormalUser = true;
      systemd.tmpfiles.rules = [ "d /home/dk/.ssh 0700 dk users -" ];

      virtualisation.vlans = vlans;
      networking.useDHCP = lib.mkForce false;
      networking.firewall.checkReversePath = role == "vps";
      networking.interfaces = lib.mapAttrs (_: addrs: {
        ipv4.addresses = lib.mkForce addrs;
        ipv6.addresses = lib.mkForce [ ];
      }) addresses;
      networking.defaultGateway = lib.mkIf (gateway != null) (
        lib.mkForce { inherit (gateway) address interface; }
      );
    };

  addr = address: prefixLength: { inherit address prefixLength; };
in
pkgs.testers.runNixOSTest {
  name = "vpn";
  node.specialArgs = { inherit inputs; };

  nodes = {
    internet =
      { ... }:
      {
        virtualisation.vlans = [ 1 ];
        networking.useDHCP = lib.mkForce false;
        networking.interfaces.eth1 = {
          ipv4.addresses = lib.mkForce [
            (addr "203.0.113.1" 24)
            (addr "198.51.100.1" 32)
          ];
          ipv6.addresses = lib.mkForce [ ];
        };
        # answers with the address it sees the client at
        services.nginx = {
          enable = true;
          virtualHosts.default = {
            default = true;
            locations."/".return = ''200 "$remote_addr\n"'';
          };
        };
        networking.firewall.allowedTCPPorts = [ 80 ];
      };

    homerouter =
      { ... }:
      {
        virtualisation.vlans = [
          1
          2
        ];
        networking.useDHCP = lib.mkForce false;
        networking.interfaces = {
          eth1 = {
            ipv4.addresses = lib.mkForce [ (addr "203.0.113.20" 24) ];
            ipv6.addresses = lib.mkForce [ ];
          };
          eth2 = {
            ipv4.addresses = lib.mkForce [ (addr "192.168.178.2" 24) ];
            ipv6.addresses = lib.mkForce [ ];
          };
        };
        networking.defaultGateway = lib.mkForce {
          address = "203.0.113.1";
          interface = "eth1";
        };
        networking.nat = {
          enable = true;
          externalInterface = "eth1";
          internalInterfaces = [ "eth2" ];
        };
      };

    olympus = meshNode "olympus" {
      role = "vps";
      vlans = [ 1 ];
      addresses.eth1 = [ (addr "203.0.113.10" 24) ];
      gateway = {
        address = "203.0.113.1";
        interface = "eth1";
      };
    };

    hestia = meshNode "hestia" {
      role = "tower";
      vlans = [ 2 ];
      addresses.eth1 = [ (addr "192.168.178.32" 24) ];
      gateway = {
        address = "192.168.178.2";
        interface = "eth1";
      };
    };

    hermes = meshNode "hermes" {
      role = "laptop";
      vlans = [ 1 ];
      addresses.eth1 = [ (addr "203.0.113.30" 24) ];
      gateway = {
        address = "203.0.113.1";
        interface = "eth1";
      };
    };
  };

  testScript = ''
    start_all()

    hosts = [hermes, hestia]
    for m in [internet, homerouter, olympus] + hosts:
        m.wait_for_unit("multi-user.target")
    internet.wait_for_unit("nginx.service")

    ips4 = {"olympus": "10.100.0.1", "hestia": "10.100.0.2", "hermes": "10.100.0.3"}
    ips6 = {"olympus": "fdaa:e184:83f::1", "hestia": "fdaa:e184:83f::2", "hermes": "fdaa:e184:83f::3"}
    mesh = {"olympus": olympus, "hestia": hestia, "hermes": hermes}

    with subtest("mesh: every node reaches every other, v4 and v6"):
        for m in hosts:
            m.wait_for_unit("wireguard-olympus.service")
        for src, m in mesh.items():
            for dst in mesh:
                if src == dst:
                    continue
                m.wait_until_succeeds(f"ping -c1 -W2 {ips4[dst]}")
                m.wait_until_succeeds(f"ping -6 -c1 -W2 {ips6[dst]}")

    with subtest("hermes goes out directly"):
        out = hermes.succeed("curl -s --max-time 5 http://198.51.100.1/").strip()
        assert out == "203.0.113.30", f"expected direct egress, got {out!r}"

    with subtest("ssh config.local follows the mesh interface"):
        hermes.succeed("test -e /home/dk/.ssh/config.local")
        hermes.succeed("grep -A1 '^Host hestia' /home/dk/.ssh/config.local | grep 10.100.0.2")
        hermes.succeed("systemctl stop wireguard-olympus.service")
        hermes.fail("ping -c1 -W2 10.100.0.1")
        hermes.fail("test -e /home/dk/.ssh/config.local")
        hermes.fail("ip rule show | grep 5000")
        hermes.succeed("systemctl start wireguard-olympus.service")
        hermes.wait_until_succeeds("ping -c1 -W2 10.100.0.1")
        hermes.succeed("test -e /home/dk/.ssh/config.local")
        hermes.succeed("ip rule show | grep 5000")
        hermes.wait_until_succeeds("ping -6 -c1 -W2 fdaa:e184:83f::1")

    curl = "curl -s --max-time 5 http://198.51.100.1/"

    with subtest("egress via olympus: hermes exits from the hub, stop goes direct"):
        hermes.succeed("systemctl start vpn-egress-olympus.service")
        out = hermes.succeed(curl).strip()
        assert out == "203.0.113.10", f"expected egress via olympus, got {out!r}"
        hermes.succeed("ip rule show | grep 5200")
        hermes.succeed("ip rule show | grep 5300")
        hermes.succeed("ping -c1 -W2 10.100.0.2")
        hermes.succeed("ping -6 -c1 -W2 fdaa:e184:83f::1")
        hermes.succeed("systemctl stop vpn-egress-olympus.service")
        out = hermes.succeed(curl).strip()
        assert out == "203.0.113.30", f"expected direct egress, got {out!r}"
        hermes.fail("ip rule show | grep -E '^(5200|5300):'")
        hermes.fail("ip -6 rule show | grep -E '^(5200|5300):'")

    with subtest("egress is bound to the mesh"):
        hermes.succeed("systemctl start vpn-egress-olympus.service")
        hermes.succeed("systemctl stop wireguard-olympus.service")
        hermes.fail("systemctl is-active vpn-egress-olympus.service")
        out = hermes.succeed(curl).strip()
        assert out == "203.0.113.30", f"expected direct egress, got {out!r}"
        hermes.succeed("systemctl start vpn-egress-olympus.service")
        hermes.succeed("systemctl is-active wireguard-olympus.service")
        hermes.wait_until_succeeds("ping -c1 -W2 10.100.0.1")
        out = hermes.succeed(curl).strip()
        assert out == "203.0.113.10", f"expected egress via olympus, got {out!r}"

    with subtest("watcher: a dead exit drops traffic, never falls back to direct"):
        watch = "vpn-egress-watch@vpn-egress-olympus.service"
        hermes.wait_for_unit(watch)
        olympus.succeed("iptables -I FORWARD -i olympus -j DROP")
        hermes.wait_until_succeeds(f"journalctl -u '{watch}' | grep 'traffic is dropped'", timeout=120)
        hermes.fail(curl)
        olympus.succeed("iptables -D FORWARD -i olympus -j DROP")
        hermes.wait_until_succeeds(f"journalctl -u '{watch}' | grep 'reachable again'", timeout=120)
        out = hermes.succeed(curl).strip()
        assert out == "203.0.113.10", f"expected egress via olympus, got {out!r}"
        hermes.succeed("systemctl stop vpn-egress-olympus.service")
  '';
}
