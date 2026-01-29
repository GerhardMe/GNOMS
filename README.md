# Gerhard's NixOS Management System (GNOMS)

    [~]❯ neofetch
                       ▐▌                     gg@gnoms
                       ██                     ------
                      ▟██▙                    OS: NixOS
                     ▟████▙                   Host: ThinkPad T480
                   ▄███▀▀███▄                 Kernel: Linux 6.12.43
                 ▄████▚███████▄               Uptime: yes
               ▄██████▞█▄▗██████▄             Packages: 5699 (nix-system), 5071 (nix-user)
           ▄▄██████████▄▄██████████▄▄         Shell: fish 4.0.2
    ▄▄▄▄████████████████████████████████▄▄▄▄  Display: > 180p
               ▜▐▐            ▌▌▛             DE: none+awesome
               ▐▐   ▞▚    ▞▚   ▌▌             WM: awesome (X11)
               ▐                ▌             Icons: Papirus-Dark [GTK]
                 ▜▄ ▄▆▀▆▆▀▆▄ ▄▛               Terminal: WezTerm
                  ▜████▄▄████▛                CPU: Intel i7-8550U @ 4.000GHz
                   ▜████████▛                 GPU: Intel UHD Graphics
                    ▜██████▛                  eGPU: NVIDIA GeForce RTX 2080
                     ▜████▛                   Memory: can't afford
                      ▜██▛
                       ▜▛                     . ݁₊ ⊹ . ݁ ⟡ ݁ . ⊹ ₊ ݁.

A flake-based NixOS manager for dotfiles, scripts, configurations and more!

## Architecture

A system of 4 parts:

- **/dotfiles :** Everything rice and window manager specific.

- **/nixos :** Everything NixOS specific, and the main reconfigure script.

- **/personal :** The stuff you want to change first.

- **/scripts :** Any custom scripts for the system.

## Main script: `reconfigure.sh`

One script to rule them all:

- `reload` : Syncs config files (dotfiles, scripts), restarts AwesomeWM if possible.

- `rebuild` : Copies the Nix flake to `/etc/nixos`, runs `nixos-rebuild switch`, then reloads.

- `update` : Runs `nix flake update` to update all packages to the latest version.

- `upgrade` : Combines `update` and `rebuild`.

## Bootstrap Installation

To install this config on any NixOS system:

```bash
git clone https://github.com/GerhardMe/GNOMS ~/GNOMS
cd ~/GNOMS/nixos
./reconfigure.sh rebuild
```

It's that simple!

(Want to read more? [Click me!](https://gerhard.page/projects/proj/gnoms))
