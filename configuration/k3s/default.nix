{
  pkgs,
  config,
  lib,
  clusterInit,
  ...
}@args:
let
  role = if (args ? role) && args.role == "server" then "server" else "agent";
  isClusterInit = config.networking.hostName == clusterInit;
  isServer = role == "server";

in
{
  services.k3s = {
    enable = true;
    package = pkgs.k3s_1_37;
    role = role; # Or "agent" for worker only nodes
    clusterInit = isClusterInit;
    serverAddr = lib.mkIf (!isClusterInit) "https://${clusterInit}:6443";
    tokenFile = config.sops.secrets."kubernetes/token".path;
    extraFlags = lib.optionals isServer [
      "--flannel-ipv6-masq"
    ];
  };

  environment.variables.KUBECONFIG = lib.mkIf isServer "/etc/rancher/k3s/k3s.yaml";
  environment.systemPackages = with pkgs; [ kubectl ];

  environment.etc."rancher/k3s/config.yaml".text =
    lib.optionalString isServer ''
      # Server
      # 需要将默认地址簇写在前面, 并且 API Server 的 Advertise Address 需要和默认地址簇相同
      cluster-cidr: "10.42.0.0/16,2001:db8:42::/56"
      service-cidr: "10.43.0.0/16,2001:db8:43::/112"
      embedded-registry: true
      secrets-encryption: true
    ''
    + ''
      # Client
      vpn-auth-file: ${config.sops.secrets."kubernetes/vpn-auth".path}
      # https://github.com/coredns/coredns/blob/master/plugin/loop/README.md
      resolv-conf: /run/systemd/resolve/resolv.conf
      node-label:
        - topology.kubernetes.io/zone=${args.zone}
    ''
    + lib.optionalString (args ? taint) ''
      node-taint:
        - "${args.taint}"
    '';

  environment.etc."rancher/k3s/registries.yaml".text = ''
    mirrors:
      "*":
  '';

  systemd.services.k3s.path = with pkgs; [
    tailscale
    nftables
  ];

  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "both";
  };

  sops.secrets."kubernetes/token".restartUnits = [ "k3s.service" ];
  sops.secrets."kubernetes/vpn-auth".restartUnits = [ "k3s.service" ];

  # networking.firewall.allowedTCPPorts = [
  #   10250 # rke2, kubelet metrics
  #   4240 # rke2/cilium, health checks
  #   4244  # rke2/cilium, hubble server
  #   4245  # rke2/cilium, hubble relay
  #   5001  # rke2/p2p, spegel
  # ] ++ lib.optionals isServer [
  #   6443  # rke2: required so that pods can reach the API server (running on port 6443 by default)
  #   9345  # rke2: supervisor API
  #   2379  # rke2, etcd clients
  #   2380  # rke2, etcd peers
  #   2381  # rke2, etcd metrics port
  # ];
  # networking.firewall.allowedTCPPortRanges = [
  #   { from = 30000; to = 32767; } # rke2, NodePort port range
  # ];
  # networking.firewall.allowedUDPPorts = [
  #   8472 # rke2/cilium, vxlan
  #   51871 # rke2/cilium, wireguard
  # ];
}
