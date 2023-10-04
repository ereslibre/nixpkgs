{ lib, rustPlatform, fetchFromGitHub, openssl, pkg-config }:

rustPlatform.buildRustPackage rec {
  pname = "wasm-workers-server";
  version = "1.4.0";

  src = fetchFromGitHub {
    owner = "ereslibre";
    repo = pname;
    rev = "2885886747b9ca2500fe5e7d0092e31b9010f918";
    hash = "sha256-2FIR29AiIK7NOfGvR/xu1lQjUYW3SYkmvLOqcwVbSfY=";
  };

  doCheck = false;

  buildInputs = [ openssl ];
  nativeBuildInputs = [ pkg-config ];

  cargoLock = {
    lockFile = ./Cargo.lock;
    allowBuiltinFetchGit = false;
    outputHashes = {
      "wax-0.5.0" = lib.fakeSha256;
      "wit-bindgen-gen-core-0.2.0" = lib.fakeSha256;
    };
  };

  postPatch = ''
    ln -sf ${./Cargo.lock} Cargo.lock
  '';

  meta = with lib; {
    description = "Develop and run serverless applications on WebAssembly";
    homepage = "https://github.com/vmware-labs/wasm-workers-server";
    license = licenses.asl20;
    maintainers = with maintainers; [ ereslibre ];
  };
}
