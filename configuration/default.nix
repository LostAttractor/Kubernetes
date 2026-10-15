{
  inputs,
  pkgs,
  lib,
  ...
}@args:
{
  imports = [
    (inputs.homelab + "/features/basic.nix")
    (inputs.homelab + "/features/nix")
    (inputs.homelab + "/features/fish.nix")
    (inputs.homelab + "/features/time.nix")
    ./k3s
  ];

  networking.useNetworkd = true;
  networking.nftables.enable = true;

  networking.firewall = {
    trustedInterfaces = [
      "tailscale0"
      "cni0"
    ];
    allowedTCPPorts = [
      80
      443
    ];
  };

  # NodePort packets are forwarded after DNAT and bypass the host INPUT chain.
  networking.nftables.tables.k3s-public-boundary = {
    family = "inet";
    content =
      let
        interface = if args.zone == "home" then "enp6s18" else "ens5";
      in
      ''
        chain forward {
          type filter hook forward priority filter - 5; policy accept;
          iifname "${interface}" ct state established,related return
          iifname "${interface}" meta l4proto { tcp, udp } ct original proto-dst 30000-32767 counter drop
        }
      '';
  };

  # DHCPv6或许更适合用于分发"确定的"地址, 但现在systemd networkd不支持在DHCPv6中选择拒绝某个地址簇
  systemd.network.networks."99-ethernet-default-dhcp" = lib.mkMerge [
    (lib.mkIf (args.zone == "home") {
      ipv6AcceptRAConfig.PrefixDenyList = [ "fc00::/7" ];
      dhcpV6Config.UseAddress = false;
      networkConfig.IPv6PrivacyExtensions = lib.mkForce false;
      routingPolicyRules = [
        {
          To = "10.0.0.1/16";
          Priority = 5260;
          Table = 254;
        }
      ];
    })
  ];

  boot.kernel.sysctl = {
    ## Conntrack
    "net.netfilter.nf_conntrack_udp_timeout" = 60;
    "net.netfilter.nf_conntrack_udp_timeout_stream" = 180;
    ## TCP optimization
    # TCP Fast Open is a TCP extension that reduces network latency by packing
    # data in the sender’s initial TCP SYN. Setting 3 = enable TCP Fast Open for
    # both incoming and outgoing connections:
    "net.ipv4.tcp_fastopen" = 3;
    ## TCP congestion control
    "net.ipv4.tcp_congestion_control" = "bbr";
    ## UDP Buffersize (https://github.com/quic-go/quic-go/wiki/UDP-Buffer-Sizes)
    ## https://docs.redhat.com/en/documentation/red_hat_data_grid/7.2/html/performance_tuning_guide/networking_configuration#adjusting_send_receive_window_settings
    "net.core.wmem_max" = 655360;
    "net.core.rmem_max" = 26214400;
    "net.ipv4.tcp_wmem" = "4096 16384 655360";
    "net.ipv4.tcp_rmem" = "4096 87380 26214400";
  };

  # https://nixos.wiki/wiki/Networkd-dispatcher
  services.networkd-dispatcher = {
    enable = true;
    rules = {
      "50-offload" = {
        onState = [ "routable" ];
        script = ''
          #!${pkgs.runtimeShell}
          ${pkgs.ethtool}/bin/ethtool -K "$IFACE" rx-udp-gro-forwarding on rx-gro-list off
          ${pkgs.ethtool}/bin/ethtool -K "$IFACE" tx-udp-segmentation on
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
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKAZlyUPTK3lIjjO21evwBvtcfk5rAoSZB4F5kNe9O7P NixNAS"
    ];
  };

  sops.defaultSopsFile = ../secrets.yaml;

  system.stateVersion = "25.11";
}
