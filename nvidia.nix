{ pkgs, ... }:
{
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia.open = false;

  hardware.nvidia-container-toolkit.enable = true;

  environment.systemPackages = with pkgs; [
    runc
    nvidia-container-toolkit
    nvtopPackages.nvidia
  ];

  system.activationScripts.script.text = ''
    ln -sf ${pkgs.writeText "config.toml.tmpl" ''
      {{ template "base" . }}

      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes."nvidia"]
        runtime_type = "io.containerd.runc.v2"

      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes."nvidia".options]
        BinaryName = "/run/current-system/sw/bin/nvidia-container-runtime.cdi"
        SystemdCgroup = true
    ''} /var/lib/rancher/rke2/agent/etc/containerd/config.toml.tmpl
  '';

  nixpkgs.config.allowUnfree = true;
}