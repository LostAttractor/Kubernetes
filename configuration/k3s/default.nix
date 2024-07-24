{
  config,
  lib,
  clusterInit,
  ...
}:
let
  isClusterInit = config.networking.hostName == clusterInit;
in
{
  networking.firewall.allowedTCPPorts = [
    6443 # k3s: required so that pods can reach the API server (running on port 6443 by default)
    2379 # k3s, etcd clients: required if using a "High Availability Embedded etcd" configuration
    2380 # k3s, etcd peers: required if using a "High Availability Embedded etcd" configuration
  ];
  networking.firewall.allowedUDPPorts = [
    8472 # k3s, flannel: required if using multi-node for inter-node networking
  ];

  services.k3s = {
    enable = true;
    role = "server"; # Or "agent" for worker only nodes
    clusterInit = isClusterInit;
    serverAddr = lib.mkIf (!isClusterInit) "https://${clusterInit}.home.lostattractor.net:6443";
    tokenFile = lib.mkIf (!isClusterInit) config.sops.secrets."kubernetes/token".path;
    extraFlags = toString [
      "--tls-san ${config.networking.hostName}.home.lostattractor.net"
      # "--kubelet-arg=v=4" # Optionally add additional args to k3s
    ];
  };

  sops.secrets."kubernetes/token" = { };
}
