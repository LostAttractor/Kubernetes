{ inputs, pkgs, ... }:
{
  imports = [
    (inputs.homelab + "/features/basic.nix")
    (inputs.homelab + "/features/nix")
    (inputs.homelab + "/features/fish.nix")
    (inputs.homelab + "/features/network/avahi")
    ./k3s
    ./k3s/longhorn.nix
  ];

  networking.useNetworkd = true;
  networking.nftables.enable = true;

  boot.kernel.sysctl = {
    ## TCP optimization
    # TCP Fast Open is a TCP extension that reduces network latency by packing
    # data in the sender’s initial TCP SYN. Setting 3 = enable TCP Fast Open for
    # both incoming and outgoing connections:
    "net.ipv4.tcp_fastopen" = 3;
    ## TCP congestion control
    "net.ipv4.tcp_congestion_control" = "bbr";
    ## UDP Buffersize (https://github.com/quic-go/quic-go/wiki/UDP-Buffer-Sizes)
    "net.core.rmem_max" = 7500000;
    "net.core.wmem_max" = 7500000;
  };

  # https://nixos.wiki/wiki/Networkd-dispatcher
  services.networkd-dispatcher = {
    enable = true;
    rules = {
      "50-tailscale" = {
        onState = [ "routable" ];
        # https://www.kernel.org/doc/html/latest/networking/segmentation-offloads.html
        # https://tailscale.com/kb/1320/performance-best-practices#ethtool-configuration
        # https://tailscale.com/blog/more-throughput
        script = ''
          #!${pkgs.runtimeShell}
          ${pkgs.ethtool}/bin/ethtool -K $IFACE tx-udp-segmentation on rx-udp-gro-forwarding on rx-gro-list off
        '';
      };
    };
  };

  users = {
    # Don't allow mutation of users outside of the config.
    mutableUsers = false;
    # Privilege User
    users.root.openssh.authorizedKeys.keys = [
      "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBC5HypvbsI4xvwfd4Uw7D+SV0AevYPS/nCarFwfBwrMHKybbqUJV1cLM1ySZPxXcZD7+3m48Riiwlssh6o7WM/M= openpgp:0xDE4C24F6"
    ];
  };

  sops.defaultSopsFile = ../secrets.yaml;

  system.stateVersion = "24.05";
}
