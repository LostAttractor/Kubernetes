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
  kubeletConfig = ''
    apiVersion: kubelet.config.k8s.io/v1beta1
    kind: KubeletConfiguration
    memorySwap:
      swapBehavior: LimitedSwap
  '';
in
{
  networking.firewall.allowedTCPPorts = [
    10250 # rke2, kubelet metrics
    4240 # rke2/cilium, health checks
    4244  # rke2/cilium, hubble server
    4245  # rke2/cilium, hubble relay
    5001  # rke2/p2p, spegel
  ] ++ lib.optionals isServer [
    6443  # rke2: required so that pods can reach the API server (running on port 6443 by default)
    9345  # rke2: supervisor API
    2379  # rke2, etcd clients
    2380  # rke2, etcd peers
    2381  # rke2, etcd metrics port
  ];
  networking.firewall.allowedTCPPortRanges = [
    { from = 30000; to = 32767; } # rke2, NodePort port range
  ];
  networking.firewall.allowedUDPPorts = [
    8472 # rke2/cilium, vxlan
  ];
  # # will "loose" work? Probably not
  # networking.firewall.checkReversePath = lib.mkForce false;  # Conflict with cilium
  # networking.firewall.logReversePathDrops = true;

  boot.kernel.sysctl = {
    # Disable rp_filter on Cilium interfaces since it may cause mangled packets to be dropped
    "-net.ipv4.conf.lxc*.rp_filter" = 0;
    "-net.ipv4.conf.cilium_*.rp_filter" = 0;
    # The kernel uses max(conf.all, conf.{dev}) as its value, so we need to set .all. to 0 as well.
    # Otherwise it will overrule the device specific settings.
    "net.ipv4.conf.all.rp_filter" = 0;
  };

  boot.kernelPatches = [ {
    name = "netkit";
    patch = null;
    extraConfig = ''
      NETKIT y
    '';
  } ];

  services.tailscale = {
    enable = true;
    useRoutingFeatures = "both";
    authKeyFile = config.sops.secrets.tailscale.path;
  };

  # systemd.services.tailscaled.serviceConfig.Environment = [ "TS_DEBUG_MTU=1420" ];

  # cilium vxlan 模式下只需要 vxlan 端口可达, 但是有些 daemonset 可能会直接使用 hostNetwork / hostPort
  networking.firewall.trustedInterfaces = [ "tailscale0" "lxc*" /*"cilium_host" "cilium_net" "cilium_vxlan"*/ ];

  services.rke2 = {
    enable = true;
    # cisHardening = true;
    role = role; # Or "agent" for worker only nodes
    tokenFile = config.sops.secrets."kubernetes/token".path;
    serverAddr = lib.mkIf (!isClusterInit) "https://${clusterInit}.tail2465c3.ts.net:9345";
    cni = lib.mkIf isServer "cilium";
    extraFlags = lib.optionals isServer [
      # "--disable-kube-proxy"
      # "--enable-servicelb"  # cilium has node-ipam for similar features
    ] ++ [
      # "--kubelet-arg=v=4" # Optionally add additional args to rke2
    ];
  };

  boot.kernelModules = [ /*"ip6_tables" "ip6table_filter"*/ "ip6table_mangle" "ip6table_raw" ];

  environment.etc."rancher/rke2/config.yaml".text = ''
    cluster-cidr: "10.42.0.0/16,2001:cafe:42::/56"
    service-cidr: "10.43.0.0/16,2001:cafe:43::/112"
    # https://github.com/coredns/coredns/blob/master/plugin/loop/README.md
    resolv-conf: /run/systemd/resolve/resolv.conf
    node-label:
      - topology.kubernetes.io/zone=${args.zone}
    kubelet-arg: config=${pkgs.writeText "kubelet.config" kubeletConfig}
  '' + lib.optionalString isServer ''
    tls-san:
      - ${config.networking.hostName}.home.lostattractor.net
      - ${config.networking.hostName}.tail2465c3.ts.net
    embedded-registry: true
    etcd-expose-metrics: true
    kube-scheduler-arg:
      - --bind-address=0.0.0.0
    kube-controller-manager-arg:
      - --bind-address=0.0.0.0
  '';

  environment.etc."rancher/rke2/registries.yaml".text = ''
    mirrors:
      docker.io:
      registry.k8s.io:
  '';

  sops.secrets."kubernetes/token" = { };
  sops.secrets.tailscale = { };
}