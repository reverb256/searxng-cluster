{
  description = "SearXNG search cluster with Docker Compose and K8s manifests";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      kubernetesModules.default = import ./kubernetes/module.nix;

      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          docker-compose
          kubectl
          jq
        ];

        shellHook = ''
          echo "searxng-cluster dev shell"
        '';
      };
    };
}
