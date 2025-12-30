# libimobiledevice iOS build
# Builds libplist, libimobiledevice-glue, libusbmuxd, and libimobiledevice for iOS
#
# These libraries are required by minimuxer for device communication via lockdownd.
#
# Copyright (c) 2025 Alex Spaulding - AGPLv3

{ lib, pkgs, buildPackages, fetchFromGitHub }:

let
  xcodeUtils = import ../utils/xcode-wrapper.nix { inherit lib pkgs; };
  
  # Common iOS cross-compilation setup
  iosCrossSetup = ''
    if [ -z "''${XCODE_APP:-}" ]; then
      XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
      if [ -n "$XCODE_APP" ]; then
        export XCODE_APP
        export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
        export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
        export SDKROOT="$DEVELOPER_DIR/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
        export SDKROOT_IOS="$DEVELOPER_DIR/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
      fi
    fi
    
    export NIX_CFLAGS_COMPILE=""
    export NIX_CXXFLAGS_COMPILE=""
    
    # Use Xcode's clang for proper iOS SDK integration
    if [ -n "''${SDKROOT:-}" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
      IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
      IOS_CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
      IOS_AR="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/ar"
      IOS_RANLIB="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/ranlib"
      IOS_STRIP="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/strip"
    else
      IOS_CC="${buildPackages.clang}/bin/clang"
      IOS_CXX="${buildPackages.clang}/bin/clang++"
      IOS_AR="${buildPackages.binutils}/bin/ar"
      IOS_RANLIB="${buildPackages.binutils}/bin/ranlib"
      IOS_STRIP="${buildPackages.binutils}/bin/strip"
    fi
    
    SIMULATOR_ARCH="arm64"
    if [ "$(uname -m)" = "x86_64" ]; then
      SIMULATOR_ARCH="x86_64"
    fi
    
    # Common flags for iOS Simulator
    export CC="$IOS_CC"
    export CXX="$IOS_CXX"
    export AR="$IOS_AR"
    export RANLIB="$IOS_RANLIB"
    export STRIP="$IOS_STRIP"
    export CFLAGS="-arch $SIMULATOR_ARCH -isysroot $SDKROOT -mios-simulator-version-min=15.0 -fPIC -DHAVE_OPENSSL"
    export CXXFLAGS="-arch $SIMULATOR_ARCH -isysroot $SDKROOT -mios-simulator-version-min=15.0 -fPIC -DHAVE_OPENSSL"
    export LDFLAGS="-arch $SIMULATOR_ARCH -isysroot $SDKROOT -mios-simulator-version-min=15.0"
    export PKG_CONFIG_PATH="$out/lib/pkgconfig"
  '';
  
  # iOS device build setup
  iosDeviceSetup = ''
    if [ -z "''${XCODE_APP:-}" ]; then
      XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
      if [ -n "$XCODE_APP" ]; then
        export XCODE_APP
        export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
        export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
        export SDKROOT="$DEVELOPER_DIR/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
      fi
    fi
    
    export NIX_CFLAGS_COMPILE=""
    export NIX_CXXFLAGS_COMPILE=""
    
    if [ -n "''${SDKROOT:-}" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
      IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
      IOS_CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
      IOS_AR="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/ar"
      IOS_RANLIB="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/ranlib"
      IOS_STRIP="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/strip"
    else
      IOS_CC="${buildPackages.clang}/bin/clang"
      IOS_CXX="${buildPackages.clang}/bin/clang++"
      IOS_AR="${buildPackages.binutils}/bin/ar"
      IOS_RANLIB="${buildPackages.binutils}/bin/ranlib"
      IOS_STRIP="${buildPackages.binutils}/bin/strip"
    fi
    
    export CC="$IOS_CC"
    export CXX="$IOS_CXX"
    export AR="$IOS_AR"
    export RANLIB="$IOS_RANLIB"
    export STRIP="$IOS_STRIP"
    export CFLAGS="-arch arm64 -isysroot $SDKROOT -miphoneos-version-min=15.0 -fPIC -DHAVE_OPENSSL"
    export CXXFLAGS="-arch arm64 -isysroot $SDKROOT -miphoneos-version-min=15.0 -fPIC -DHAVE_OPENSSL"
    export LDFLAGS="-arch arm64 -isysroot $SDKROOT -miphoneos-version-min=15.0"
    export PKG_CONFIG_PATH="$out/lib/pkgconfig"
  '';

  # Fetch sources from SideStore forks (they have the patches for iOS)
  libplist-src = fetchFromGitHub {
    owner = "SideStore";
    repo = "libplist";
    rev = "master";
    sha256 = "0krgbb05dwkzsabrxqcgp3l107dswq0bv35bnxc8ab18m8ya8293";
  };
  
  libimobiledevice-glue-src = fetchFromGitHub {
    owner = "libimobiledevice";
    repo = "libimobiledevice-glue";
    rev = "master";
    sha256 = "1ilh107y0nx38nf48cmrdccni707ghkfn8psi0hnmv2dgwr871y4";
  };
  
  libusbmuxd-src = fetchFromGitHub {
    owner = "libimobiledevice";
    repo = "libusbmuxd";
    rev = "master";
    sha256 = "0yshswi9ma5x6hamkv8n7h8p4x5afhi5zqk9hqqn1p86p594l069";
  };
  
  # SideStore fork with minimuxer fix patches
  libimobiledevice-src = fetchFromGitHub {
    owner = "SideStore";
    repo = "libimobiledevice";
    rev = "master";
    sha256 = "1qql95d5vw8jfv4i35n926dr3hiccad9j35rdg43hx22c05f26q8";
  };

  # Build libplist first (no dependencies)
  libplist-ios-sim = pkgs.stdenv.mkDerivation {
    name = "libplist-ios-sim";
    version = "2.3.0";
    
    src = libplist-src;
    
    nativeBuildInputs = with buildPackages; [
      autoconf
      automake
      libtool
      pkg-config
    ];
    
    preConfigure = ''
      ${iosCrossSetup}
      
      # Create version file (required for non-git builds)
      echo "2.6.0" > .tarball-version
      
      # Generate configure script
      NOCONFIGURE=1 ./autogen.sh || true
    '';
    
    configurePhase = ''
      runHook preConfigure
      ./configure \
        --prefix=$out \
        --host=arm-apple-darwin \
        --disable-shared \
        --enable-static \
        --without-cython
      runHook postConfigure
    '';
    
    buildPhase = ''
      runHook preBuild
      make -j$NIX_BUILD_CORES
      runHook postBuild
    '';
    
    installPhase = ''
      runHook preInstall
      make install
      runHook postInstall
    '';
    
    __noChroot = true;
  };
  
  libplist-ios = pkgs.stdenv.mkDerivation {
    name = "libplist-ios";
    version = "2.3.0";
    
    src = libplist-src;
    
    nativeBuildInputs = with buildPackages; [
      autoconf
      automake
      libtool
      pkg-config
    ];
    
    preConfigure = ''
      ${iosDeviceSetup}
      
      # Create version file (required for non-git builds)
      echo "2.6.0" > .tarball-version
      
      NOCONFIGURE=1 ./autogen.sh || true
    '';
    
    configurePhase = ''
      runHook preConfigure
      ./configure \
        --prefix=$out \
        --host=arm-apple-darwin \
        --disable-shared \
        --enable-static \
        --without-cython
      runHook postConfigure
    '';
    
    buildPhase = ''
      runHook preBuild
      make -j$NIX_BUILD_CORES
      runHook postBuild
    '';
    
    installPhase = ''
      runHook preInstall
      make install
      runHook postInstall
    '';
    
    __noChroot = true;
  };

  # Build libimobiledevice-glue (depends on libplist)
  libimobiledevice-glue-ios-sim = pkgs.stdenv.mkDerivation {
    name = "libimobiledevice-glue-ios-sim";
    version = "1.0.0";
    
    src = libimobiledevice-glue-src;
    
    nativeBuildInputs = with buildPackages; [
      autoconf
      automake
      libtool
      pkg-config
    ];
    
    preConfigure = ''
      ${iosCrossSetup}
      
      # Create version file
      echo "1.3.1" > .tarball-version
      
      export PKG_CONFIG_PATH="${libplist-ios-sim}/lib/pkgconfig:$PKG_CONFIG_PATH"
      export CFLAGS="$CFLAGS -I${libplist-ios-sim}/include"
      export LDFLAGS="$LDFLAGS -L${libplist-ios-sim}/lib"
      
      NOCONFIGURE=1 ./autogen.sh || true
    '';
    
    configurePhase = ''
      runHook preConfigure
      ./configure \
        --prefix=$out \
        --host=arm-apple-darwin \
        --disable-shared \
        --enable-static
      runHook postConfigure
    '';
    
    buildPhase = ''
      runHook preBuild
      make -j$NIX_BUILD_CORES
      runHook postBuild
    '';
    
    installPhase = ''
      runHook preInstall
      make install
      runHook postInstall
    '';
    
    __noChroot = true;
  };
  
  libimobiledevice-glue-ios = pkgs.stdenv.mkDerivation {
    name = "libimobiledevice-glue-ios";
    version = "1.0.0";
    
    src = libimobiledevice-glue-src;
    
    nativeBuildInputs = with buildPackages; [
      autoconf
      automake
      libtool
      pkg-config
    ];
    
    preConfigure = ''
      ${iosDeviceSetup}
      
      # Create version file
      echo "1.3.1" > .tarball-version
      
      export PKG_CONFIG_PATH="${libplist-ios}/lib/pkgconfig:$PKG_CONFIG_PATH"
      export CFLAGS="$CFLAGS -I${libplist-ios}/include"
      export LDFLAGS="$LDFLAGS -L${libplist-ios}/lib"
      
      NOCONFIGURE=1 ./autogen.sh || true
    '';
    
    configurePhase = ''
      runHook preConfigure
      ./configure \
        --prefix=$out \
        --host=arm-apple-darwin \
        --disable-shared \
        --enable-static
      runHook postConfigure
    '';
    
    buildPhase = ''
      runHook preBuild
      make -j$NIX_BUILD_CORES
      runHook postBuild
    '';
    
    installPhase = ''
      runHook preInstall
      make install
      runHook postInstall
    '';
    
    __noChroot = true;
  };

  # Build libusbmuxd (depends on libplist, libimobiledevice-glue)
  libusbmuxd-ios-sim = pkgs.stdenv.mkDerivation {
    name = "libusbmuxd-ios-sim";
    version = "2.0.2";
    
    src = libusbmuxd-src;
    
    nativeBuildInputs = with buildPackages; [
      autoconf
      automake
      libtool
      pkg-config
    ];
    
    preConfigure = ''
      ${iosCrossSetup}
      
      # Create version file
      echo "2.1.0" > .tarball-version
      
      export PKG_CONFIG_PATH="${libplist-ios-sim}/lib/pkgconfig:${libimobiledevice-glue-ios-sim}/lib/pkgconfig:$PKG_CONFIG_PATH"
      export CFLAGS="$CFLAGS -I${libplist-ios-sim}/include -I${libimobiledevice-glue-ios-sim}/include"
      export LDFLAGS="$LDFLAGS -L${libplist-ios-sim}/lib -L${libimobiledevice-glue-ios-sim}/lib"
      
      NOCONFIGURE=1 ./autogen.sh || true
    '';
    
    configurePhase = ''
      runHook preConfigure
      ./configure \
        --prefix=$out \
        --host=arm-apple-darwin \
        --disable-shared \
        --enable-static
      runHook postConfigure
    '';
    
    buildPhase = ''
      runHook preBuild
      make -j$NIX_BUILD_CORES
      runHook postBuild
    '';
    
    installPhase = ''
      runHook preInstall
      make install
      runHook postInstall
    '';
    
    __noChroot = true;
  };
  
  libusbmuxd-ios = pkgs.stdenv.mkDerivation {
    name = "libusbmuxd-ios";
    version = "2.0.2";
    
    src = libusbmuxd-src;
    
    nativeBuildInputs = with buildPackages; [
      autoconf
      automake
      libtool
      pkg-config
    ];
    
    preConfigure = ''
      ${iosDeviceSetup}
      
      # Create version file
      echo "2.1.0" > .tarball-version
      
      export PKG_CONFIG_PATH="${libplist-ios}/lib/pkgconfig:${libimobiledevice-glue-ios}/lib/pkgconfig:$PKG_CONFIG_PATH"
      export CFLAGS="$CFLAGS -I${libplist-ios}/include -I${libimobiledevice-glue-ios}/include"
      export LDFLAGS="$LDFLAGS -L${libplist-ios}/lib -L${libimobiledevice-glue-ios}/lib"
      
      NOCONFIGURE=1 ./autogen.sh || true
    '';
    
    configurePhase = ''
      runHook preConfigure
      ./configure \
        --prefix=$out \
        --host=arm-apple-darwin \
        --disable-shared \
        --enable-static
      runHook postConfigure
    '';
    
    buildPhase = ''
      runHook preBuild
      make -j$NIX_BUILD_CORES
      runHook postBuild
    '';
    
    installPhase = ''
      runHook preInstall
      make install
      runHook postInstall
    '';
    
    __noChroot = true;
  };

  # Build libimobiledevice (depends on all above)
  libimobiledevice-ios-sim = pkgs.stdenv.mkDerivation {
    name = "libimobiledevice-ios-sim";
    version = "1.3.0";
    
    src = libimobiledevice-src;
    
    nativeBuildInputs = with buildPackages; [
      autoconf
      automake
      libtool
      pkg-config
      openssl
    ];
    
    preConfigure = ''
      ${iosCrossSetup}
      
      # Create version file
      echo "1.3.0" > .tarball-version
      
      # Find OpenSSL from SDK
      SSL_INCLUDE="$SDKROOT/usr/include"
      SSL_LIB="$SDKROOT/usr/lib"
      
      export PKG_CONFIG_PATH="${libplist-ios-sim}/lib/pkgconfig:${libimobiledevice-glue-ios-sim}/lib/pkgconfig:${libusbmuxd-ios-sim}/lib/pkgconfig:$PKG_CONFIG_PATH"
      export CFLAGS="$CFLAGS -I${libplist-ios-sim}/include -I${libimobiledevice-glue-ios-sim}/include -I${libusbmuxd-ios-sim}/include -I$SSL_INCLUDE"
      export LDFLAGS="$LDFLAGS -L${libplist-ios-sim}/lib -L${libimobiledevice-glue-ios-sim}/lib -L${libusbmuxd-ios-sim}/lib -L$SSL_LIB"
      export openssl_CFLAGS="-I$SSL_INCLUDE"
      export openssl_LIBS="-L$SSL_LIB -lssl -lcrypto"
      
      NOCONFIGURE=1 ./autogen.sh || true
    '';
    
    configurePhase = ''
      runHook preConfigure
      ./configure \
        --prefix=$out \
        --host=arm-apple-darwin \
        --disable-shared \
        --enable-static \
        --without-cython \
        --with-openssl
      runHook postConfigure
    '';
    
    buildPhase = ''
      runHook preBuild
      make -j$NIX_BUILD_CORES
      runHook postBuild
    '';
    
    installPhase = ''
      runHook preInstall
      make install
      runHook postInstall
    '';
    
    __noChroot = true;
  };
  
  libimobiledevice-ios = pkgs.stdenv.mkDerivation {
    name = "libimobiledevice-ios";
    version = "1.3.0";
    
    src = libimobiledevice-src;
    
    nativeBuildInputs = with buildPackages; [
      autoconf
      automake
      libtool
      pkg-config
      openssl
    ];
    
    preConfigure = ''
      ${iosDeviceSetup}
      
      # Create version file
      echo "1.3.0" > .tarball-version
      
      SSL_INCLUDE="$SDKROOT/usr/include"
      SSL_LIB="$SDKROOT/usr/lib"
      
      export PKG_CONFIG_PATH="${libplist-ios}/lib/pkgconfig:${libimobiledevice-glue-ios}/lib/pkgconfig:${libusbmuxd-ios}/lib/pkgconfig:$PKG_CONFIG_PATH"
      export CFLAGS="$CFLAGS -I${libplist-ios}/include -I${libimobiledevice-glue-ios}/include -I${libusbmuxd-ios}/include -I$SSL_INCLUDE"
      export LDFLAGS="$LDFLAGS -L${libplist-ios}/lib -L${libimobiledevice-glue-ios}/lib -L${libusbmuxd-ios}/lib -L$SSL_LIB"
      export openssl_CFLAGS="-I$SSL_INCLUDE"
      export openssl_LIBS="-L$SSL_LIB -lssl -lcrypto"
      
      NOCONFIGURE=1 ./autogen.sh || true
    '';
    
    configurePhase = ''
      runHook preConfigure
      ./configure \
        --prefix=$out \
        --host=arm-apple-darwin \
        --disable-shared \
        --enable-static \
        --without-cython \
        --with-openssl
      runHook postConfigure
    '';
    
    buildPhase = ''
      runHook preBuild
      make -j$NIX_BUILD_CORES
      runHook postBuild
    '';
    
    installPhase = ''
      runHook preInstall
      make install
      runHook postInstall
    '';
    
    __noChroot = true;
  };

in {
  # Expose individual libraries
  inherit libplist-ios-sim libplist-ios;
  inherit libimobiledevice-glue-ios-sim libimobiledevice-glue-ios;
  inherit libusbmuxd-ios-sim libusbmuxd-ios;
  inherit libimobiledevice-ios-sim libimobiledevice-ios;
  
  # Combined simulator bundle
  ios-sim = pkgs.stdenv.mkDerivation {
    name = "libimobiledevice-bundle-ios-sim";
    version = "1.0.0";
    
    unpackPhase = "true";
    
    installPhase = ''
      mkdir -p $out/{lib,include}
      
      # Copy all static libraries
      cp ${libplist-ios-sim}/lib/*.a $out/lib/ 2>/dev/null || true
      cp ${libimobiledevice-glue-ios-sim}/lib/*.a $out/lib/ 2>/dev/null || true
      cp ${libusbmuxd-ios-sim}/lib/*.a $out/lib/ 2>/dev/null || true
      cp ${libimobiledevice-ios-sim}/lib/*.a $out/lib/ 2>/dev/null || true
      
      # Copy headers
      cp -r ${libplist-ios-sim}/include/* $out/include/ 2>/dev/null || true
      cp -r ${libimobiledevice-glue-ios-sim}/include/* $out/include/ 2>/dev/null || true
      cp -r ${libusbmuxd-ios-sim}/include/* $out/include/ 2>/dev/null || true
      cp -r ${libimobiledevice-ios-sim}/include/* $out/include/ 2>/dev/null || true
      
      # Create combined library
      echo "Creating combined static library..."
      cd $out/lib
      mkdir -p _tmp
      cd _tmp
      for lib in ../*.a; do
        $AR x "$lib"
      done
      $AR rcs ../libimobiledevice-combined-sim.a *.o
      cd ..
      rm -rf _tmp
      
      echo ""
      echo "✅ libimobiledevice iOS Simulator bundle built"
      echo "   Libraries: $(ls $out/lib/*.a | wc -l)"
      ls $out/lib/*.a
    '';
    
    __noChroot = true;
  };
  
  # Combined device bundle
  ios = pkgs.stdenv.mkDerivation {
    name = "libimobiledevice-bundle-ios";
    version = "1.0.0";
    
    unpackPhase = "true";
    
    installPhase = ''
      mkdir -p $out/{lib,include}
      
      # Copy all static libraries
      cp ${libplist-ios}/lib/*.a $out/lib/ 2>/dev/null || true
      cp ${libimobiledevice-glue-ios}/lib/*.a $out/lib/ 2>/dev/null || true
      cp ${libusbmuxd-ios}/lib/*.a $out/lib/ 2>/dev/null || true
      cp ${libimobiledevice-ios}/lib/*.a $out/lib/ 2>/dev/null || true
      
      # Copy headers
      cp -r ${libplist-ios}/include/* $out/include/ 2>/dev/null || true
      cp -r ${libimobiledevice-glue-ios}/include/* $out/include/ 2>/dev/null || true
      cp -r ${libusbmuxd-ios}/include/* $out/include/ 2>/dev/null || true
      cp -r ${libimobiledevice-ios}/include/* $out/include/ 2>/dev/null || true
      
      # Create combined library
      echo "Creating combined static library..."
      cd $out/lib
      mkdir -p _tmp
      cd _tmp
      for lib in ../*.a; do
        $AR x "$lib"
      done
      $AR rcs ../libimobiledevice-combined-ios.a *.o
      cd ..
      rm -rf _tmp
      
      echo ""
      echo "✅ libimobiledevice iOS Device bundle built"
      echo "   Libraries: $(ls $out/lib/*.a | wc -l)"
      ls $out/lib/*.a
    '';
    
    __noChroot = true;
  };
}

