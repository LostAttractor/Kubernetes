{
  description = "ChaosAttractor's NixNAS Server Flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    deploy-rs.url = "github:serokell/deploy-rs";
    deploy-rs.inputs.nixpkgs.follows = "nixpkgs";
    homelab.url = "github:lostattractor/homelab";
    homelab.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { nixpkgs, deploy-rs, ... }@inputs:
    let
      clusterInit = "node0-rke";
    in
    rec {
      # Node@NUC9.home.lostattractor.net
      nixosConfigurations."node@nuc9.home.lostattractor.net" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit inputs clusterInit;
          role = "server";
          zone = "home";
        };
        modules = [
          ./configuration
          (inputs.homelab + "/hardware/kvm/proxmox.nix")
          (inputs.homelab + "/features/network/avahi")
          { services.avahi.allowInterfaces = [ "enp6s18" ]; }
          inputs.sops-nix.nixosModules.sops
          { networking.hostName = "node0-rke"; }
        ];
      };
      # Node@Harvester0.home.lostattractor.net
      nixosConfigurations."node@harvester0.home.lostattractor.net" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit inputs clusterInit;
          zone = "home";
        };
        modules = [
          ./configuration
          ./nvidia.nix
          (inputs.homelab + "/hardware/kvm/kubevirt.nix")
          (inputs.homelab + "/features/network/avahi")
          { services.avahi.allowInterfaces = [ "enp1s0" ]; }
          inputs.sops-nix.nixosModules.sops
          { networking.hostName = "node1-rke"; }
        ];
      };
      # Node@PVE2.home.lostattractor.net
      nixosConfigurations."node@pve2.home.lostattractor.net" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit inputs clusterInit;
          zone = "home";
        };
        modules = [
          ./configuration
          (inputs.homelab + "/hardware/kvm/proxmox.nix")
          (inputs.homelab + "/features/network/avahi")
          { services.avahi.allowInterfaces = [ "enp6s18" ]; }
          inputs.sops-nix.nixosModules.sops
          { networking.hostName = "node2-rke"; }
        ];
      };
      nixosConfigurations."node@lightsail.lostattractor.net" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit inputs clusterInit;
          zone = "ap-northeast-1a";
          exitNode = true;
        };
        modules = [
          ./configuration
          ./specific/sing-box.nix
          (inputs.homelab + "/hardware/ec2")
          ({ lib, ... }: { boot.loader.grub.device = lib.mkForce "/dev/nvme0n1"; })
          inputs.sops-nix.nixosModules.sops
          { networking.hostName = "lightsail"; }
          { networking.nameservers = [ "1.1.1.1" ]; }
        ];
      };
      nixosConfigurations."node@ali.lostattractor.net" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit inputs clusterInit;
          zone = "ali-hk";
          exitNode = true;
        };
        modules = [
          ./configuration
          ./specific/sing-box.nix
          (inputs.homelab + "/hardware/kvm")
          { virtualisation.docker.enable = true; }
          inputs.sops-nix.nixosModules.sops
          { networking.hostName = "ali"; }
          { networking.nameservers = [ "1.1.1.1" ]; }
        ];
      };

      # Deploy-RS Configuration
      deploy = {
        sshUser = "root";
        magicRollback = false;

        nodes."node@nuc9.home.lostattractor.net" = {
          hostname = "node0-rke.home.lostattractor.net";
          profiles.system.path =
            deploy-rs.lib.x86_64-linux.activate.nixos
              nixosConfigurations."node@nuc9.home.lostattractor.net";
        };
        nodes."node@harvester0.home.lostattractor.net" = {
          hostname = "node1-rke.home.lostattractor.net";
          profiles.system.path =
            deploy-rs.lib.x86_64-linux.activate.nixos
              nixosConfigurations."node@harvester0.home.lostattractor.net";
        };
        nodes."node@pve2.home.lostattractor.net" = {
          hostname = "node2-rke.home.lostattractor.net";
          profiles.system.path =
            deploy-rs.lib.x86_64-linux.activate.nixos
              nixosConfigurations."node@pve2.home.lostattractor.net";
        };
        nodes."node@lightsail.lostattractor.net" = {
          hostname = "lightsail.lostattractor.net";
          profiles.system.path =
            deploy-rs.lib.x86_64-linux.activate.nixos
              nixosConfigurations."node@lightsail.lostattractor.net";
        };
        nodes."node@ali.lostattractor.net" = {
          hostname = "ali.lostattractor.net";
          profiles.system.path =
            deploy-rs.lib.x86_64-linux.activate.nixos
              nixosConfigurations."node@ali.lostattractor.net";
        };
      };

      # This is highly advised, and will prevent many possible mistakes
      checks = builtins.mapAttrs (_system: deployLib: deployLib.deployChecks deploy) deploy-rs.lib;

      hydraJobs = with nixpkgs.lib; {
        nixosConfigurations = mapAttrs' (
          name: config: nameValuePair name config.config.system.build.toplevel
        ) nixosConfigurations;
        image = mapAttrs' (
          name: config: nameValuePair name config.config.system.build.image
        ) nixosConfigurations;
      };
    };
}
