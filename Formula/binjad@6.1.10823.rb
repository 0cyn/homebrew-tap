class BinjadAT6110823 < Formula
  desc "Headless Binary Ninja MCP server"
  homepage "https://github.com/0cyn/binjad"
  url "https://github.com/0cyn/binjad.git",
      revision: "bd90d95f1cd6e78c2132c845150f6b680beed732",
      using:    :git
  version "0.2.3"
  license "BSD-3-Clause"

  bottle do
    root_url "https://ghcr.io/v2/0cyn/tap"
    sha256 arm64_tahoe:  "844383df78c9d75fee4475631fca1335adf1282a675479a6f94af367046fc365"
    sha256 arm64_linux:  "c7757c10111f38a982e55a8dbac29204b69c09c90f4a75b704c872ab1a603f4f"
    sha256 x86_64_linux: "0cb6eb83e5b2c3fa6f77dfaee3c63d98930e77cf69a0e0385af197f1847bad53"
  end

  keg_only :versioned_formula

  depends_on "cmake" => :build
  depends_on "ninja" => :build
  depends_on "python@3.14" => :build

  on_macos do
    depends_on macos: :sonoma
  end

  on_linux do
    depends_on "patchelf" => :build
    depends_on "util-linux"
  end

  def install
    args = [
      "-G", "Ninja",
      *std_cmake_args,
      "-DBINJAD_BUILD_TESTS=OFF",
      "-DBINJAD_USE_KEYCHAIN=#{OS.mac? ? "ON" : "OFF"}"
    ]
    args << "-DBINJAD_SERVICE_EXECUTABLE=#{opt_bin}/binjad" if OS.mac?

    system "cmake", "-S", ".", "-B", "build", *args
    system "cmake", "--build", "build", "--parallel"
    system "cmake", "--install", "build"

    return unless OS.linux?

    runtime = libexec/"binjad-runtime"
    %w[
      libbinaryninjacore.so.1
      libdebuggercore.so
      libkernelcache.so
      libsharedcache.so
    ].each do |library|
      system "patchelf", "--remove-needed", library, runtime
    end

    unit = <<~SYSTEMD
      [Unit]
      Description=binjad headless Binary Ninja MCP server
      After=network.target

      [Service]
      Type=simple
      ExecStart=__BINJAD_EXECUTABLE__
      Restart=always
      RestartSec=10

      [Install]
      WantedBy=default.target
    SYSTEMD
    (prefix/"binjad.service").write unit.sub("__BINJAD_EXECUTABLE__", (opt_bin/"binjad").to_s)
  end

  post_install_steps do
    on_macos do
      run "/usr/bin/install_name_tool",
          args:           ["-delete_rpath", "@loader_path", "{{libexec}}/binjad-runtime"],
          must_succeed:   false,
          writable_paths: ["{{libexec}}/binjad-runtime"]
      run "/usr/bin/install_name_tool",
          args:           ["-add_rpath", "@loader_path", "{{libexec}}/binjad-runtime"],
          writable_paths: ["{{libexec}}/binjad-runtime"]
      run "/usr/bin/codesign",
          args:           ["--force", "--sign", "-", "--timestamp=none", "{{libexec}}/binjad-runtime"],
          writable_paths: ["{{libexec}}/binjad-runtime"]
      run "/usr/bin/xattr",
          args:           ["-c", "{{libexec}}/binjad-menubar.app/Contents/Resources/menubar.png"],
          writable_paths: ["{{libexec}}/binjad-menubar.app"]
      run "/usr/bin/codesign",
          args:           ["--force", "--sign", "-", "--timestamp=none", "{{libexec}}/binjad-menubar.app"],
          writable_paths: ["{{libexec}}/binjad-menubar.app"]
    end
  end

  def caveats
    requirement = <<~EOS
      binjad requires Binary Ninja 6.1.10823 development build and a license that permits headless operation.
      Binary Ninja is not included in this package.
      This development formula shares its service and configuration with stable binjad.
      Stop the stable service before starting this formula.
    EOS

    if OS.mac?
      return requirement + <<~EOS

        Install Binary Ninja at:
          /Applications/Binary Ninja.app
        For another location, set binary_ninja.installation_dir in:
          ~/Library/Application Support/binjad/config.json
      EOS
    end

    requirement + <<~EOS

      Install Binary Ninja at ~/binaryninja by default.
      For another location, set binary_ninja.installation_dir in:
        ~/.local/share/binjad/config.json
    EOS
  end

  service do
    name macos: "me.cynder.binjad", linux: "binjad"
  end

  test do
    assert_predicate bin/"binjad", :executable?
    assert_predicate libexec/"binjad-runtime", :executable?
    assert_path_exists share/"binjad/portal/index.html"
    assert_path_exists share/"binjad/portal/setup.html"
    assert_path_exists share/"binjad/portal/setup.js"

    %w[binaryninjacore kernelcache sharedcache debuggercore].each do |library|
      assert_empty prefix.glob("**/*#{library}*")
    end

    if OS.mac?
      assert_path_exists libexec/"binjad-menubar.app/Contents/MacOS/binjad-menubar"
      assert_match "<key>MachServices</key>", (prefix/"me.cynder.binjad.plist").read
      system "/usr/bin/codesign", "--verify", "--strict", libexec/"binjad-menubar.app"
    else
      refute_match "EnvironmentFile", (prefix/"binjad.service").read
    end

    output = shell_output("#{bin}/binjad --invalid-option 2>&1", 1)
    assert_match "unknown argument: --invalid-option", output
  end
end
