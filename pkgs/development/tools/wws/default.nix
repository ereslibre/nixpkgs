{ lib, rustPlatform, fetchFromGitHub }:

rustPlatform.buildRustPackage rec {
  pname = "wasm-workers-server";
  version = "1.4.0";

  src = fetchFromGitHub {
    owner = "vmware-labs";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-4jrUmFeHWE6R1K5f2aE7usnS+OETUP5ZwIOZ445UnUA=";
  };

  cargoLock = {
    lockFile = ./Cargo.lock;
    outputHashes = {
      "wax-0.5.0" = lib.fakeSha256;
      "wit-bindgen-gen-core-0.2.0" = lib.fakeSha256;
    };
  };
  postPatch = ''
    ln -s ${./Cargo.lock} Cargo.lock
  '';

  meta = with lib; {
    description = "Develop and run serverless applications on WebAssembly";
    homepage = "https://github.com/vmware-labs/wasm-workers-server";
    license = licenses.asl20;
    maintainers = with maintainers; [ ereslibre ];
  };
}
