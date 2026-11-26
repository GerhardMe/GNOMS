{ pkgs, config, lib, ... }:

let
  # user/ holds your profile: ./user when running from a synced copy in
  # /etc/nixos, ../user when evaluating inside the repo.
  profile = import (if builtins.pathExists ./user
    then ./user/userprofile.nix
    else ../user/userprofile.nix);
  userprograms = import (if builtins.pathExists ./user
    then ./user/userprograms.nix
    else ../user/userprograms.nix) { inherit pkgs; };

  rootTriggerScript = pkgs.writeScript "log-hw-event" ''
    #!${pkgs.runtimeShell}
    touch "/tmp/hw-trigger-$(date +%s)-$1"
  '';

  # Lid debounce: the T480 lid sensor sometimes reports closed for a second
  # and reopens (2026-09-09: four bounces in ten minutes, each one a full
  # suspend cycle). acpid calls this with "button/lid LID close|open"; on
  # close we wait lidDebounceSec and only sleep if the lid is still closed.
  # Going through logind's D-Bus sleep methods keeps logind's sleep
  # inhibitors (awake.service) in charge. systemctl is deliberately NOT used:
  # run as root it refuses to sleep while any other user is logged in
  # ("User gg is logged in on tty2"), and the autologin session always counts
  # (2026-10-01: every lid close silently refused since the Sep 09 rebuild).
  lidDebounceSec = 5;
  lidDebounceScript = pkgs.writeShellScript "lid-debounce" ''
    # acpid passes the event either as one string or as separate words.
    case "$*" in *close*) ;; *) exit 0 ;; esac
    ${pkgs.coreutils}/bin/sleep ${toString lidDebounceSec}
    ${pkgs.gnugrep}/bin/grep -qs closed /proc/acpi/button/lid/*/state || exit 0
    if [ "$(${pkgs.coreutils}/bin/cat /sys/class/power_supply/AC/online 2>/dev/null)" = "1" ]; then
      exec ${pkgs.systemd}/bin/busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager Suspend b false
    else
      exec ${pkgs.systemd}/bin/busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager SuspendThenHibernate b false
    fi
  '';

  # systemd-sleep runs this with "pre|post <verb>" around every sleep stage;
  # during suspend-then-hibernate it fires per stage and SYSTEMD_SLEEP_ACTION
  # says which one (suspend, hibernate, suspend-after-failed-hibernate).
  sleepTraceHook = pkgs.writeShellScript "sleep-trace" ''
    PATH=${pkgs.coreutils}/bin
    temp=0
    for z in /sys/class/thermal/thermal_zone*/temp; do
      t=$(cat "$z" 2>/dev/null) || continue
      (( t > temp )) && temp=$t
    done
    echo "$(date '+%F %T') $1 $2 stage=''${SYSTEMD_SLEEP_ACTION:--}" \
      "bat=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null)%" \
      "temp=$((temp / 1000))C" >> /var/log/sleep-trace.log
    sync /var/log/sleep-trace.log
  '';
in {

  # ------------------------------------------------------------------------------------------
  # ----------------------------------------- CONFIG -----------------------------------------
  # ------------------------------------------------------------------------------------------

  imports = [ ./hardware-configuration.nix ];
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  programs.command-not-found.enable = false;
  networking.hostName = profile.hostname;

  # ENV varriables
  environment.variables = {
    TERMINAL = profile.terminal;
    EDITOR = profile.editor;
    BROWSER = profile.browser;
  };
  systemd.user.settings.Manager = {
    ImportEnvironment = "DISPLAY XAUTHORITY";
  };
  xdg.mime = {
    enable = true;
    defaultApplications = {
      # file manager
      "inode/directory" = "Thunar.desktop";
      # HTML files
      "text/html" = "firefox.desktop";
      # URL handlers
      "x-scheme-handler/http" = "firefox.desktop";
      "x-scheme-handler/https" = "firefox.desktop";
    };
  };

  # ------------------------------------------------------------------------------------------
  # ----------------------------------------- BOOT -------------------------------------------
  # ------------------------------------------------------------------------------------------

  boot.loader.systemd-boot.enable = false;
  boot.loader = {
    # dualboot = false: GRUB owns the ESP and NVRAM like standard NixOS.
    # dualboot = true:  contained instance — GRUB installs into /EFI/GNOMS
    #                   (via efiBootloaderId below) with --no-nvram, and
    #                   extraInstallCommands registers a separate firmware
    #                   entry without touching the existing OS's boot order.
    efi.canTouchEfiVariables = !profile.dualboot;
    grub = {
      enable = true;
      efiSupport = true;
      enableCryptodisk = true;
      device = "nodev";
      configurationLimit = 5;
      useOSProber = profile.dualboot;
      extraInstallCommands = lib.optionalString profile.dualboot ''
        # Contained instance: grub-install above ran with --no-nvram, leaving
        # NixOS's GRUB at /EFI/<distro>-boot on the ESP. Copy it under a stable
        # path and register a "GNOMS" firmware entry --create-only (never
        # reorders the boot menu). Idempotent: guarded by a fixed-string match
        # on the loader path in `efibootmgr -v`.
        mkdir -p /boot/EFI/GNOMS
        cp -f /boot/EFI/${config.system.nixos.distroName}-boot/grubx64.efi /boot/EFI/GNOMS/grubx64.efi
        esp_dev="$(${pkgs.util-linux}/bin/findmnt -n -o SOURCE /boot)"
        esp_part="$(cat "/sys/class/block/$(basename "$esp_dev")/partition")"
        esp_disk="$(${pkgs.util-linux}/bin/lsblk -no PKNAME "$esp_dev")"
        if ! ${pkgs.efibootmgr}/bin/efibootmgr -v | grep -qF '\EFI\GNOMS'; then
          ${pkgs.efibootmgr}/bin/efibootmgr --create-only --quiet \
            --label GNOMS --disk "/dev/$esp_disk" --part "$esp_part" \
            --loader '\EFI\GNOMS\grubx64.efi'
        fi
      '';
    };
    timeout = profile.boot_timeout;
  };
  boot.blacklistedKernelModules =
    [ "nouveau" "nvidiafb" ]; # to get eGPU to work
  boot.extraModprobeConfig = ''
    options nvidia-drm modeset=1
    options thinkpad_acpi fan_control=1
  '';
  # Swap is >= RAM (24 GB) so a full memory image fits when hibernating.
  swapDevices = [{
    device = "/var/lib/swapfile";
    size = 32 * 1024;
  }];

  # --- Hibernate / resume ---
  # The swapfile lives on the LUKS-encrypted ext4 root, so any hibernation
  # image is encrypted at rest. initrd already unlocks that device for root;
  # resumeDevice points the kernel at it. resume_offset is machine-generated
  # (where the swapfile physically lands on disk — never a user setting);
  # it must be updated whenever the swapfile is (re)created:
  #   sudo filefrag -v /var/lib/swapfile | awk 'NR==4 {print $4+0}'
  boot.resumeDevice = config.fileSystems."/".device;
  boot.kernelParams = [ "resume_offset=589824" ];

  # ------------------------------------------------------------------------------------------
  # ----------------------------------------- POWER ----------------------------------------
  # ------------------------------------------------------------------------------------------

  # Lid close / power key: suspend to RAM now (instant resume), then after
  # HibernateDelaySec of sleeping, wake briefly and hibernate to disk so a
  # forgotten laptop ends up at zero battery draw instead of dying flat.
  # Inhibitors still win, so "server mode" (awake.service) keeps it awake.
  #
  # The lid itself is NOT handled by logind (it acts on the very first
  # "closed" edge, and the sensor bounces). acpid + lidDebounceScript do it:
  # on battery -> suspend-then-hibernate, on AC -> plain suspend, and only
  # if the lid has stayed closed for lidDebounceSec.
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
    HandlePowerKey = "suspend-then-hibernate";
  };
  services.acpid = {
    enable = true;
    lidEventCommands = "${lidDebounceScript} \"$@\"";
  };
  systemd.sleep.settings.Sleep = {
    HibernateDelaySec = "1h";
    HibernateOnACPower = "no"; # on AC (eGPU dock) stay in cheap S3; only hibernate on battery
  };

  # Keep the 32 GB swap mostly empty so a hibernation image always fits, and
  # spare the SSD writes. 24 GB RAM means real swap pressure is rare anyway.
  boot.kernel.sysctl."vm.swappiness" = 10;

  # Sleep trace: one line per sleep stage in /var/log/sleep-trace.log, synced
  # to disk before the machine goes down. The journal loses its last minutes
  # on a hang (2026-11-23: died somewhere in suspend-then-hibernate, journal
  # ends at "suspend entry"); the last line here shows which stage hung.
  environment.etc."systemd/system-sleep/sleep-trace".source = sleepTraceHook;

  # ------------------------------------------------------------------------------------------
  # ----------------------------------------- USER -----------------------------------------
  # ------------------------------------------------------------------------------------------

  users.users.${profile.username} = {
    isNormalUser = true;
    extraGroups = [ "networkmanager" "wheel" "dialout" "audio" "jackaudio" ];
    shell = pkgs.fish;
    subUidRanges = [{ startUid=100000; count=65536;}];
    subGidRanges = [{ startGid=100000; count=65536;}];
  };
  programs.fish.enable = true;

  # Language and locale
  time.timeZone = profile.timezone;
  i18n.defaultLocale = profile.locale;
  i18n.extraLocaleSettings = {
    LC_ADDRESS = profile.locale;
    LC_IDENTIFICATION = profile.locale;
    LC_MEASUREMENT = profile.locale;
    LC_MONETARY = profile.locale;
    LC_NAME = profile.locale;
    LC_NUMERIC = profile.locale;
    LC_PAPER = profile.locale;
    LC_TELEPHONE = profile.locale;
    LC_TIME = profile.locale;
  };

  # ------------------------------------------------------------------------------------------
  # --------------------------------------- PERIFERALS ---------------------------------------
  # ------------------------------------------------------------------------------------------

  # Inverse tutchpad scolling. No middle-click emulation: left and right
  # pressed together stay left and right (games read them as two buttons),
  # instead of turning into a middle click.
  services.libinput = {
    enable = true;
    touchpad.naturalScrolling = true;
    touchpad.middleEmulation = false;
    mouse.middleEmulation = false;
  };

  # Keyboard layout
  console.keyMap = profile.keyboard_layout;
  services.xserver.xkb = {
    layout = profile.keyboard_layout;
    options = "lv3:ralt_switch";
  };

  # ------------------------------------------------------------------------------------------
  # ------------------------------------ DISPLAY MANAGER -------------------------------------
  # ------------------------------------------------------------------------------------------

  services = {
    xserver = {
      enable = true;
      windowManager.awesome = {
        enable = true;
        luaModules = with pkgs.luaPackages; [
          luarocks # is the package manager for Lua modules
          luadbi-mysql # Database abstraction layer
        ];
      };
    };

    displayManager = {
      sddm.enable = true;
      defaultSession = "none+awesome";
      autoLogin.enable = true;
      autoLogin.user = profile.username;
    };
  };
  programs.i3lock.enable = true;

  # ------------------------------------------------------------------------------------------
  # ------------------------------------------ SOUND -----------------------------------------
  # ------------------------------------------------------------------------------------------

  # Sound
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # Bluetooth
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  environment.etc."wireplumber/bluetooth.lua.d/51-bluez-config.lua".text =
    "	bluez_monitor.properties = {\n		[\"bluez5.enable-sbc-xq\"] = true,\n		[\"bluez5.enable-msbc\"] = true,\n		[\"bluez5.enable-hw-volume\"] = true,\n		[\"bluez5.headset-roles\"] = \"[ hsp_hs hsp_ag hfp_hf hfp_ag ]\"\n	}\n";

  # ------------------------------------------------------------------------------------------
  # ---------------------------------------- NETWORK -----------------------------------------
  # ------------------------------------------------------------------------------------------

  # Networking protocols
  networking.networkmanager.enable = true; # Enable networking
  services.openssh = {
    enable = true;
    ports = [ 34826 ];
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PubkeyAuthentication = true;
      AuthenticationMethods = "publickey";

      MaxAuthTries = 3;
      LoginGraceTime = "30s";
      MaxStartups = "10:30:100";
    };
  };
  services.printing = {
    enable = true;
    drivers = [ pkgs.brlaser ];
  };
  services.avahi = {
  enable = true;
  nssmdns4 = true;
};
  networking.modemmanager.enable = true;
  systemd.services.ModemManager = {
    enable = pkgs.lib.mkForce true;
    wantedBy = [ "multi-user.target" "network.target" ];
    restartIfChanged = false; # a rebuild still restarts it when polkit changes (upstream Requires=polkit)
    serviceConfig = {
      # SIGTERM only ModemManager itself: by default mbim-proxy is killed with it,
      # so MM can't disable the modem cleanly, hangs until SIGKILL, and the modem
      # is left wedged (the next MM can't probe it; 4G is gone until a reboot).
      KillMode = "mixed";
      TimeoutStopSec = 10;
    };
    environment = {
      MM_DEBUG = "1";
    };
  };
  services.fwupd.enable = true;
  networking.firewall = {
    enable = true;
    # Syncthing:
    allowedTCPPorts = [
      # 8384
      22000
      53317 # localsend
      4321
    ]; # 22000 TCP and/or UDP for sync traffic & 8384 for remote access to GUI
    allowedUDPPorts = [ 22000 21027 53317]; # 21027/UDP for discovery
    # SSH:
    extraInputRules = ''
      tcp dport 34826 ct state new limit rate 30/minute accept
    '';
  };

  # ------------------------------------------------------------------------------------------
  # ----------------------------------------- SECURITY ---------------------------------------
  # ------------------------------------------------------------------------------------------

  security.polkit.enable = true; # managing user premitions
  security.sudo.extraRules = [{
    users = [ profile.username ];
    commands = [
      {
        command = "${pkgs.systemd}/bin/systemctl start sshd";
        options = [ "NOPASSWD" ]; # Not shure if nessesary
      }
      {
        command = "${pkgs.systemd}/bin/systemctl stop sshd";
        options = [ "NOPASSWD" ]; # Not shure if nessesary
      }
      {
        command = "${pkgs.coreutils}/bin/tee /proc/acpi/ibm/fan";
        options = [ "NOPASSWD" ];
      }
    ];
  }];
  programs.dconf.enable = true; # somthing, something, keys...
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  # ------------------------------------------------------------------------------------------
  # ----------------------------------------- GRAPHICS ---------------------------------------
  # ------------------------------------------------------------------------------------------

  hardware.graphics.enable32Bit = true; # Steam support
  services.picom = {
    enable = true;
    settings = {
      vsync = true;
      backend = "glx";
      blur-method = "dual_kawase";
      blur-strength = 3;
      blur-background = true;
      blur-background-frame = false;
      blur-background-exclude = [ "_NET_WM_WINDOW_TYPE@:32a *= '_NET_WM_WINDOW_TYPE_DOCK'" ];
    };
  };
  hardware.graphics.enable = true;
  services.xserver.videoDrivers = [ "modesetting" ];

  # ------------------------------------------------------------------------------------------
  # ---------------------------------------- EGPU --------------------------------------------
  # ------------------------------------------------------------------------------------------

  specialisation = let
    # The eGPU's PCI bus depends on how it is plugged in (the dock adds bridges),
    # and PRIME needs the exact bus ID, so each topology gets its own boot entry.
    egpu = name: label: nvidiaBusId: {
      system.nixos.label = label;
      boot.loader.grub.configurationName = name;
      services.xserver.videoDrivers = [ "nvidia" "modesetting" ];
      hardware.nvidia = {
        modesetting.enable = true;
        open = false;
        nvidiaSettings = true;
        powerManagement.enable = true;
        powerManagement.finegrained = false;
        package = config.boot.kernelPackages.nvidiaPackages.stable;
        prime = {
          sync.enable = true; # shuld be false ???
          offload.enable = false; # shuld be true ???
          allowExternalGpu = true;
          intelBusId = "PCI:0:2:0";
          inherit nvidiaBusId;
        };
      };
    };
  in {
    rescue.configuration = {
      system.nixos.label = "rescue";
      boot.loader.grub.configurationName = "rescue";

      services.xserver.enable = pkgs.lib.mkForce false;
      services.displayManager.sddm.enable = pkgs.lib.mkForce false;
      services.displayManager.autoLogin.enable = pkgs.lib.mkForce false;
      services.picom.enable = pkgs.lib.mkForce false;

      environment.etc."issue".text = ''

        ┌─────────────────────────────────────────────────────┐
        │                                                     │
        │          GNOMS  —  EMERGENCY  RESCUE  MODE          │
        │                                                     │
        │   No graphical session. Auto-login disabled.        │
        │   Home-manager user services will not start.        │
        │   Log in to access the shell environment.           │
        │                                                     │
        └─────────────────────────────────────────────────────┘

      '';
    };

    eGPU.configuration = egpu "eGPU" "nix-NVIDIA" "PCI:9:0:0"; # eGPU plugged straight into the laptop
    eGPU-dock.configuration = egpu "eGPU-dock" "nix-NVIDIA-dock" "PCI:12:0:0"; # eGPU behind the WD22TB4 dock
  };

  # ------------------------------------------------------------------------------------------
  # ---------------------------------------- NIX SPESIFIC ------------------------------------
  # ------------------------------------------------------------------------------------------

  # Fix to get bin/bash to work, not strictly nessesary.
  system.activationScripts.binbash = {
  text = ''
    mkdir -p /bin
    ln -sf ${pkgs.bash}/bin/bash /bin/bash
  '';
};

  # Nix garbage collection
  # The weekly timer only GCs unreachable paths — it must NEVER delete
  # generations. Generation pruning happens in reconfigure.sh immediately
  # after a successful rebuild, so the freshly regenerated GRUB menu can
  # never reference paths that garbage collection removed.
  nix = {
    settings = {
      auto-optimise-store = true;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      # default options: plain `nix-collect-garbage` (no generation deletion)
    };
  };

  # nix-direnv: creates GC roots for dev environments so they survive garbage
  # collection — without this, `nix develop` packages have no GC root and get
  # collected even though the flake hasn't changed
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };


  system.stateVersion = "24.11"; # apparantly important. ¯\_(ツ)_/¯
  home-manager.backupFileExtension = "backup";

  # ------------------------------------------------------------------------------------------
  # ----------------------------------------- SERVICES ---------------------------------------
  # ------------------------------------------------------------------------------------------

  # Monitor and usb connection watch:
  services.udev.packages = with pkgs; [
    segger-jlink-headless # installs 99-jlink.rules
    (pkgs.nrfutil.withExtensions [ "nrfutil-device" ]) # installs 71-nrf.rules
  ];
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="tty", TAG+="systemd", ENV{SYSTEMD_WANTS}="log-usb-event.service"
    ACTION=="change", SUBSYSTEM=="drm", TAG+="systemd", ENV{SYSTEMD_WANTS}="log-monitor-event.service"
  '';
  systemd.services.log-usb-event = {
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${rootTriggerScript} usb";
    };
  };
  systemd.services.log-monitor-event = {
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${rootTriggerScript} monitor";
    };
  };
  systemd.services.log-on-lid = {
    description = "Delay suspend to allow screen lock";
    before = [ "sleep.target" ];
    wantedBy = [ "sleep.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart =
        "${pkgs.bash}/bin/bash -c '${rootTriggerScript} sleep; sleep 3'";
    };
  };
  systemd.tmpfiles.rules = [
    "r /tmp/awesome-has-started - - - - -"
    # Hibernation image may hold all of RAM (24 GiB; swap is 32 GiB). The
    # kernel default (2/5 of RAM) pushes everything above ~10 GB out to
    # encrypted swap before saving, which then pages back in slowly after
    # resume (the sluggish lock screen). Cost: a bigger image to write.
    "w /sys/power/image_size - - - - 25769803776"
  ];

  # ------------------------------------------------------------------------------------------
  # ----------------------------------------- PROGRAMS ---------------------------------------
  # ------------------------------------------------------------------------------------------

  # SYSTEM WIDE PROGRAMS
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.segger-jlink.acceptLicense = true;
  environment.systemPackages = with pkgs; [
    config.boot.kernelPackages.nvidia_x11 # NVIDIA driver

    # Terminal:
    wezterm

    # Editors:
    vim

    # Backupp browser:
    chromium

    # Multi monitor support:
    arandr
    autorandr

    # Microcontrollers:
    mpremote # (MicroPython REPL + file push)
    esptool # (ESP flashing)
    picocom # (serial monitor)
    avrdude # (Arduino flashing)
    picotool # (Pico UF2 loading)
    (pkgs.nrfutil.withExtensions [ "nrfutil-device" ]) # Nordic nRF flashing; device extension bundled to avoid NixOS FHS issues
    segger-jlink-headless # J-Link drivers/tools without Qt GUI
    arduino-cli # compiler for arduino
    probe-rs-tools # RTT monitor + debug probe for Nordic/ARM bare-metal

    # Coding resources:
    python3 # Python interpreter
    gcc # C/C++ compiler
    poetry # Python dependency manager

    # Code formatters
    nixfmt # Nix formatter
    stylua # Lua formatter
    black # Python formatter
    shfmt # shell script formatter
    prettier # web/JS/TS formatter
    jq # JSON processor

    # Small programs:
    rofi # Application launcer
    dunst # notification daemon
    flameshot # screenshot app
    pavucontrol # Audio controll
    polkit_gnome # GUI for user auth
    networkmanagerapplet # nm-applet nm-connection-editor
    brightnessctl # Backlight brightness support
    qalculate-gtk # Calculator
    udiskie # USB automout applet
    baobab # disk analyser tool
    speedtest-cli # network speed test
    nethogs # program network usage
    bluetuith # Bluetooth TUI
    modem-manager-gui # 4G GUI

    # Cmd tools:
    zip # zip files
    unzip # unzip files
    gnupg # OpenPGP, encrypt/decrypt & sign data
    curl # transfer data over URLs (HTTP, FTP, etc.)
    file # detect a file’s type/format
    xclip # clipboard manager
    htop # program control pannel
    libnotify # notifyer backend
    xev # show keycodes
    xmodmap # list keycodes
    imagemagick # Blur images
    xdotool # for scripts flashing to microcontollers
    wget # download files from web
    usbutils # list USB devices
    lsof # list open files/processes
    pciutils # list PCI devices
    inotify-tools # filesystem change watcher
    coreutils # GNU base tools (ls, cp, etc.)
    maim # screenshot tool
    lshw # list hardware details
    sshfs # acsess to folk.NTNU
    xidlehook # autolocker
    ntfs3g # Windows filesystem support
    file-roller # zip and unzip for thunar
    mesa-demos # GPU utils
    nftables # Filefwall tools
    glmark2 # GPU benchmark
    mpv # the best video player
    bat # cat but with colors
    bat-extras.core # Batman!
    ffmpeg-full # full-featured media converter

    # MAN PAGES:
    man-pages # Linux man pages
    man-pages-posix # POSIX man pages

  ] ++ userprograms.system;
  documentation.dev.enable = true;
  documentation.man = {
    man-db.enable = false;
    mandoc.enable = true;
  };

  # ------------------------------------------------------------------------------------------
  # -------------------------------------- SYNCTHING -----------------------------------------
  # ------------------------------------------------------------------------------------------

  services.syncthing = {
    enable = true;
    group = "users";
    user = profile.username;
    configDir = "/home/${profile.username}/.config/syncthing";
  }; # GUI on http://127.0.0.1:8384/

  # ------------------------------------------------------------------------------------------
  # -------------------------------------- FILEMANAGER ---------------------------------------
  # ------------------------------------------------------------------------------------------

  programs.thunar.enable = true;
  programs.xfconf.enable = true;
  programs.thunar.plugins = with pkgs; [
    thunar-archive-plugin
    thunar-volman
  ];
  services.gvfs.enable = true; # Mount, trash, and other functionalities
  services.tumbler.enable = true; # Thumbnail support for images
  services.udisks2.enable = true; # AutoMount backend

  # ------------------------------------------------------------------------------------------
  # ---------------------------------------- FONTS -------------------------------------------
  # ------------------------------------------------------------------------------------------

  fonts.packages = with pkgs; [
    jetbrains-mono # system font
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    noto-fonts-monochrome-emoji
    liberation_ttf
    fira-code
    fira-code-symbols
    mplus-outline-fonts.githubRelease
    dina-font
    proggyfonts
    nerd-fonts.jetbrains-mono
    nerd-fonts.inconsolata
    font-awesome
    corefonts # Impact (meme font), Arial, etc. - unfree
    (google-fonts.override { fonts = [ "Anton" "BebasNeue" "Oswald" "Bangers" "LuckiestGuy" "Montserrat" ]; }) # thumbnail fonts
  ];
  fonts.fontDir.enable = true;

}