{ pkgs, ... }:
{
  home.packages = with pkgs; [
    cargo
    rustc
    rust-analyzer
    nixd
    gcc

  ];
}

# Rust
# Python
# Java/kotlin (minecraft)
# Lua
# Zig
# C
# C++
# R
# Julia
# MATLAB
