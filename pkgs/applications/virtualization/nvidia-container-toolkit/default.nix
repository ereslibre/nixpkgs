{ lib
, stdenv
, glibc
, fetchFromGitHub
, makeWrapper
, buildGoModule
, linkFarm
, writeShellScript
, formats
, containerRuntimePath
, configTemplate
, configTemplatePath ? null
, libnvidia-container
, cudaPackages
}:

assert configTemplate != null -> (lib.isAttrs configTemplate && configTemplatePath == null);
assert configTemplatePath != null -> (lib.isStringLike configTemplatePath && configTemplate == null);

let
  isolatedContainerRuntimePath = linkFarm "isolated_container_runtime_path" [
    {
      name = "runc";
      path = containerRuntimePath;
    }
  ];
  warnIfXdgConfigHomeIsSet = writeShellScript "warn_if_xdg_config_home_is_set" ''
    set -eo pipefail

    if [ -n "$XDG_CONFIG_HOME" ]; then
      echo >&2 "$(tput setaf 3)warning: \$XDG_CONFIG_HOME=$XDG_CONFIG_HOME$(tput sgr 0)"
    fi
  '';

  configToml = if configTemplatePath != null then configTemplatePath else (formats.toml { }).generate "config.toml" configTemplate;
in
buildGoModule rec {
  pname = "nvidia-container-toolkit";
  version = "1.15.0-rc.1";

  src = fetchFromGitHub {
    owner = "ereslibre";
    repo = pname;
    rev = "5c2d576e0f754ec102c7d41392152f65beb00d64";
    hash = "sha256-8Wie9d0NhzCcazp7TkExQEuohICjnNn/mJ51qphqerE=";
  };

  vendorHash = null;

  prePatch = let
    ldconfig = "${stdenv.cc.libc.bin}/bin/ldconfig";
  in ''
    substituteInPlace cmd/nvidia-ctk/hook/update-ldcache/update-ldcache.go \
      --replace /sbin/ldconfig '${ldconfig}'
  '';

  ldflags = [ "-extldflags=-Wl,-z,lazy" "-s" "-w" ];

  nativeBuildInputs = [
    cudaPackages.autoAddOpenGLRunpathHook
    makeWrapper
  ];

  checkFlags =
    let
      skippedTests = [
        # Disable tests executing nvidia-container-runtime command.
        "TestGoodInput"
        "TestDuplicateHook"
      ];
    in
    [ "-skip" "${builtins.concatStringsSep "|" skippedTests}" ];

  postInstall = ''
    mkdir -p $out/etc/nvidia-container-runtime

    # nvidia-container-runtime invokes docker-runc or runc if that isn't
    # available on PATH.
    #
    # Also set XDG_CONFIG_HOME if it isn't already to allow overriding
    # configuration. This in turn allows users to have the nvidia container
    # runtime enabled for any number of higher level runtimes like docker and
    # podman, i.e., there's no need to have mutually exclusivity on what high
    # level runtime can enable the nvidia runtime because each high level
    # runtime has its own config.toml file.
    wrapProgram $out/bin/nvidia-container-runtime \
      --run "${warnIfXdgConfigHomeIsSet}" \
      --prefix PATH : ${isolatedContainerRuntimePath}:${libnvidia-container}/bin \
      --set-default XDG_CONFIG_HOME $out/etc

    cp ${configToml} $out/etc/nvidia-container-runtime/config.toml

    substituteInPlace $out/etc/nvidia-container-runtime/config.toml \
      --subst-var-by glibcbin ${lib.getBin glibc}

    ln -s $out/bin/nvidia-container-runtime-hook $out/bin/nvidia-container-toolkit

    wrapProgram $out/bin/nvidia-container-toolkit \
      --add-flags "-config ${placeholder "out"}/etc/nvidia-container-runtime/config.toml"
  '';

  meta = with lib; {
    homepage = "https://gitlab.com/nvidia/container-toolkit/container-toolkit";
    description = "NVIDIA Container Toolkit";
    license = licenses.asl20;
    platforms = platforms.linux;
    maintainers = with maintainers; [ cpcloud ];
  };
}
