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
  systemd.services.systemd-sysctl.restartTriggers = [ "/etc/sysctl.d/99-zzz-override_cilium.conf" ];

  services.rke2 = {
    enable = true;
    role = role; # Or "agent" for worker only nodes
    tokenFile = config.sops.secrets."kubernetes/token".path;
    serverAddr = lib.mkIf (!isClusterInit) "https://${clusterInit}.home.lostattractor.net:9345";
    # cni = lib.mkIf isServer "cilium";
    cni = lib.mkIf isServer "none";
    extraFlags = lib.optionals isServer [
      "--disable-kube-proxy"
      # "--enable-servicelb"  # cilium has node-ipam for similar features
    ] ++ [
      # "--kubelet-arg=v=4" # Optionally add additional args to rke2
    ];
  };

  # kubelet.kubeconfig or kube-proxy.kubeconfig

  # systemd.services."rke2-${config.services.rke2.role}" = {
  #   after = [ "tailscaled.service" "tailscaled-autoconnect.service" ];
  #   requires = [ "tailscaled.service" "tailscaled-autoconnect.service" ];
  #   serviceConfig = {
  #     ExecStartPre = [
  #       (pkgs.writeScript "setup-tailscale-ip.sh" (''
  #         #! ${pkgs.runtimeShell}
  #         mkdir -p /etc/rancher/rke2/config.yaml.d
  #         # echo "node-ip: $(${pkgs.tailscale}/bin/tailscale ip -4),$(${pkgs.iproute2}/bin/ip -6 addr show scope global | grep inet6 | ${pkgs.gawk}/bin/awk '{print $2}' | cut -d/ -f1 | head -n 1)" > /etc/rancher/rke2/config.yaml.d/tailscale.yaml
  #         echo "node-ip: $(${pkgs.tailscale}/bin/tailscale ip | paste -sd,)" > /etc/rancher/rke2/config.yaml.d/tailscale.yaml
  #         echo "node-external-ip: $(${pkgs.iproute2}/bin/ip -6 addr show scope global | grep inet6 | ${pkgs.gawk}/bin/awk '{print $2}' | cut -d/ -f1 | head -n 1)" >> /etc/rancher/rke2/config.yaml.d/tailscale.yaml
  #       '' + lib.optionalString isServer ''
  #         echo "advertise-address: $(${pkgs.tailscale}/bin/tailscale ip -4)" >> /etc/rancher/rke2/config.yaml.d/tailscale.yaml
  #       ''))
  #     ];
  #     ExecStartPost = [
  #       (pkgs.writeScript "setup-tailscale-subnet-router.sh" ''
  #         #! ${pkgs.runtimeShell}
  #         ${pkgs.tailscale}/bin/tailscale set --advertise-routes=$(${pkgs.kubectl}/bin/kubectl --server=https://${clusterInit}.tail2465c3.ts.net:6443 --kubeconfig=/var/lib/rancher/rke2/agent/kubelet.kubeconfig get nodes $(${pkgs.nettools}/bin/hostname) -o jsonpath='{.spec.podCIDRs[*]}' | sed 's/ /,/g')
  #       '')
  #     ];
  #   };
  # };

  environment.variables.KUBECONFIG = lib.mkIf isServer "/etc/rancher/rke2/rke2.yaml";
  environment.systemPackages = with pkgs; [ kubectl ];

  boot.kernelModules = [ "ip6table_mangle" "ip6table_raw" ];

  environment.etc."rancher/rke2/config.yaml".text = lib.optionalString isServer ''
    # Server
    # https://github.com/kubernetes/kubernetes/issues/111671
    kube-apiserver-arg:
      - "bind-address=::"
    # 需要将默认地址簇写在前面, 并且 API Server 的 Advertise Address 需要和默认地址簇相同
    cluster-cidr: "2001:cafe:42::/56"
    service-cidr: "2001:cafe:43::/112"
    tls-san:
      - ${config.networking.hostName}.home.lostattractor.net
    embedded-registry: true
  '' + ''
    # Client
    # https://github.com/coredns/coredns/blob/master/plugin/loop/README.md
    resolv-conf: /etc/kubernetes-resolv.conf
    node-label:
      - topology.kubernetes.io/zone=${args.zone}
    kubelet-arg:
      - config=${pkgs.writeText "kubelet.config" kubeletConfig}
  '' + lib.optionalString (args ? taint) ''
    node-taint:
      - "${args.taint}"
  '';

  environment.etc."rancher/rke2/registries.yaml".text = ''
    mirrors:
      "*":
  '';

  system.activationScripts.applyKubernetesMainfest = {
    deps = [ "var" ];
    text = ''
      mkdir -p /var/lib/rancher/rke2/server/manifests
      cp -r ${./mainfests}/* /var/lib/rancher/rke2/server/manifests
    '';
  };

  sops.secrets."kubernetes/token" = { };
  sops.secrets.tailscale = { };

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
  # # will "loose" work? Probably not
  # # networking.firewall.checkReversePath = lib.mkForce false;  # Conflict with cilium
  # # networking.firewall.logReversePathDrops = true;

  # # cilium vxlan 模式下只需要 vxlan 端口可达, 但是有些 daemonset 可能会直接使用 hostNetwork / hostPort
  # networking.firewall.trustedInterfaces = [ "cilium_wg0" "lxc*" ];
}