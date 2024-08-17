import ./make-test-python.nix (
  {
    pkgs,
    lib,
    system,
    ...
  }:
  let
    unfreeAndInsecurePkgs = import ../.. {
      inherit system;
      config = {
        allowUnfree = true;
        permittedInsecurePackages = [ "openssl-1.1.1w" ];
      };
    };
    testContainerImage =
      let
        testCDIScript = pkgs.writeShellScriptBin "test-cdi" ''
          die() {
            echo "$1"
            exit 1
          }

          check_file_referential_integrity() {
            echo "checking $file referential integrity"
            files=$(set -o pipefail && \
                    ${pkgs.glibc.bin}/bin/ldd "$1" | \
                    ${lib.getExe pkgs.gnugrep} '=>' | \
                    ${lib.getExe pkgs.gnused} "s/.* => //" | \
                    ${lib.getExe pkgs.gnused} "s/ (.*//") || exit 1

            for file in $files; do
              if [ ! -f "$file" ]; then
                die "$file does not exist in the container filesystem"
              fi
            done
          }

          check_directory_referential_integrity() {
            ${lib.getExe pkgs.findutils} "$1" -type f -print0 | while read -d $'\0' file; do
              if [[ $(${lib.getExe pkgs.file} "$file" | ${lib.getExe pkgs.gnugrep} ELF) ]]; then
                check_file_referential_integrity "$file" || exit 1
              else
                echo "skipping $file"
              fi
            done
          }

          check_directory_referential_integrity "/usr/bin" || exit 1
          check_directory_referential_integrity "${pkgs.addDriverRunpath.driverLink}" || exit 1
          check_directory_referential_integrity "/usr/local/nvidia" || exit 1
        '';
      in
      pkgs.dockerTools.buildImage {
        name = "cdi-test";
        tag = "latest";
        config = {
          Cmd = [ "${testCDIScript}/bin/test-cdi" ];
          Env = [
            "LD_LIBRARY_PATH=${unfreeAndInsecurePkgs.linuxPackages.nvidia_x11}/lib:${lib.getLib unfreeAndInsecurePkgs.openssl_1_1}/lib"
          ];
        };
        copyToRoot = (
          with pkgs.dockerTools;
          [
            usrBinEnv
            binSh
          ]
        );
      };
  in
  {
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
      nvidia-one-gpu =
        { pkgs, ... }:
        let
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
        in
        {
          virtualisation.diskSize = 10240;
          environment.systemPackages = with pkgs; [
            jq
            podman
          ];
          hardware = {
            nvidia-container-toolkit = {
              enable = true;
              package = pkgs.stdenv.mkDerivation {
                name = "nvidia-ctk-dummy";
                version = "1.0.0";
                dontUnpack = true;
                dontBuild = true;
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
          services.xserver.videoDrivers = [ "nvidia" ];
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
        nvidia_one_gpu.succeed("cat /var/run/cdi/nvidia-container-toolkit.json | jq")
        nvidia_one_gpu.succeed("podman load < ${testContainerImage}")
        print(nvidia_one_gpu.succeed("podman run --pull=never --device=nvidia.com/gpu=all -v /run/opengl-driver:/run/opengl-driver:ro cdi-test:latest"))
    '';
  }
)
