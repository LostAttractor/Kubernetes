{ inputs, pkgs, lib, ... } @ args:
{
  imports = [
    (inputs.homelab + "/features/basic.nix")
    (inputs.homelab + "/features/nix")
    (inputs.homelab + "/features/fish.nix")
    (inputs.homelab + "/features/time.nix")
    ./rke2
    ./rke2/longhorn.nix
  ];

  networking.useNetworkd = true;
  networking.nftables.enable = true;

  networking.firewall.enable = false;

  # DHCPv6或许更适合用于分发"确定的"地址, 但现在systemd networkd不支持在DHCPv6中选择拒绝某个地址簇
  systemd.network.networks."99-ethernet-default-dhcp" = lib.mkMerge [ (lib.mkIf (args.zone == "home") {
    ipv6AcceptRAConfig.PrefixDenyList = [ "fc00::/7" ];
    dhcpV6Config.UseAddress = false;
    networkConfig.IPv6PrivacyExtensions = lib.mkForce false;
  }) (lib.mkIf (args.zone != "home") {
    networkConfig.DNS = [ "8.8.8.8" ];
  }) ];

  environment.etc."kubernetes-resolv.conf".text = ''
    nameserver 64:ff9b::8.8.8.8
    nameserver 8.8.8.8
  '';

  networking.jool.enable = true;
  networking.jool.nat64.default = {};

  boot.kernel.sysctl = {
    "vm.swappiness" = 1;
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
    ];
  };

  sops.defaultSopsFile = ../secrets.yaml;

  system.stateVersion = "24.05";
}
