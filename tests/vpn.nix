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
        pkgs.tcpdump
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

  # common/modules/ssh-server on the desktop hosts, with its capability option
  # (the real one lives in common/host.nix)
  sshServer =
    { lib, ... }:
    {
      imports = [ ../common/modules/ssh-server ];
      config.environment.systemPackages = [ pkgs.netcat ];
      options.host.capabilities.sshServer = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
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
              ('${keys.phone.public}', '10.100.1.2', '${phone6}:2', 'phone1', 1, 'wg0');
            CREATE TABLE hooks_table (id text, pre_up text, post_up text, pre_down text, post_down text);
            INSERT INTO hooks_table (id) VALUES ('wg0');"
        '';
      };
      # stands in for the container, to see the watcher restart it
      systemd.services.podman-wg-easy = {
        wantedBy = [ "multi-user.target" ];
        serviceConfig.ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
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
        environment.systemPackages = [ pkgs.netcat ];
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
        environment.systemPackages = [ pkgs.netcat ];
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
      extra = sshServer;
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
      extra = sshServer;
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

    with subtest("egress survives a mesh stop: traffic is dropped, then returns"):
        hermes.succeed("systemctl start vpn-egress-olympus.service")
        hermes.succeed("systemctl stop wireguard-olympus.service")
        hermes.succeed("systemctl is-active vpn-egress-olympus.service")
        out = hermes.execute(curl)[1].strip()
        assert out == "", f"expected a dropped connection, got {out!r}"
        hermes.succeed("systemctl start wireguard-olympus.service")
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
        hermes.succeed("vpn home on")
        assert short(hermes) == "direct +home", short(hermes)
        hermes.succeed("vpn home off")
        assert short(hermes) == "direct", short(hermes)
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
    home = "192.168.178.2"

    with subtest("home switch: hermes reaches the LAN only while vpn-home is on"):
        hermes.fail(f"ping -c1 -W2 {home}")
        hermes.succeed("systemctl start vpn-home.service")
        hermes.wait_until_succeeds(f"ping -c1 -W2 {home}")
        hermes.succeed("systemctl start vpn-egress-olympus.service")
        hermes.succeed(f"ping -c1 -W2 {home}")
        out = hermes.succeed(curl).strip()
        assert out == "203.0.113.10", f"expected egress via olympus, got {out!r}"
        hermes.succeed("systemctl stop vpn-egress-olympus.service")
        hermes.succeed("systemctl stop vpn-home.service")
        hermes.fail(f"ping -c1 -W2 {home}")
        hermes.fail("ip rule show | grep 5100")

    with subtest("home switch: stopping the mesh stops vpn-home"):
        hermes.succeed("systemctl start vpn-home.service")
        hermes.succeed("systemctl stop wireguard-olympus.service")
        hermes.fail("systemctl is-active vpn-home.service")
        hermes.succeed("systemctl start wireguard-olympus.service")
        hermes.wait_until_succeeds("ping -c1 -W2 10.100.0.1")
        hermes.fail(f"ping -c1 -W2 {home}")

    with subtest("home switch: an exit's traffic never reaches the LAN"):
        hermes.succeed("systemctl start vpn-egress-hestia.service")
        hermes.fail(f"ping -c1 -W2 {home}")
        hermes.succeed("systemctl stop vpn-egress-hestia.service")

    with subtest("home switch: olympus reaches the LAN only while vpn-home is on"):
        olympus.fail(f"ping -c1 -W2 {home}")
        olympus.succeed("systemctl start vpn-home.service")
        olympus.wait_until_succeeds(f"ping -c1 -W2 {home}")
        olympus.succeed("systemctl stop vpn-home.service")
        olympus.fail(f"ping -c1 -W2 {home}")

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

    with subtest("phone: home on/off gates the home LAN"):
        phone.fail(f"ping -c1 -W2 {home}")
        olympus.succeed("vpn-phone phone1 home on")
        phone.wait_until_succeeds(f"ping -c1 -W2 {home}")
        olympus.succeed("vpn-phone phone1 home off")
        phone.wait_until_fails(f"ping -c1 -W2 {home}")

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
        olympus.succeed("systemctl reload vpn-hub-nft.service")
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

    # What hestia sends out of eth1 (-Q out) while homerouter probes it, with
    # the arrival at hestia (-Q in) as the control that the probe got there.
    def probe_router(src_ip):
        hestia.succeed("rm -f /tmp/in.cap /tmp/out.cap")
        for d in ["in", "out"]:
            hestia.execute(f"nohup timeout 12 tcpdump -nl -i eth1 -Q {d} -c1 'icmp and dst 198.51.100.1' >/tmp/{d}.cap 2>&1 &")
        hestia.sleep(2)
        homerouter.execute(f"ping -c3 -W1 -I {src_ip} 198.51.100.1")
        hestia.sleep(3)
        arrived = hestia.execute("grep -q 'ICMP echo request' /tmp/in.cap")[0] == 0
        forwarded = hestia.execute("grep -q 'ICMP echo request' /tmp/out.cap")[0] == 0
        return arrived, forwarded

    with subtest("exit gate: a LAN neighbour cannot use hestia as a router"):
        hestia.succeed("test $(sysctl -n net.ipv4.conf.all.forwarding) = 1")
        homerouter.succeed("ip route replace 198.51.100.1/32 via 192.168.178.32")
        arrived, forwarded = probe_router("192.168.178.2")
        assert arrived and not forwarded, (arrived, forwarded)

    with subtest("exit gate: a spoofed mesh source is neither forwarded nor masqueraded"):
        homerouter.succeed("ip addr add 10.100.0.9/32 dev lo")
        homerouter.succeed("ip route replace 198.51.100.1/32 via 192.168.178.32 src 10.100.0.9")
        arrived, forwarded = probe_router("10.100.0.9")
        assert arrived and not forwarded, (arrived, forwarded)
        homerouter.succeed("ip route del 198.51.100.1/32; ip addr del 10.100.0.9/32 dev lo")

    with subtest("exit gate: relayed traffic still works and may not leave via tukl"):
        hermes.succeed("vpn egress hestia")
        out = hermes.succeed(curl).strip()
        assert out == "203.0.113.20", f"expected egress via hestia, got {out!r}"
        hestia.succeed("ip link add tukl type dummy; ip link set tukl up; ip addr add 192.0.2.1/24 dev tukl")
        hestia.succeed("ip route replace 198.51.100.1/32 dev tukl")
        hermes.fail(curl)
        hestia.succeed("nft list chain inet vpn-exit forward | grep 'oifname \"tukl\"' | grep -v 'packets 0 '")
        hestia.succeed("ip link del tukl")
        hermes.succeed("vpn egress direct")

    with subtest("exit gate: languard follows the networks the exit joins and leaves"):
        hestia.wait_for_unit("vpn-languard-watch.service")
        hestia.succeed("ip link add dum0 type dummy; ip link set dum0 up")
        hestia.succeed("ip addr add 10.77.0.1/24 dev dum0")
        hestia.succeed("ip -6 addr add 2001:db8:1:2::1/64 dev dum0 nodad")
        hestia.wait_until_succeeds("nft list set inet vpn-exit lan4 | grep 10.77.0.0/24")
        # a global /64 is widened to the /56 around it
        hestia.wait_until_succeeds("nft list set inet vpn-exit lan6 | grep -F 2001:db8:1::/56")
        hestia.fail("nft list set inet vpn-exit lan6 | grep -F 2001:db8:1:2::/64")
        hestia.succeed("ip link del dum0")
        hestia.wait_until_fails("nft list set inet vpn-exit lan4 | grep 10.77.0.0/24")
        hestia.wait_until_fails("nft list set inet vpn-exit lan6 | grep -F 2001:db8:1::/56")

    with subtest("gates: loaded before the network, required by the mesh, reloaded without a bounce"):
        for m, gate in [(olympus, "vpn-hub-nft"), (hestia, "vpn-exit-nft")]:
            assert "network-pre.target" in m.succeed(f"systemctl show -p Before --value {gate}.service")
            props = m.succeed("systemctl show -p Requires -p After wireguard-olympus.service")
            assert props.count(f"{gate}.service") == 2, props
            before = m.succeed("systemctl show -p InvocationID --value wireguard-olympus.service")
            m.succeed(f"systemctl reload {gate}.service")
            assert before == m.succeed("systemctl show -p InvocationID --value wireguard-olympus.service")
        # the mesh cannot stay up (or start) without its gate
        hestia.succeed("systemctl stop vpn-exit-nft.service")
        hestia.fail("systemctl is-active wireguard-olympus.service")
        hestia.succeed("systemctl start wireguard-olympus.service")
        hestia.succeed("systemctl is-active vpn-exit-nft.service")
        hestia.wait_until_succeeds("ping -c1 -W2 10.100.0.1")
        hestia.wait_until_succeeds("nft list set inet vpn-exit lan4 | grep 192.168.178.0/24")

    with subtest("hub: a missing exit link drops the phone's traffic, never sends it out of olympus"):
        hestia.succeed("systemctl start vpn-languard-watch.service")
        olympus.succeed("vpn-phone phone1 egress hermes")
        out = phone.succeed(curl).strip()
        assert out == "203.0.113.30", f"expected phone egress via hermes, got {out!r}"
        for f in ["-4", "-6"]:
            olympus.succeed(f"ip {f} route show table 2003 | grep blackhole")
        olympus.succeed("ip link del vpn-hermes")
        out = phone.execute(curl)[1].strip()
        assert out == "", f"expected a dropped connection, got {out!r}"
        # the fallback also holds while the whole mesh unit is down
        olympus.succeed("systemctl stop wireguard-olympus.service")
        olympus.succeed("ip route show table 2003 | grep blackhole")
        out = phone.execute(curl)[1].strip()
        assert out == "", f"expected a dropped connection, got {out!r}"
        # the hub has to wait for the spokes' keepalives to re-handshake
        olympus.succeed("systemctl start wireguard-olympus.service")
        phone.wait_until_succeeds(f"{curl} | grep -x 203.0.113.30", timeout=180)
        hestia.wait_until_succeeds("ping -c1 -W2 10.100.0.1", timeout=180)
        olympus.succeed("vpn-phone phone1 egress olympus")

    with subtest("hub: phones reach the internet, not private or metadata ranges behind the uplink"):
        internet.succeed("ip addr add 169.254.169.254/32 dev lo; ip addr add 10.55.0.1/32 dev lo")
        out = phone.succeed(curl).strip()
        assert out == "203.0.113.10", f"expected phone egress via olympus, got {out!r}"
        phone.fail("curl -s --max-time 5 http://169.254.169.254/")
        phone.fail("curl -s --max-time 5 http://10.55.0.1/")
        olympus.succeed("nft list chain inet vpn-hub forward | grep 169.254.0.0/16 | grep -v 'packets 0 '")
        # olympus itself is not subject to the phone gate
        olympus.succeed("curl -s --max-time 5 http://10.55.0.1/")

    with subtest("hub: the internet cannot open connections into the mesh"):
        internet.succeed("ip route add 10.100.0.2/32 via 203.0.113.10")
        hestia.succeed("rm -f /tmp/hub.cap")
        hestia.execute("nohup timeout 12 tcpdump -nl -i olympus -c1 'icmp and src 203.0.113.1' >/tmp/hub.cap 2>&1 &")
        hestia.sleep(2)
        internet.execute("ping -c3 -W1 10.100.0.2")
        hestia.sleep(3)
        hestia.fail("grep -q 'ICMP echo request' /tmp/hub.cap")
        olympus.succeed("nft list chain inet vpn-hub forward | grep '\"eth1\".*\"olympus\"' | grep -v 'packets 0 '")
        internet.succeed("ip route del 10.100.0.2/32")

    with subtest("sshd: reachable over the mesh and from the home LAN, closed to the internet"):
        for m in hosts:
            m.wait_for_unit("sshd.service")
        hermes.succeed("nc -z -w2 10.100.0.2 22")
        homerouter.succeed("nc -z -w2 192.168.178.32 22")
        internet.fail("nc -z -w2 203.0.113.30 22")
    with subtest("phone: malformed db rows are skipped, never reach nft or ip"):
        olympus.succeed("vpn-phone phone1 egress hestia")
        olympus.succeed(
            "sqlite3 /var/lib/wg-easy/wg-easy.db \""
            "INSERT INTO clients_table VALUES "
            "('${keys.hermes.public}', '10.100.1.5 }; delete table inet vpn-hub', '${phone6}:5', 'evil' || char(10) || 'x' || char(9) || 'y', 1, 'wg0'), "
            "('${keys.hermes.public}', '10.100.2.7', '${phone6}:6', 'outside', 1, 'wg0'), "
            "('${keys.hermes.public}', '10.100.1.8', 'fdcc:ad94:bacf:61a5::cafe:8', 'outside6', 1, 'wg0'), "
            "('not-a-key', '10.100.1.9', '${phone6}:9', 'badkey', 1, 'wg0'), "
            "('${keys.hermes.public}', '10.100.1.10', '${phone6}:a', 'enabled-true', 'true', 'wg0');\""
        )
        err = olympus.succeed("vpn-phone apply 2>&1 >/dev/null")
        assert err.count("skipping malformed") >= 4, err
        olympus.succeed("nft list table inet vpn-hub")
        olympus.succeed("ip rule show | grep 3500 | grep -c 10.100.1.2")
        olympus.fail("ip rule show | grep -E '10.100.(1.(5|8|9|10)|2.7)'")
        listing = olympus.succeed("vpn-phone list 2>/dev/null")
        assert "phone1" in listing and "evil" not in listing, listing
        out = phone.succeed(curl).strip()
        assert out == "203.0.113.20", f"expected phone egress via hestia, got {out!r}"
        olympus.succeed("sqlite3 /var/lib/wg-easy/wg-easy.db \"DELETE FROM clients_table WHERE name <> 'phone1'\"")
        olympus.succeed("vpn-phone phone1 egress olympus")

    with subtest("phone: revoking hosts or changing egress ends established flows"):
        olympus.succeed("vpn-phone phone1 hosts on")
        phone.succeed("(ping -i 0.2 10.100.0.2 > /tmp/ping.log 2>&1 &)")
        olympus.wait_until_succeeds("conntrack -L -s 10.100.1.2 -d 10.100.0.2 2>&1 | grep -q icmp")
        olympus.succeed("vpn-phone phone1 hosts off")
        olympus.succeed("test -z \"$(conntrack -L -s 10.100.1.2 2>/dev/null)\"")
        phone.succeed("pkill ping")
        out = phone.succeed(curl).strip()
        assert out == "203.0.113.10", f"expected phone egress via olympus, got {out!r}"
        olympus.succeed("conntrack -L -s 10.100.1.2 2>/dev/null | grep -q 198.51.100.1")
        olympus.succeed("vpn-phone phone1 egress hestia")
        olympus.succeed("test -z \"$(conntrack -L -s 10.100.1.2 2>/dev/null)\"")
        olympus.succeed("vpn-phone phone1 egress olympus")
        olympus.succeed("systemctl show -p RestartUSec -p StartLimitIntervalUSec vpn-phones.service | grep -x -e RestartUSec=5s -e StartLimitIntervalUSec=0")

    with subtest("phone: wg-easy interface hooks are cleared and wg-easy restarted"):
        db = "/var/lib/wg-easy/wg-easy.db"
        before = olympus.succeed("systemctl show -p InvocationID --value podman-wg-easy.service").strip()
        olympus.succeed(f"sqlite3 {db} \"UPDATE hooks_table SET post_up = 'touch /tmp/hook-ran'\"")
        olympus.wait_until_succeeds(f"test \"$(sqlite3 {db} 'SELECT count(*) FROM hooks_table WHERE length(post_up) > 0')\" = 0")
        olympus.wait_until_succeeds("journalctl -u vpn-phones.service -p err -o cat | grep -q 'interface hooks are set'")
        olympus.wait_until_succeeds(f"test \"$(systemctl show -p InvocationID --value podman-wg-easy.service)\" != {before}")
        olympus.succeed("systemctl is-active vpn-phones.service")
    with subtest("A1: a full tunnel never carries the home lan"):
        hermes.succeed("vpn egress olympus")
        hermes.fail(f"ping -c1 -W2 {home}")
        hermes.succeed("systemctl start vpn-home.service")
        hermes.wait_until_succeeds(f"ping -c1 -W2 {home}")
        hermes.succeed("systemctl stop vpn-home.service")
        hermes.fail(f"ping -c1 -W2 {home}")
        hermes.succeed("vpn egress direct")

    with subtest("A2: a vanished tunnel route drops, never falls through to direct"):
        hermes.succeed("vpn egress olympus")
        hermes.succeed("ip route del default dev olympus table 2100")
        hermes.succeed("ip -6 route del default dev olympus table 2100")
        out = hermes.execute(curl)[1].strip()
        assert out == "", f"expected a dropped connection, got {out!r}"
        hermes.succeed("vpn egress direct")

    with subtest("A6: gatewayed routes pushed into main cannot pull traffic around the tunnel"):
        watch = "vpn-egress-watch@vpn-egress-olympus.service"
        hermes.succeed("vpn egress olympus")
        hermes.succeed("ip route show table 2150 | grep -F 10.100.0.0/16")
        hermes.succeed("ip route show table 2150 | grep -F 203.0.113.0/24")
        hermes.fail("ip route show table 2150 | grep default")
        hermes.succeed("ip route add 0.0.0.0/1 via 203.0.113.1 dev eth1")
        hermes.succeed("ip route add 128.0.0.0/1 via 203.0.113.1 dev eth1")
        hermes.sleep(3)
        hermes.fail("ip route show table 2150 | grep -E '^(0.0.0.0|128.0.0.0)/1 '")
        out = hermes.succeed(curl).strip()
        assert out == "203.0.113.10", f"expected egress via olympus, got {out!r}"
        hermes.sleep(40)
        hermes.fail(f"journalctl -u '{watch}' | grep 'path left'")
        # an on-link route appearing later is picked up by the follower
        hermes.succeed("ip route add 198.18.0.0/24 dev eth1")
        hermes.wait_until_succeeds("ip route show table 2150 | grep -F 198.18.0.0/24")
        hermes.succeed("ip route del 198.18.0.0/24 dev eth1")
        hermes.wait_until_fails("ip route show table 2150 | grep -F 198.18.0.0/24")
        hermes.succeed("ip route del 0.0.0.0/1 via 203.0.113.1 dev eth1")
        hermes.succeed("ip route del 128.0.0.0/1 via 203.0.113.1 dev eth1")
        hermes.succeed("vpn egress direct")
        hermes.fail("systemctl is-active vpn-onlink.service")
        hermes.fail("ip route show table 2150 | grep .")

    def poll_start():
        hermes.succeed("rm -f /tmp/poll.log")
        hermes.succeed(
            "systemd-run --unit=poll -p StandardOutput=file:/tmp/poll.log -E PATH=$PATH "
            "sh -c 'while true; do curl -s --max-time 2 http://198.51.100.1/ || echo fail; sleep 0.1; done'"
        )

    def poll_stop():
        hermes.succeed("systemctl stop poll.service")
        return hermes.succeed("cat /tmp/poll.log").split()

    with subtest("A3: switching exits never shows the direct address"):
        hermes.succeed("vpn egress hestia")
        poll_start()
        for target in ["olympus", "hestia", "olympus", "hestia"]:
            hermes.succeed(f"vpn egress {target}")
            hermes.sleep(1)
        seen = poll_stop()
        assert "203.0.113.30" not in seen, f"direct address leaked during a switch: {seen}"
        assert {"203.0.113.10", "203.0.113.20"} <= set(seen), seen

    with subtest("A3: a failed switch stays dropped and reports inconsistent, direct recovers"):
        hermes.succeed("ip link add tukl type dummy")
        hermes.fail("vpn egress olympus")
        out = hermes.execute(curl)[1].strip()
        assert out == "", f"expected a dropped connection, got {out!r}"
        rc, out = hermes.execute("vpn status --short")
        assert rc == 1 and out.strip() == "inconsistent", (rc, out)
        hermes.succeed("ip link del tukl")
        hermes.succeed("vpn egress direct")
        out = hermes.succeed(curl).strip()
        assert out == "203.0.113.30", f"expected direct egress, got {out!r}"
        assert short(hermes) == "direct", short(hermes)
        check_exclusive(hermes, [])
        hermes.succeed("systemctl reset-failed vpn-egress-olympus.service")

    with subtest("A4: a mesh restart drops, never leaks, and the egress comes back by itself"):
        for target, address in [("olympus", "203.0.113.10"), ("hestia", "203.0.113.20")]:
            hermes.succeed(f"vpn egress {target}")
            poll_start()
            hermes.succeed("systemctl restart wireguard-olympus.service")
            hermes.wait_until_succeeds(f"{curl} | grep -x {address}", timeout=60)
            hermes.sleep(1)
            seen = poll_stop()
            assert "203.0.113.30" not in seen, f"direct address leaked during a mesh restart: {seen}"
            assert address in seen, seen
            hermes.succeed(f"systemctl is-active vpn-egress-{target}.service")
        hermes.succeed("vpn egress direct")

    with subtest("A4: mesh off means direct"):
        hermes.succeed("vpn egress olympus")
        hermes.succeed("vpn mesh off")
        out = hermes.succeed(curl).strip()
        assert out == "203.0.113.30", f"expected direct egress, got {out!r}"
        hermes.fail("ip rule show | grep -E '^(5200|5300):'")
        check_exclusive(hermes, [])
        hermes.succeed("vpn mesh on")
        hermes.wait_until_succeeds("ping -c1 -W2 10.100.0.1")
        assert short(hermes) == "direct", short(hermes)

    with subtest("C2: odd spellings and duplicate addresses neither break apply nor leave stale set entries"):
        db = "/var/lib/wg-easy/wg-easy.db"
        ka, kb, kc = "A" * 43 + "=", "B" * 43 + "=", "C" * 43 + "="
        olympus.succeed(
            f"sqlite3 {db} \""
            f"INSERT INTO clients_table VALUES "
            f"('{ka}', '10.100.1.20', 'FDCC:AD94:BACF:61A4:0000:0000:CAFE:0014', 'upper', 1, 'wg0'), "
            f"('{kb}', '10.100.1.30', '${phone6}:1e', 'dup1', 1, 'wg0'), "
            f"('{kc}', '10.100.1.30', '${phone6}:1f', 'dup2', 1, 'wg0');\""
        )
        err = olympus.succeed("vpn-phone apply 2>&1 >/dev/null")
        assert err.count("used by another row") == 2, err
        olympus.succeed("vpn-phone upper hosts on")
        olympus.succeed("vpn-phone upper hosts on")
        olympus.succeed("nft list set inet vpn-hub phone_hosts6 | grep -q 'fdcc:ad94:bacf:61a4::cafe:14'")
        olympus.succeed("nft list set inet vpn-hub phone_hosts | grep -q 10.100.1.20")
        olympus.succeed("vpn-phone upper egress hestia")
        olympus.succeed("vpn-phone upper egress hestia")
        olympus.succeed("ip -6 rule show pref 3500 | grep -c 'fdcc:ad94:bacf:61a4::cafe:14' | grep -x 1")
        olympus.succeed("ip rule show pref 3500 | grep -c 10.100.1.20 | grep -x 1")
        olympus.fail("ip rule show pref 3500 | grep -e 10.100.1.30")
        # a rule that already exists, or one that vanished behind its back
        olympus.succeed("ip -6 rule del from fdcc:ad94:bacf:61a4::cafe:14/128 pref 3500")
        olympus.succeed("ip rule add from 10.100.1.20/32 lookup 2012 pref 3500 || true")
        olympus.succeed("vpn-phone upper egress hestia")
        olympus.succeed("ip -6 rule show pref 3500 | grep -c 'fdcc:ad94:bacf:61a4::cafe:14' | grep -x 1")
        olympus.succeed("vpn-phone upper hosts off")
        olympus.fail("nft list set inet vpn-hub phone_hosts6 | grep -q cafe:14")
        olympus.fail("nft list set inet vpn-hub phone_hosts | grep -q 10.100.1.20")
        olympus.succeed("vpn-phone upper egress olympus")
        olympus.fail("ip rule show pref 3500 | grep -e 10.100.1.20 -e 10.100.1.30")
        olympus.fail("ip -6 rule show pref 3500 | grep -e cafe:14")
        olympus.succeed("ip rule show pref 3500 | grep -c 10.100.1.2 || true")
        olympus.succeed(f"sqlite3 {db} \"DELETE FROM clients_table WHERE name <> 'phone1'\"")
        olympus.succeed("vpn-phone apply")
        out = phone.succeed(curl).strip()
        assert out == "203.0.113.10", f"expected phone egress via olympus, got {out!r}"
  '';
}
