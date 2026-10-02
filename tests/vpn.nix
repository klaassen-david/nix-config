# VM test of the wireguard mesh (common/modules/wireguard) on a small fake
# internet. Topology, addressing and the test-only registry are below; add
# nodes to `nodes` and subtests to `testScript` as the design grows.
#
#   vlan 1 "internet" 203.0.113.0/24: internet .1 (+ 198.51.100.1/32 with a
#       web server echoing the client address), olympus .10 (hub, uplink eth1),
#       homerouter .20 (WAN side), hermes .30, phone .40 (wg-easy client)
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
    # olympus's wg0 (stands in for wg-easy) and the phone behind it
    wg0 = {
      private = "YArkoxRJvhzZVd/NikWOwfKPrGVxG6QsqyNOjuCkW3o=";
      public = "kBVlb7b+x1pmOapkLhYfrAEYCVrfzAfnzcTOku5vGCQ=";
    };
    phone = {
      private = "gOgzsSpI6t4e/zRuvcKKuQBpXo/ZV6/+OB1NiW/gPmE=";
      public = "7W/c7L+NAPHXcm0Sat6vpfcV1rhA/dMe3d2qcq/IKDc=";
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
      environment.systemPackages = [
        pkgs.conntrack-tools
        pkgs.nftables
      ];
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

  # wg-easy stand-in on olympus: plain wg0 plus the slice of its sqlite db that
  # vpn-phone reads.
  phone6 = "fdcc:ad94:bacf:61a4::cafe";
  wgEasyStandIn =
    { pkgs, ... }:
    {
      networking.wireguard.interfaces.wg0 = {
        ips = [
          "10.100.1.1/24"
          "${phone6}:1/112"
        ];
        listenPort = 51821;
        privateKey = keys.wg0.private;
        peers = [
          {
            publicKey = keys.phone.public;
            allowedIPs = [
              "10.100.1.2/32"
              "${phone6}:2/128"
            ];
          }
        ];
      };
      environment.systemPackages = [ pkgs.sqlite ];
      networking.nat.internalInterfaces = [ "wg0" ];
      networking.firewall.allowedUDPPorts = [ 51821 ];

      systemd.services.wg-easy-db = {
        wantedBy = [ "multi-user.target" ];
        before = [
          "vpn-hub-nft.service"
          "vpn-phones.service"
        ];
        path = [ pkgs.sqlite ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          mkdir -p /var/lib/wg-easy
          # WAL like wg-easy's own db
          sqlite3 /var/lib/wg-easy/wg-easy.db "
            PRAGMA journal_mode = wal;
            CREATE TABLE clients_table (public_key text, ipv4_address text, ipv6_address text,
                                        name text, enabled integer, interface_id text);
            INSERT INTO clients_table VALUES
              ('${keys.phone.public}', '10.100.1.2', '${phone6}:2', 'phone1', 1, 'wg0');"
        '';
      };
    };
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
      extra = wgEasyStandIn;
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

    phone =
      { ... }:
      {
        virtualisation.vlans = [ 1 ];
        networking.useDHCP = lib.mkForce false;
        networking.interfaces.eth1 = {
          ipv4.addresses = lib.mkForce [ (addr "203.0.113.40" 24) ];
          ipv6.addresses = lib.mkForce [ ];
        };
        networking.defaultGateway = lib.mkForce {
          address = "203.0.113.1";
          interface = "eth1";
        };
        networking.firewall.checkReversePath = false;
        networking.wg-quick.interfaces.wg0 = {
          address = [
            "10.100.1.2/32"
            "${phone6}:2/128"
          ];
          privateKey = keys.phone.private;
          peers = [
            {
              publicKey = keys.wg0.public;
              endpoint = "203.0.113.10:51821";
              allowedIPs = [
                "0.0.0.0/0"
                "::/0"
              ];
              persistentKeepalive = 25;
            }
          ];
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
    import json

    start_all()

    hosts = [hermes, hestia]
    for m in [internet, homerouter, olympus, phone] + hosts:
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

    with subtest("egress via hestia: exits from hestia's home NAT, refuses its LAN"):
        hermes.succeed("systemctl start vpn-egress-hestia.service")
        out = hermes.succeed(curl).strip()
        assert out == "203.0.113.20", f"expected egress via hestia, got {out!r}"
        hermes.fail("ping -c1 -W2 192.168.178.2")
        hermes.succeed("systemctl start vpn-egress-olympus.service")
        hermes.fail("systemctl is-active vpn-egress-hestia.service")
        out = hermes.succeed(curl).strip()
        assert out == "203.0.113.10", f"expected egress via olympus, got {out!r}"
        hermes.succeed("systemctl stop vpn-egress-olympus.service")
        hermes.fail("ip addr show dev olympus | grep 10.100.12.3")

    with subtest("egress via hermes: hestia exits from hermes"):
        hestia.succeed("systemctl start vpn-egress-hermes.service")
        out = hestia.succeed(curl).strip()
        assert out == "203.0.113.30", f"expected egress via hermes, got {out!r}"
        hestia.succeed("systemctl stop vpn-egress-hermes.service")

    with subtest("exit offline: traffic is dropped, never sent from another exit"):
        watch = "vpn-egress-watch@vpn-egress-hestia.service"
        hermes.succeed("systemctl start vpn-egress-hestia.service")
        hermes.succeed(curl)
        hestia.succeed("systemctl stop wireguard-olympus.service")
        out = hermes.execute(curl)[1].strip()
        assert out == "", f"expected a dropped connection, got {out!r}"
        hermes.wait_until_succeeds(f"journalctl -u '{watch}' | grep 'traffic is dropped'", timeout=120)
        hestia.succeed("systemctl start wireguard-olympus.service")
        hermes.wait_until_succeeds(f"{curl} | grep -x 203.0.113.20", timeout=120)
        hermes.succeed("systemctl stop vpn-egress-hestia.service")
        out = hermes.succeed(curl).strip()
        assert out == "203.0.113.30", f"expected direct egress, got {out!r}"

    # Run as root: the polkit rule that lets dk flip these units is not imported here.
    # Read-only `vpn status` is also checked as dk.
    with subtest("vpn wrapper: switching, status, exclusivity"):
        egress_units = ["olympus", "hestia"]

        def check_exclusive(m, expect):
            active = [
                u for u in egress_units
                if m.execute(f"systemctl is-active --quiet vpn-egress-{u}.service")[0] == 0
            ]
            assert active == expect, f"active egress units {active}, expected {expect}"
            for fam in ["-4", "-6"]:
                n = int(m.succeed(f"ip {fam} rule show pref 5300 | wc -l").strip())
                assert n == len(expect), f"{n} pref-5300 rules in {fam}, expected {len(expect)}"

        def short(m):
            return m.succeed("vpn status --short").strip()

        hermes.succeed("vpn egress hestia")
        out = hermes.succeed(curl).strip()
        assert out == "203.0.113.20", f"expected egress via hestia, got {out!r}"
        assert short(hermes) == "hestia", short(hermes)
        assert hermes.succeed("su - dk -c 'vpn status --short'").strip() == "hestia"
        status = json.loads(hermes.succeed("vpn status --json"))
        assert status == {"text": "hestia", "state": "Info"}, status
        assert "exit: hestia" in hermes.succeed("vpn status")
        check_exclusive(hermes, ["hestia"])

        hermes.succeed("vpn egress olympus")
        out = hermes.succeed(curl).strip()
        assert out == "203.0.113.10", f"expected egress via olympus, got {out!r}"
        assert short(hermes) == "olympus", short(hermes)
        check_exclusive(hermes, ["olympus"])

        hermes.succeed("vpn egress direct")
        out = hermes.succeed(curl).strip()
        assert out == "203.0.113.30", f"expected direct egress, got {out!r}"
        assert short(hermes) == "direct", short(hermes)
        status = json.loads(hermes.succeed("vpn status --json"))
        assert status == {"text": "direct", "state": "Idle"}, status
        check_exclusive(hermes, [])

        hermes.fail("vpn egress nowhere")
        hermes.fail("vpn home on")  # no vpn-home.service yet
        hermes.succeed("vpn mesh off")
        hermes.fail("ping -c1 -W2 10.100.0.1")
        assert "mesh: down" in hermes.succeed("vpn status")
        hermes.succeed("vpn mesh on")
        hermes.wait_until_succeeds("ping -c1 -W2 10.100.0.1")
        assert "mesh: up" in hermes.succeed("vpn status")

    with subtest("vpn wrapper: kernel state without a unit is inconsistent"):
        hermes.succeed("ip rule add pref 5300 lookup 2100")
        rc, out = hermes.execute("vpn status --short")
        assert rc == 1 and out.strip() == "inconsistent", (rc, out)
        assert json.loads(hermes.succeed("vpn status --json")) == {"text": "inconsistent", "state": "Critical"}
        hermes.succeed("ip rule del pref 5300")
        assert short(hermes) == "direct", short(hermes)

        # a tukl link outside wg-quick-tukl: flagged, and the egress units refuse to start
        hermes.succeed("ip link add tukl type dummy")
        rc, out = hermes.execute("vpn status --short")
        assert rc == 1 and out.strip() == "inconsistent", (rc, out)
        hermes.fail("vpn egress olympus")
        hermes.fail("ip rule show pref 5300 | grep .")
        hermes.succeed("ip link del tukl")
        hermes.succeed("systemctl reset-failed vpn-egress-olympus.service")
        assert short(hermes) == "direct", short(hermes)

    with subtest("vpn wrapper: a dead exit shows as !down"):
        hermes.succeed("vpn egress hestia")
        hestia.succeed("systemctl stop wireguard-olympus.service")
        hermes.wait_until_succeeds('test "$(vpn status --short)" = "hestia !down"', timeout=120)
        status = json.loads(hermes.succeed("vpn status --json"))
        assert status == {"text": "hestia !down", "state": "Critical"}, status
        hestia.succeed("systemctl start wireguard-olympus.service")
        hermes.wait_until_succeeds('test "$(vpn status --short)" = hestia', timeout=120)
        hermes.succeed("vpn egress direct")
        hermes.fail("ls /run/vpn-egress-watch/*.down")
        check_exclusive(hermes, [])

    with subtest("phone: exits via olympus by default, sees no mesh host"):
        olympus.wait_for_unit("vpn-hub-nft.service")
        phone.wait_for_unit("wg-quick-wg0.service")
        phone.wait_until_succeeds("ping -c1 -W2 10.100.1.1")
        out = phone.succeed(curl).strip()
        assert out == "203.0.113.10", f"expected phone egress via olympus, got {out!r}"
        phone.fail("ping -c1 -W2 10.100.0.2")

    with subtest("phone: hosts on/off gates the mesh hosts"):
        olympus.succeed("vpn-phone phone1 hosts on")
        phone.wait_until_succeeds("ping -c1 -W2 10.100.0.2")
        olympus.succeed("vpn-phone phone1 hosts off")
        phone.wait_until_fails("ping -c1 -W2 10.100.0.2")
        phone.fail("ping -c1 -W2 192.168.178.2")

    with subtest("phone: egress via hestia and hermes"):
        olympus.succeed("vpn-phone phone1 egress hestia")
        out = phone.succeed(curl).strip()
        assert out == "203.0.113.20", f"expected phone egress via hestia, got {out!r}"
        olympus.succeed("vpn-phone phone1 egress hermes")
        out = phone.succeed(curl).strip()
        assert out == "203.0.113.30", f"expected phone egress via hermes, got {out!r}"

    with subtest("phone: a dead exit drops the traffic, never falls back to olympus"):
        hermes.succeed("systemctl stop wireguard-olympus.service")
        out = phone.execute(curl)[1].strip()
        assert out == "", f"expected a dropped connection, got {out!r}"
        hermes.succeed("systemctl start wireguard-olympus.service")
        phone.wait_until_succeeds(f"{curl} | grep -x 203.0.113.30", timeout=60)

    with subtest("phone: reloading the hub keeps the phone rules"):
        olympus.succeed("systemctl restart vpn-hub-nft.service")
        out = phone.succeed(curl).strip()
        assert out == "203.0.113.30", f"expected phone egress via hermes, got {out!r}"

    with subtest("phone: list, then back to olympus"):
        listing = olympus.succeed("vpn-phone list")
        assert "phone1" in listing and "hermes" in listing, listing
        olympus.succeed("vpn-phone phone1 egress olympus")
        out = phone.succeed(curl).strip()
        assert out == "203.0.113.10", f"expected phone egress via olympus, got {out!r}"
        olympus.fail("ip rule show | grep 3500")

    with subtest("phone: db changes re-apply, reading the db does not retrigger"):
        olympus.succeed("vpn-phone phone1 egress hestia")
        olympus.succeed("ip rule show | grep 3500")
        olympus.succeed("sqlite3 /var/lib/wg-easy/wg-easy.db \"UPDATE clients_table SET enabled = 0\"")
        olympus.wait_until_fails("ip rule show | grep 3500")
        olympus.succeed("sqlite3 /var/lib/wg-easy/wg-easy.db \"UPDATE clients_table SET enabled = 1\"")
        olympus.wait_until_succeeds("ip rule show | grep 3500")
        olympus.succeed("vpn-phone phone1 egress olympus")
        olympus.sleep(3)
        n = olympus.succeed("journalctl -u vpn-phones.service -o cat | grep -c 'db changed'").strip()
        for _ in range(3):
            olympus.succeed("vpn-phone list")
        olympus.sleep(10)
        m = olympus.succeed("journalctl -u vpn-phones.service -o cat | grep -c 'db changed'").strip()
        assert n == m, f"vpn-phones keeps re-running: {n} -> {m}"
        olympus.succeed("systemctl is-active vpn-phones.service")
  '';
}
