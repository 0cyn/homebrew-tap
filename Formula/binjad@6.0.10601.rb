class BinjadAT6010601 < Formula
  desc "Headless Binary Ninja MCP server"
  homepage "https://github.com/0cyn/binjad"
  url "https://github.com/0cyn/binjad.git",
      revision: "9d3496d71fc08139c303dee9df8d3bb2bfb1f8a7",
      using:    :git
  version "0.2.2"
  license "BSD-3-Clause"

  bottle do
    root_url "https://ghcr.io/v2/0cyn/tap"
    sha256 arm64_tahoe:  "557d1f228b0c328814a52407e1bfb723736d5ae18cb38ccc8438bcd46f29d5e1"
    sha256 arm64_linux:  "ff1398f346ebb44b0bbbd79fd2c304f078ccac48a14da2ad86b478449208c785"
    sha256 x86_64_linux: "794b8d2ee277d01b08c640143054759e8d68224bc4e42d30cf9f9f47e99964f8"
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
    # Binary Ninja stays external; the launcher supplies the validated user-installed runtime libraries.
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
      binjad requires Binary Ninja 6.0.10601 and a license that permits headless operation.
      Binary Ninja is not included in this package.
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
