{ rustPlatform, fetchFromGitHub, lib, python, cmake, llvmPackages, clang, stdenv, darwin, v8 }:

rustPlatform.buildRustPackage rec {
  pname = "wasmtime";
  version = "0.32.1";

  src = fetchFromGitHub {
    owner = "bytecodealliance";
    repo = pname;
    rev = "v${version}";
    sha256 = "sha256-yWi4bz+DvTMy/Krt6uqg8M1Keah2ynEvgnupiBPahiY";
    fetchSubmodules = true;
  };

  cargoSha256 = "sha256-IXrE1XVZUnyCbOcC0eEZKtI97YRA9Nap3u4tqcbEKf8";

  # This environment variable is required so that when wasmtime tries
  # to run tests by using the rusty_v8 crate, it does not try to
  # download a static v8 build from the Internet, what would break
  # build hermetism.
  RUSTY_V8_ARCHIVE = "${v8}/lib/libv8.a";

  patches = [
    ./patches/remove-failing-test.patch
  ];

  doCheck = true;

  meta = with lib; {
    description = "Standalone JIT-style runtime for WebAssembly, using Cranelift";
    homepage = "https://github.com/bytecodealliance/wasmtime";
    license = licenses.asl20;
    maintainers = [ maintainers.matthewbauer ];
    platforms = platforms.unix;
  };
}
