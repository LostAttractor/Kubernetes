{
  pkgs,
  config,
  lib,
  clusterInit,
  ...
} @ args:
let
  role = if (args ? role) && args.role == "server" then "server" else "agent";
  isClusterInit = config.networking.hostName == clusterInit;
  isServer = role == "server";
  isExitNode = (args ? exitNode) && args.exitNode;
in
{
  networking.firewall.allowedTCPPorts = [
    10250 # k3s, kubelet metrics
  ] ++ lib.optionals isServer [
    6443  # k3s: required so that pods can reach the API server (running on port 6443 by default)
    2379  # k3s, etcd clients: required if using a "High Availability Embedded etcd" configuration
    2380  # k3s, etcd peers: required if using a "High Availability Embedded etcd" configuration
  ];
  networking.firewall.allowedUDPPorts = [
    # 8472   # k3s, flannel: required if using multi-node for inter-node networking
    # 51820  # k3s, flannel wireguard with ipv4: required if using multi-node for inter-node networking
    # 51821  # k3s, flannel wireguard with ipv6: required if using multi-node for inter-node networking
  ];

  services.tailscale = {
    enable = true;
    useRoutingFeatures = "both";
  };

  networking.firewall.trustedInterfaces = [ "cni0" "tailscale0" ];

  services.k3s = {
    enable = true;
    role = role; # Or "agent" for worker only nodes
    clusterInit = isClusterInit;
    serverAddr = lib.mkIf (!isClusterInit) "https://${clusterInit}.home.lostattractor.net:6443";
    tokenFile = lib.mkIf (!isClusterInit) config.sops.secrets."kubernetes/token".path;
    extraFlags = toString (lib.optionals isServer [
      "--tls-san=${config.networking.hostName}.home.lostattractor.net"
      "--cluster-cidr=10.42.0.0/16,2001:cafe:42::/56 --service-cidr=10.43.0.0/16,2001:cafe:43::/112"
      "--flannel-ipv6-masq"
    ] ++ lib.optionals isExitNode [
      "--vpn-auth-file=${config.sops.templates."kubernetes/tailscale-exitnode".path}"
    ] ++ lib.optionals (!isExitNode) [
      "--vpn-auth-file=${config.sops.secrets."kubernetes/tailscale".path}"
    ] ++ [
      # https://github.com/coredns/coredns/blob/master/plugin/loop/README.md
      "--resolv-conf=/run/systemd/resolve/resolv.conf"
      "--kubelet-arg=config=${pkgs.writeText "kubelet.config" ''
        apiVersion: kubelet.config.k8s.io/v1beta1
        kind: KubeletConfiguration
        memorySwap:
          swapBehavior: LimitedSwap
      ''}"
      # "--kubelet-arg=v=4" # Optionally add additional args to k3s
    ]);
  };

  sops.templates."kubernetes/tailscale-exitnode".content = ''
    ${config.sops.placeholder."kubernetes/tailscale"},extraArgs=--advertise-exit-node
  '';

  systemd.services.k3s.path = [ pkgs.tailscale pkgs.nftables ];

  sops.secrets."kubernetes/token" = { };
  sops.secrets."kubernetes/tailscale" = { };
}
