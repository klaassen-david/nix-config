{
  config,
  lib,
  secretsPath,
  ...
}:

# -----------------------------------------------------------------------------
# ACME — automatic renewal of the shared wildcard cert
# -----------------------------------------------------------------------------
# Replaces the hand-rolled pair in ssl-fullchain.age / ssl-key.age, which has no
# renewal path and simply stops working on its notAfter date. Gated by
# host.tls.acme; ../nginx switches sslVhost and tlsCert on the same flag.
#
# dns-01, so the cert stays a wildcard: RFC 8555 permits no other challenge for a
# wildcard identifier. lego's `ionos` provider writes the _acme-challenge TXT
# through the hosting API (dklaassen.de is served by ui-dns.*) — that is all the
# IONOS API key does here; it is a *zone* credential, unrelated to the CA. If the
# propagation check times out, add IONOS_PROPAGATION_TIMEOUT=<seconds> to the
# environment file rather than disabling the check.
#
# The CA is Let's Encrypt because IONOS' own endpoint
# (https://acme.ionos.com/directory) cannot issue for this account. It is DV-only
# and issues solely against a *purchased, unassigned* certificate in the
# contract, refusing at newOrder before any challenge:
#   unauthorized :: The list of domains is not valid for a certificate
#     — an explicit per-vhost SAN list is not an identifier set it recognises.
#   unauthorized :: No available certificate found for the requested domain(s)
#     — `*.dklaassen.de` + apex is recognised, but the only DV wildcard on the
#       account is already issued and Assigned, and a panel reissue did not free
#       a slot. Its EAB pairs are also single-use per registration.
# None of that is reachable from Nix. Let's Encrypt needs neither an entitlement
# nor EAB, and issues the same wildcard over the same dns-01 setup.
#
# acme-env.age is therefore ONE line — the two halves of the IONOS API key
# joined by a dot:
#   IONOS_API_KEY=<public prefix>.<secret>
# Any leftover LEGO_EAB* lines must be removed: lego would attempt an EAB
# registration against a CA that does not offer one, and fail. systemd reads
# EnvironmentFile as root before the unit drops to the acme user, so the default
# 0400 root mode is correct.
#
# Switching over is a soft failure, not an outage, but it *is* visible: nixpkgs
# writes a self-signed placeholder into /var/lib/acme/${domain} and nginx and
# stalwart serve it until issuance succeeds. Only set host.tls.acme = true once
# the secret is in place, and read acme-order-renew-${domain}.service right
# after (acme-${domain}.service only prepares the placeholder). That unit is
# oneshot with no Restart=, so a failure waits for the daily timer — start it by
# hand rather than leaving the placeholder facing the internet. Setting
# host.tls.acme back to false restores the agenix pair.

let
  domain = "dklaassen.de";
in
{
  config = lib.mkIf config.host.tls.acme {
    age.secrets.acme-env.file = "${secretsPath}/acme-env.age";

    security.acme = {
      acceptTerms = true;
      defaults.email = "postmaster@${domain}";

      certs.${domain} = {
        # the attr name is only the directory under /var/lib/acme; the wildcard
        # is the CN and the apex rides along, matching the cert being replaced.
        domain = "*.${domain}";
        extraDomainNames = [ domain ];

        dnsProvider = "ionos";
        environmentFile = config.age.secrets.acme-env.path;

        # rsa2048 over lego's ec256 default: this cert also terminates SMTP/IMAP
        # for arbitrary remote MTAs, and it is what the current cert uses.
        keyType = "rsa2048";

        # nginx reads the PEMs as the ssl-cert group and is added to
        # reloadServices by the nixpkgs nginx module (useACMEHost). Stalwart
        # inlines them with %{file:..}% at startup, so it needs restarting too.
        group = "ssl-cert";
        reloadServices = lib.optional config.services.stalwart.enable "stalwart.service";
      };
    };
  };
}
