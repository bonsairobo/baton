{
  description = "NixOS environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      devShell.${system} =
        with pkgs;
        mkShell {
          buildInputs = [
            gleam
            erlang
            pkg-config
            rebar3
          ];
        };
    };
}
