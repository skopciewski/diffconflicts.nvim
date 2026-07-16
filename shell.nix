let
  pkgs = import <nixpkgs> { };

  projectPackages = with pkgs; [
    neovim-unwrapped
    lua
    stylua
  ];

  containerScripts = pkgs.project_opencode_helpers_builder {
    inherit
      projectPackages
      pkgs
      ;
    projectContainer = "diffconflicts-env";
    currentDir = toString ./.;
  };
in
pkgs.mkShell {
  packages = with pkgs; [
    containerScripts
  ];
}
