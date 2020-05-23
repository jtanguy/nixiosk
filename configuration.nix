{ lib, pkgs, config, ...}: {

  imports = [ ./custom.nix ./hardware/raspberrypi.nix ./hardware/ova.nix ];

  hardware.opengl.enable = true;
  hardware.bluetooth.enable = true;
  sound.enable = true;
  hardware.pulseaudio.enable = true;
  services.dbus.enable = true;
  services.dbus.socketActivated = true;

  # theming
  gtk.iconCache.enable = true;
  environment.systemPackages = [
    pkgs.gnome3.adwaita-icon-theme pkgs.hicolor-icon-theme

    (pkgs.git.override {
      withManual = false;
      pythonSupport = false;
      withpcre2 = false;
      perlSupport = false;
    })
  ];

  # input
  services.udev.packages = [ pkgs.libinput.out ];

  # nix.package = pkgs.nixUnstable;
  nix.binaryCachePublicKeys = ["https://nixiosk.cachix.org"];
  nix.binaryCaches = ["nixiosk.cachix.org-1:zcztl5w5OEAd6KKqWvrlfH7zopGsalSg/vJp3fUJDMk="];

  services.openssh = {
    enable = true;
    permitRootLogin = "without-password";
  };

  users.users.kiosk = {
    isNormalUser = true;
    useDefaultShell = true;
  };

  services.xserver.displayManager.startx.enable = true;

  environment.etc."X11/xinit/xinitrc" = {
    enable = true;
    text = ''
if test -z "$DBUS_SESSION_BUS_ADDRESS"; then
	eval $(dbus-launch --exit-with-session --sh-syntax)
fi
systemctl --user import-environment DISPLAY XAUTHORITY

if command -v dbus-update-activation-environment >/dev/null 2>&1; then
        dbus-update-activation-environment DISPLAY XAUTHORITY
fi
      '';
  };

  # systemd.services."cage@" = {
  #   serviceConfig.Restart = "always";
  #   environment = {
  #     WLR_LIBINPUT_NO_DEVICES = "1";
  #     XDG_DATA_DIRS = "/nix/var/nix/profiles/default/share:/run/current-system/sw/share";
  #     XDG_CONFIG_DIRS = "/nix/var/nix/profiles/default/etc/xdg:/run/current-system/sw/etc/xdg";
  #     WEBKIT_DISABLE_COMPOSITING_MODE = "1";
  #   } // lib.optionalAttrs (config.environment.variables ? GDK_PIXBUF_MODULE_FILE) {
  #     GDK_PIXBUF_MODULE_FILE = config.environment.variables.GDK_PIXBUF_MODULE_FILE;
  #   };
  # };

  systemd.enableEmergencyMode = false;
  # systemd.services."serial-getty@ttyS0".enable = false;
  # systemd.services."serial-getty@hvc0".enable = false;
  # systemd.services."getty@tty1".enable = false;
  # systemd.services."autovt@".enable = false;

  services.udisks2.enable = false;
  documentation.enable = false;
  powerManagement.enable = false;
  programs.command-not-found.enable = false;

  # services.cage = {
  #   enable = true;
  #   user = "kiosk";
  # };

  services.avahi = {
    enable = true;
    nssmdns = true;
    publish = {
      enable = true;
      userServices = true;
      addresses = true;
      hinfo = true;
      workstation = true;
      domain = true;
    };
  };
  environment.etc."avahi/services/ssh.service" = {
    text = ''
      <?xml version="1.0" standalone='no'?><!--*-nxml-*-->
      <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
      <service-group>
        <name replace-wildcards="yes">%h</name>
        <service>
          <type>_ssh._tcp</type>
          <port>22</port>
        </service>
      </service-group>
    '';
  };

  nixpkgs = {
    overlays = [

    # Disable some things that don’t cross compile
    (self: super: lib.optionalAttrs (super.stdenv.hostPlatform != super.stdenv.buildPlatform) {
      gtk3 = super.gtk3.override { cupsSupport = false; };
      webkitgtk = super.webkitgtk.override {
        enableGeoLocation = false;
        stdenv = super.stdenv;
      };
      gst_all_1 = super.gst_all_1 // {
        gst-plugins-good = null;
        gst-plugins-bad = null;
        gst-plugins-ugly = null;
        gst-libav = null;
      };

      # cython pulls in target-specific gdb
      python37 = super.python37.override {
        packageOverrides = self: super: { cython = super.cython.override { gdb = null; }; };
      };

      # doesn’t cross compile
      libass = super.libass.override { encaSupport = false; };
      libproxy = super.libproxy.override { networkmanager = null; };
      enchant2 = super.enchant2.override { hspell = null; };

      alsaPlugins = super.alsaPlugins.override { libjack2 = null; };
      fluidsynth = super.fluidsynth.override { libjack2 = null; };
      portaudio = super.portaudio.override { libjack2 = null; };

      ffmpeg_4 = super.ffmpeg_4.override ({
        sdlSupport = false;
        # some ffmpeg libs are compiled with neon which rpi0 doesn’t support
      } // lib.optionalAttrs (super.stdenv.hostPlatform.parsed.cpu.name == "armv6l") {
        libopus = null;
        x264 = null;
        x265 = null;
        soxr = null;
      });
      ffmpeg = super.ffmpeg.override ({
        sdlSupport = false;
      } // lib.optionalAttrs (super.stdenv.hostPlatform.parsed.cpu.name == "armv6l") {
        libopus = null;
        x264 = null;
        x265 = null;
        soxr = null;
      });

      # mesa = super.mesa.override { eglPlatforms = ["wayland" "drm"]; };

      kodiPlain = super.kodiPlain.override {
        sambaSupport = false;
        rtmpSupport = false;
        joystickSupport = false;
        lirc = null;
      };

    }) (self: super: {

      makair-control-ui = self.rustPlatform.buildRustPackage {
        name = "makair-control-ui";
        src = builtins.fetchTarball {
          url = "https://github.com/makers-for-life/makair-control-ui/archive/84a395809abf86ac74b3a603a2a99141e2a9b51d.tar.gz";
          sha256 = "0hhm44nrbg1hnjz1blq7bhnffzzjnahcsbf6rqnwq5ppn86n3iav";
        };
        nativeBuildInputs = with super.buildPackages; [ cmake pkgconfig python3 ];
        buildInputs = with super; [ expat freetype xorg.libxcb fontconfig  ];
        PKG_CONFIG = "pkg-config";
        verifyCargoDeps = true;
        cargoSha256 = "089j0sdmjs8x2s0vlx6ik6wpfdvfdwv2194hmrr4gykyvf785w49";
        postInstall = let
          rpathLibs = with super; [
            expat
            fontconfig
            freetype
            libGL
            wayland
          ];
        in ''
          patchelf --set-rpath "${lib.makeLibraryPath rpathLibs}" $out/bin/makair-control
        '';
      };

    }) ];

    # We use remote builders for things like 32-bit arm where there is
    # no binary cache, otherwise, we might as well build it natively,
    # with the cache covering most of it.
    localSystem = let
      cachedSystems = [ "aarch64-linux" "x86_64-linux" "x86_64-darwin" ];
    in if builtins.elem (config.nixpkgs.crossSystem.system or null) cachedSystems
       then config.nixpkgs.crossSystem
       else if (config.nixiosk.localSystem.hostName != null) && (config.nixiosk.localSystem.sshUser != null) && (config.nixiosk.localSystem.system != null) then { inherit (config.nixiosk.localSystem) system; }
       else (lib.mkIf (config.nixpkgs.crossSystem.system or null != null) config.nixpkgs.crossSystem);
  };

  boot.plymouth.enable = true;
  boot.consoleLogLevel = 3;
  boot.kernelParams = [ "rd.udev.log_priority=3" "vt.global_cursor_default=0" ];

  networking = {
    wireless.enable = true;
    dhcpcd.extraConfig = "timeout 0";
  };

  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.login1.power-off" ||
	        action.id == "org.freedesktop.login1.reboot") {
        return polkit.Result.YES;
      }
    });
  '';

}
