import ./make-test-python.nix (
  { pkgs, lib, ... }: let
      testContainerImage = let
        testCDIScript = pkgs.writeShellScriptBin "test-cdi" ''
            # If we exit this script with a 0 exit code, the container sandbox was
            # created successfully.
            exit 0
          '';
      in pkgs.dockerTools.buildImage {
        name = "cdi-test";
        tag = "latest";
        config = {
          Cmd = [ "${testCDIScript}/bin/test-cdi" ];
        };
      };
    in {
    name = "nvidia-container-toolkit";
    meta = with lib.maintainers; {
      maintainers = [ ereslibre ];
    };
    nodes = {
      no-nvidia-gpus = {
        environment.systemPackages = with pkgs; [ jq ];
        hardware.nvidia-container-toolkit.enable = true;
        nixpkgs.config.allowUnfree = true;
      };
      nvidia-one-gpu = { pkgs, ... }: let
        emptyCDISpec = ''
          #! ${pkgs.runtimeShell}
          cat <<CDI_DOCUMENT
            {
              "cdiVersion": "0.5.0",
              "kind": "nvidia.com/gpu",
              "devices": [
                {
                  "name": "all",
                  "containerEdits": {
                    "deviceNodes": [
                      {
                        "path": "/dev/urandom"
                      }
                    ],
                    "hooks": [],
                    "mounts": []
                  }
                }
              ],
              "containerEdits": {
                "deviceNodes": [],
                "hooks": [],
                "mounts": []
              }
            }
          CDI_DOCUMENT
        '';
      in {
        environment.systemPackages = with pkgs; [ jq linuxPackages.nvidia_x11 podman ];
        hardware = {
          nvidia-container-toolkit = {
            enable = true;
            package = pkgs.stdenv.mkDerivation {
              name = "nvidia-ctk-dummy";
              version = "1.0.0";
              phases = "installPhase";
              installPhase = ''
              mkdir -p $out/bin
              cat <<EOF > $out/bin/nvidia-ctk
                ${emptyCDISpec}
              EOF
              chmod +x $out/bin/nvidia-ctk
            '';
            };
          };
          opengl.enable = true;
        };
        nixpkgs.config.allowUnfree = true;
        services.xserver.videoDrivers = ["nvidia"];
        virtualisation.containers.enable = true;
      };
    };
    testScript = ''
      start_all()

      with subtest("Generate the CDI spec (empty) for a machine with no Nvidia GPU"):
        no_nvidia_gpus.wait_for_unit("nvidia-container-toolkit-cdi-generator.service")
        no_nvidia_gpus.succeed("cat /var/run/cdi/nvidia-container-toolkit.json | jq")

      with subtest("Generate the CDI spec for a machine with an Nvidia GPU"):
        nvidia_one_gpu.wait_for_unit("nvidia-container-toolkit-cdi-generator.service")
        print(nvidia_one_gpu.succeed("cat /var/run/cdi/nvidia-container-toolkit.json | jq"))
        nvidia_one_gpu.succeed("podman load < ${testContainerImage}")
        nvidia_one_gpu.succeed("podman run --pull=never --device=nvidia.com/gpu=all cdi-test:latest")
    '';
  }
)
