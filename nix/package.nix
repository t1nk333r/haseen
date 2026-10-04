# The haseen tree as a Nix package: bin/ and share/haseen, with every command
# wrapped so HASEEN_PATH points at this store path and the tools the CLI and
# the shell call are on PATH.
#
# The real scripts live in libexec/haseen/ and only thin wrappers go in bin/:
# the router (bin/haseen) lists commands by reading the `# haseen:summary`
# headers of the files next to itself, which a makeWrapper wrapper would hide.
{
  lib,
  stdenvNoCC,
  makeWrapper,
  bash,
  coreutils,
  curl,
  findutils,
  gawk,
  git,
  gnugrep,
  gnused,
  jq,
  libnotify,
  procps,
  quickshell,
  util-linux,
}:

let
  runtimeDeps = [
    bash
    coreutils
    curl
    findutils
    gawk
    git
    gnugrep
    gnused
    jq
    libnotify
    procps
    quickshell
    util-linux
  ];
in
stdenvNoCC.mkDerivation {
  pname = "haseen";
  version = lib.trim (builtins.readFile ../share/haseen/VERSION);

  # Only what the installer copies; docs, plans and tests changing must not
  # rebuild the package.
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../bin
      ../share
    ];
  };

  nativeBuildInputs = [ makeWrapper ];
  # patchShebangs rewrites `#!/usr/bin/env bash` against the host inputs.
  buildInputs = [ bash ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/libexec/haseen" "$out/share"
    cp -r share/haseen "$out/share/haseen"
    install -m 0755 bin/haseen* "$out/libexec/haseen/"
    for f in "$out"/libexec/haseen/haseen*; do
        makeWrapper "$f" "$out/bin/''${f##*/}" \
            --set HASEEN_PATH "$out/share/haseen" \
            --prefix PATH : ${lib.makeBinPath runtimeDeps}
    done

    runHook postInstall
  '';

  passthru = { inherit quickshell; };

  meta = {
    description = "Clean, low-resource Hyprland + Quickshell desktop base";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "haseen";
  };
}
