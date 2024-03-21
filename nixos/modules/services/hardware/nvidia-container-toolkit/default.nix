{ config, lib, pkgs, ... }:

{

  options = {

    hardware.nvidia-container-toolkit = {
      enable = lib.mkOption {
        default = false;
        type = lib.types.bool;
        description = lib.mdDoc ''
        Enable dynamic CDI configuration for NVidia devices by running
        nvidia-container-toolkit on boot.
      '';
      };

      mount-nvidia-binaries = mkOption {
        default = true;
        type = types.bool;
        description = lib.mdDoc ''
            Mount binaries nvidia-smi, nvidia-cuda-mps-control, nvidia-cuda-mps-server, nvidia-debugdump, nvidia-powerd and nvidia-ctk on containers.
          '';
      };

      mount-nvidia-docker-1-directories = mkOption {
        default = true;
        type = types.bool;
        description = lib.mdDoc ''
            Mount nvidia-docker-1 directories on containers: /usr/local/nvidia/lib and /usr/local/nvidia/lib64.
          '';
      };

    };

  };

  config = {

    systemd.services.nvidia-container-toolkit-cdi-generator = lib.mkIf config.hardware.nvidia-container-toolkit.enable {
      description = "Container Device Interface (CDI) for Nvidia generator";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-udev-settle.service" ];
      serviceConfig = {
        RuntimeDirectory = "cdi";
        RemainAfterExit = true;
        ExecStart =
          let
            script = pkgs.callPackage ./cdi-generate.nix {
              inherit (config.hardware.nvidia-container-toolkit)
                mount-nvidia-binaries
                mount-nvidia-docker-1-directories;
              nvidia-driver = config.hardware.nvidia.package;
            };
          in
          lib.getExe script;
        Type = "oneshot";
      };
    };

  };

}
