use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::sync::atomic::{AtomicU32, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

const PREFIX: &str = "/fixture/prefix";

struct Fixture {
    dir: PathBuf,
    bin: PathBuf,
}

impl Fixture {
    fn new() -> Self {
        static COUNTER: AtomicU32 = AtomicU32::new(0);
        let unique = format!(
            "brew-shim-test-{}-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .expect("clock before epoch")
                .as_nanos(),
            COUNTER.fetch_add(1, Ordering::SeqCst)
        );
        let dir = std::env::temp_dir().join(unique);
        let bin = dir.join("bin");
        fs::create_dir_all(&bin).expect("create fixture bin");
        let fixture = Self { dir, bin };
        fixture.install_stubs();
        fixture
    }

    fn install_stubs(&self) {
        self.script(
            "port",
            r#"#!/bin/sh
printf 'port %s\n' "$*" >> "$STUB_DIR/port.log"
case "$*" in
  "-q installed")
    [ -f "$STUB_DIR/installed.txt" ] && cat "$STUB_DIR/installed.txt"
    ;;
  "-q info --line --name --version --revision "*)
    [ -f "$STUB_DIR/info.txt" ] && cat "$STUB_DIR/info.txt"
    ;;
  "-q search --name --exact "*)
    [ -f "$STUB_DIR/search_exact.txt" ] && cat "$STUB_DIR/search_exact.txt"
    ;;
  "-q search --name "*)
    [ -f "$STUB_DIR/search.txt" ] && cat "$STUB_DIR/search.txt"
    ;;
  "-q outdated")
    [ -f "$STUB_DIR/outdated.txt" ] && cat "$STUB_DIR/outdated.txt"
    ;;
  "-q deps "*)
    [ -f "$STUB_DIR/deps.txt" ] && cat "$STUB_DIR/deps.txt"
    ;;
  "-q echo depof:"*)
    [ -f "$STUB_DIR/depof.txt" ] && cat "$STUB_DIR/depof.txt"
    ;;
  "-q echo rdepof:"*)
    [ -f "$STUB_DIR/rdepof.txt" ] && cat "$STUB_DIR/rdepof.txt"
    ;;
  "-q echo dependentof:"*)
    [ -f "$STUB_DIR/dependentof.txt" ] && cat "$STUB_DIR/dependentof.txt"
    ;;
  "-q dependents "*)
    [ -f "$STUB_DIR/dependents.txt" ] && cat "$STUB_DIR/dependents.txt"
    ;;
  "-q echo leaves")
    [ -f "$STUB_DIR/leaves.txt" ] && cat "$STUB_DIR/leaves.txt"
    ;;
  "-b install "*)
    if [ -f "$STUB_DIR/install_failure.txt" ]; then
      cat "$STUB_DIR/install_failure.txt" >&2
      exit 1
    fi
    ;;
  "version")
    echo "Version: 2.10.1"
    ;;
esac
exit 0
"#,
        );

        self.script(
            "sudo",
            r#"#!/bin/sh
printf 'sudo %s\n' "$*" >> "$STUB_DIR/sudo.log"
if [ "$1" = "-n" ]; then
  if [ "${STUB_SUDO_PASSWORD:-0}" = "1" ]; then
    echo "sudo: a password is required" >&2
    exit 1
  fi
  shift
fi
exec "$@"
"#,
        );

        self.script(
            "brew",
            r#"#!/bin/sh
printf 'brew %s\n' "$*" >> "$STUB_DIR/brew.log"
if [ -n "${HOMEBREW_PATH+x}" ]; then
  echo "HOMEBREW_PATH=$HOMEBREW_PATH" >> "$STUB_DIR/brew.env"
fi
if [ -n "${HOMEBREW_BREW_FILE+x}" ]; then
  echo "HOMEBREW_BREW_FILE=$HOMEBREW_BREW_FILE" >> "$STUB_DIR/brew.env"
fi
case "$*" in
  "--caskroom") echo "/usr/local/Caskroom" ;;
  "list --formula")
    [ -f "$STUB_DIR/brew_list.txt" ] && cat "$STUB_DIR/brew_list.txt"
    ;;
  "list --versions")
    [ -f "$STUB_DIR/brew_versions.txt" ] && cat "$STUB_DIR/brew_versions.txt"
    ;;
  "leaves")
    [ -f "$STUB_DIR/brew_leaves.txt" ] && cat "$STUB_DIR/brew_leaves.txt"
    ;;
  "search "*)
    [ -f "$STUB_DIR/brew_search.txt" ] && cat "$STUB_DIR/brew_search.txt"
    ;;
esac
exit 0
"#,
        );

        self.script(
            "launchctl",
            r#"#!/bin/sh
[ -f "$STUB_DIR/launchctl.txt" ] && cat "$STUB_DIR/launchctl.txt"
exit 0
"#,
        );
    }

    fn script(&self, name: &str, body: &str) {
        let path = self.bin.join(name);
        fs::write(&path, body).expect("write stub");
        let mut permissions = fs::metadata(&path).expect("stub metadata").permissions();
        permissions.set_mode(0o755);
        fs::set_permissions(&path, permissions).expect("chmod stub");
    }

    fn write(&self, name: &str, contents: &str) {
        fs::write(self.dir.join(name), contents).expect("write fixture file");
    }

    fn command(&self, args: &[&str], envs: &[(&str, &str)]) -> Command {
        let mut command = Command::new(env!("CARGO_BIN_EXE_brew"));
        let inherited_path = std::env::var("PATH").unwrap_or_default();
        command
            .args(args)
            .env("PATH", format!("{}:{}", self.bin.display(), inherited_path))
            .env("STUB_DIR", &self.dir)
            .env("ANIX_MACPORTS_PREFIX", PREFIX)
            .env("ANIX_BREW_REAL", self.bin.join("brew"))
            .env("SHELL", "/bin/bash")
            .env_remove("ANIX_BREW_VERSION");
        for (key, value) in envs {
            command.env(key, value);
        }
        command
    }

    fn run(&self, args: &[&str]) -> Output {
        self.command(args, &[]).output().expect("run brew shim")
    }

    fn run_env(&self, args: &[&str], envs: &[(&str, &str)]) -> Output {
        self.command(args, envs).output().expect("run brew shim")
    }

    fn log(&self, name: &str) -> Option<String> {
        fs::read_to_string(self.dir.join(name)).ok()
    }

    fn log_exists(&self, name: &str) -> bool {
        Path::new(&self.dir.join(name)).exists()
    }
}

impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.dir);
    }
}

fn stdout(output: &Output) -> String {
    String::from_utf8_lossy(&output.stdout).into_owned()
}

fn stderr(output: &Output) -> String {
    String::from_utf8_lossy(&output.stderr).into_owned()
}

fn code(output: &Output) -> i32 {
    output.status.code().expect("process was signalled")
}

#[test]
fn lists_ports_and_brew_formulae_deduped_and_sorted() {
    let fixture = Fixture::new();
    fixture.write(
        "installed.txt",
        "\
The following ports are currently installed:
  python312 @3.12.7_0+universal (active)
  sharedport @1.0_0
",
    );
    fixture.write("brew_list.txt", "sharedport\nnodejs22\n");

    let output = fixture.run(&["list"]);
    assert_eq!(code(&output), 0, "stderr: {}", stderr(&output));
    assert_eq!(stdout(&output), "nodejs22\npython@3.12\nsharedport\n");
}

#[test]
fn list_versions_keeps_ports_winning_over_brew() {
    let fixture = Fixture::new();
    fixture.write(
        "installed.txt",
        "  python312 @3.12.7_0+universal (active)\n",
    );
    fixture.write("brew_versions.txt", "nodejs22 22.9.0\n");

    let output = fixture.run(&["list", "--versions"]);
    assert_eq!(code(&output), 0, "stderr: {}", stderr(&output));
    assert_eq!(
        stdout(&output),
        "nodejs22 22.9.0\npython@3.12 3.12.7\n"
    );
}

#[test]
fn prefix_reports_installed_port_and_rejects_unknown_formula() {
    let fixture = Fixture::new();
    fixture.write(
        "installed.txt",
        "  python312 @3.12.7_0+universal (active)\n",
    );
    fixture.write("search_exact.txt", "");
    fixture.write("search.txt", "foobar1 @1.0\nfoobar2 @2.0\n");

    let installed = fixture.run(&["--prefix", "python312"]);
    assert_eq!(code(&installed), 0, "stderr: {}", stderr(&installed));
    // Without the activation layout there is no opt link, so the prefix itself
    // is the honest answer; it always exists.
    assert_eq!(stdout(&installed), format!("{PREFIX}\n"));

    let prefix = fixture.dir.join("prefix");
    fs::create_dir_all(prefix.join("opt")).expect("create test prefix");
    std::os::unix::fs::symlink(&prefix, prefix.join("opt/python312")).expect("link port");
    let linked = fixture.run_env(
        &["--prefix", "python312"],
        &[("ANIX_MACPORTS_PREFIX", prefix.to_str().expect("utf-8 path"))],
    );
    assert_eq!(code(&linked), 0, "stderr: {}", stderr(&linked));
    assert_eq!(
        stdout(&linked),
        format!("{}/opt/python312\n", prefix.display())
    );

    let unknown = fixture.run(&["--prefix", "foobar"]);
    assert_eq!(code(&unknown), 1);
    let message = stderr(&unknown);
    assert!(
        message.contains("No available formula with the name \"foobar\""),
        "stderr: {}",
        message
    );
    assert!(message.contains("foobar1"), "stderr: {}", message);
}

#[test]
fn dry_run_prints_command_without_touching_port_or_sudo() {
    let fixture = Fixture::new();

    let output = fixture.run(&["install", "--dry-run", "python@3.12"]);
    assert_eq!(code(&output), 0, "stderr: {}", stderr(&output));
    assert_eq!(stdout(&output), "sudo -n port -b install python312\n");
    assert!(!fixture.log_exists("port.log"), "dry run invoked port");
    assert!(!fixture.log_exists("sudo.log"), "dry run invoked sudo");
}

#[test]
fn missing_archive_falls_back_to_brew_with_clean_environment() {
    let fixture = Fixture::new();
    fixture.write("search_exact.txt", "foo @1.0\n");
    fixture.write(
        "install_failure.txt",
        "Error: Failed to archivefetch foo: version @1.0_0: The requested URL returned error: 404\n",
    );

    let output = fixture.run_env(
        &["install", "foo"],
        &[
            ("HOMEBREW_PATH", "/old/homebrew"),
            ("HOMEBREW_BREW_FILE", "/old/homebrew/bin/brew"),
        ],
    );
    assert_eq!(code(&output), 0, "stderr: {}", stderr(&output));

    let brew_log = fixture.log("brew.log").expect("brew was not called");
    assert!(
        brew_log.contains("brew install foo"),
        "brew log: {}",
        brew_log
    );
    let brew_env = fixture.log("brew.env").unwrap_or_default();
    assert!(
        brew_env.is_empty(),
        "Homebrew inherited shim variables: {}",
        brew_env
    );
}

#[test]
fn archivefetch_server_error_is_reported_without_brew_fallback() {
    let fixture = Fixture::new();
    fixture.write("search_exact.txt", "foo @1.0\n");
    fixture.write(
        "install_failure.txt",
        "Error: Failed to archivefetch foo: version @1.0_0: The requested URL returned error: 500\n",
    );

    let output = fixture.run(&["install", "foo"]);
    assert_eq!(code(&output), 1, "stderr: {}", stderr(&output));
    assert!(
        !fixture.log_exists("brew.log"),
        "a server error must not fall back to Homebrew"
    );
}

#[test]
fn archivefetch_connection_reset_does_not_fall_back() {
    let fixture = Fixture::new();
    fixture.write("search_exact.txt", "foo @1.0\n");
    fixture.write(
        "install_failure.txt",
        "Error: Failed to archivefetch foo: version @1.0_0: Connection reset by peer\n",
    );

    let output = fixture.run(&["install", "foo"]);
    assert_eq!(code(&output), 1, "stderr: {}", stderr(&output));
    assert!(
        !fixture.log_exists("brew.log"),
        "a connection error must not fall back to Homebrew"
    );
}

#[test]
fn archivefetch_network_error_is_reported_without_brew_fallback() {
    let fixture = Fixture::new();
    fixture.write("search_exact.txt", "foo @1.0\n");
    fixture.write(
        "install_failure.txt",
        "Error: Failed to archivefetch foo: version @1.0_0: Couldn't resolve host name\n",
    );

    let output = fixture.run(&["install", "foo"]);
    assert_eq!(code(&output), 1, "stderr: {}", stderr(&output));
    assert!(
        !fixture.log_exists("brew.log"),
        "a network error must not fall back to Homebrew"
    );
}

#[test]
fn deps_is_recursive_and_direct_is_opt_in() {
    let fixture = Fixture::new();
    fixture.write("search_exact.txt", "wget @1.24.5_0 (www)\n");
    fixture.write("rdepof.txt", "libidn2\nopenssl3\nzlib\n");
    fixture.write("depof.txt", "libidn2\n");

    let output = fixture.run(&["deps", "wget"]);
    assert_eq!(code(&output), 0, "stderr: {}", stderr(&output));
    assert_eq!(stdout(&output), "libidn2\nopenssl3\nzlib\n");
    let port_log = fixture.log("port.log").expect("port was not called");
    assert!(port_log.contains("-q echo rdepof:wget"), "port log: {}", port_log);

    let direct = fixture.run(&["deps", "--direct", "wget"]);
    assert_eq!(code(&direct), 0, "stderr: {}", stderr(&direct));
    assert_eq!(stdout(&direct), "libidn2\n");
}

#[test]
fn other_port_failure_is_reported_and_does_not_call_brew() {
    let fixture = Fixture::new();
    fixture.write("search_exact.txt", "foo @1.0\n");
    fixture.write("install_failure.txt", "Error: failed to fetch archive\n");

    let output = fixture.run(&["install", "foo"]);
    assert_eq!(code(&output), 1);
    assert!(
        stderr(&output).contains("failed to fetch archive"),
        "stderr: {}",
        stderr(&output)
    );
    assert!(
        !fixture.log_exists("brew.log"),
        "brew must not be called for a non-archive failure"
    );
}

#[test]
fn cask_install_delegates_to_real_brew_with_clean_environment() {
    let fixture = Fixture::new();

    let output = fixture.run_env(
        &["install", "--cask", "iterm2"],
        &[
            ("HOMEBREW_PATH", "/old/homebrew"),
            ("HOMEBREW_BREW_FILE", "/old/homebrew/bin/brew"),
        ],
    );
    assert_eq!(code(&output), 0, "stderr: {}", stderr(&output));

    let brew_log = fixture.log("brew.log").expect("brew was not called");
    assert!(
        brew_log.contains("brew install --cask iterm2"),
        "brew log: {}",
        brew_log
    );
    let brew_env = fixture.log("brew.env").unwrap_or_default();
    assert!(
        brew_env.is_empty(),
        "Homebrew inherited shim variables: {}",
        brew_env
    );
    assert!(
        !fixture.log_exists("sudo.log"),
        "casks must not be installed through port"
    );
}

#[test]
fn cask_without_real_brew_names_the_missing_path() {
    let fixture = Fixture::new();
    let missing = fixture.dir.join("no-such-brew");

    let output = fixture.run_env(
        &["install", "--cask", "iterm2"],
        &[("ANIX_BREW_REAL", missing.to_str().unwrap())],
    );
    assert_eq!(code(&output), 1);
    let message = stderr(&output);
    assert!(
        message.contains("Homebrew not found at"),
        "stderr: {}",
        message
    );
    assert!(
        message.contains(missing.to_str().unwrap()),
        "stderr: {}",
        message
    );
}

#[test]
fn brew_owned_commands_delegate_and_json_stays_rejected() {
    let fixture = Fixture::new();

    let tap = fixture.run(&["tap", "homebrew/core"]);
    assert_eq!(code(&tap), 0, "stderr: {}", stderr(&tap));
    let brew_log = fixture.log("brew.log").expect("brew was not called");
    assert!(
        brew_log.contains("brew tap homebrew/core"),
        "brew log: {}",
        brew_log
    );

    let switch = fixture.run(&["switch", "openjdk"]);
    assert_eq!(code(&switch), 1);
    assert!(
        stderr(&switch).contains("not supported"),
        "stderr: {}",
        stderr(&switch)
    );

    let json = fixture.run(&["outdated", "--json"]);
    assert_eq!(code(&json), 1);
    assert!(
        stderr(&json).contains("not supported"),
        "stderr: {}",
        stderr(&json)
    );

    let cask_json = fixture.run(&["install", "--cask", "--json=v2", "iterm2"]);
    assert_eq!(code(&cask_json), 0, "stderr: {}", stderr(&cask_json));
    let brew_log = fixture.log("brew.log").expect("brew was not called");
    assert!(
        brew_log.contains("install --cask --json=v2 iterm2"),
        "brew log: {}",
        brew_log
    );
}

#[test]
fn shellenv_emits_bash_and_fish_forms() {
    let fixture = Fixture::new();

    let bash = fixture.run(&["shellenv", "bash"]);
    assert_eq!(code(&bash), 0, "stderr: {}", stderr(&bash));
    let bash_output = stdout(&bash);
    assert!(
        bash_output.contains(&format!("export HOMEBREW_PREFIX=\"{}\";", PREFIX)),
        "stdout: {}",
        bash_output
    );
    assert!(bash_output.contains(&format!("export PATH=\"{}/bin", PREFIX)));
    assert!(bash_output.contains("export MANPATH="));
    assert!(bash_output.contains("export INFOPATH="));

    let fish = fixture.run(&["shellenv", "fish"]);
    assert_eq!(code(&fish), 0, "stderr: {}", stderr(&fish));
    let fish_output = stdout(&fish);
    assert!(
        fish_output.contains(&format!("set -gx HOMEBREW_PREFIX \"{}\";", PREFIX)),
        "stdout: {}",
        fish_output
    );
    assert!(fish_output.contains("set -gx PATH "));
}

#[test]
fn services_list_reads_launchctl_state() {
    let fixture = Fixture::new();
    fixture.write(
        "launchctl.txt",
        "123 0 org.macports.redis\n- 0 org.macports.mysql8\n",
    );

    let output = fixture.run(&["services", "list"]);
    assert_eq!(code(&output), 0, "stderr: {}", stderr(&output));
    assert_eq!(stdout(&output), "mysql8 stopped\nredis started\n");
}

#[test]
fn info_reports_stable_version_and_installed_state() {
    let fixture = Fixture::new();
    fixture.write("installed.txt", "  python312 @3.12.7_0 (active)\n");
    fixture.write("info.txt", "python312 3.12.7 0\n");

    let output = fixture.run(&["info", "python@3.12"]);
    assert_eq!(code(&output), 0, "stderr: {}", stderr(&output));
    assert_eq!(stdout(&output), "==> python312: stable 3.12.7\nInstalled\n");
}

#[test]
fn version_and_caskroom_come_from_the_configured_values() {
    let fixture = Fixture::new();

    let version = fixture.run(&["--version"]);
    assert_eq!(code(&version), 0);
    assert_eq!(stdout(&version), "Homebrew 7.0.13\n");

    let caskroom = fixture.run(&["--caskroom"]);
    assert_eq!(code(&caskroom), 0, "stderr: {}", stderr(&caskroom));
    assert_eq!(stdout(&caskroom), "/usr/local/Caskroom\n");
}

#[test]
fn sudo_password_failure_suggests_an_interactive_command() {
    let fixture = Fixture::new();
    fixture.write("search_exact.txt", "foo @1.0\n");

    let output = fixture.run_env(&["install", "foo"], &[("STUB_SUDO_PASSWORD", "1")]);
    assert_eq!(code(&output), 1);
    let message = stderr(&output);
    assert!(
        message.contains("run: sudo port -b install foo"),
        "stderr: {}",
        message
    );
    assert!(
        !fixture.log_exists("brew.log"),
        "a sudo failure must not fall back to Homebrew"
    );
}

#[test]
fn brew_installed_formula_uninstalls_through_brew() {
    let fixture = Fixture::new();
    fixture.write("installed.txt", "  otherport @1.0_0\n");
    fixture.write("brew_list.txt", "foo\n");

    let output = fixture.run(&["uninstall", "foo"]);
    assert_eq!(code(&output), 0, "stderr: {}", stderr(&output));
    let brew_log = fixture.log("brew.log").expect("brew was not called");
    assert!(
        brew_log.contains("brew uninstall foo"),
        "brew log: {}",
        brew_log
    );
    assert!(
        !fixture.log_exists("sudo.log"),
        "brew formulae must not be uninstalled through port"
    );
}

#[test]
fn upgrade_with_a_formula_upgrades_that_port() {
    let fixture = Fixture::new();
    fixture.write("installed.txt", "  wget @1.24.5_0 (active)\n");
    fixture.write("search_exact.txt", "wget @1.24.5_0 (www)\n");

    let output = fixture.run(&["upgrade", "wget"]);
    assert_eq!(code(&output), 0, "stderr: {}", stderr(&output));
    let sudo_log = fixture.log("sudo.log").expect("sudo was not called");
    assert!(sudo_log.contains("upgrade wget"), "sudo log: {}", sudo_log);
}

#[test]
fn prefix_falls_back_to_brew_for_brew_installed_formula() {
    let fixture = Fixture::new();
    fixture.write("installed.txt", "  otherport @1.0_0\n");
    fixture.write("brew_list.txt", "cocoapods\n");
    fixture.write("search_exact.txt", "");

    let output = fixture.run(&["--prefix", "cocoapods"]);
    assert_eq!(code(&output), 0, "stderr: {}", stderr(&output));
    let brew_log = fixture.log("brew.log").expect("brew was not called");
    assert!(
        brew_log.contains("brew --prefix cocoapods"),
        "brew log: {}",
        brew_log
    );
}

#[test]
fn info_marks_brew_installed_formula_as_installed() {
    let fixture = Fixture::new();
    fixture.write("installed.txt", "");
    fixture.write("info.txt", "python312\t3.12.7\t0\n");
    fixture.write("search_exact.txt", "python312 @3.12.7_0 (lang)\n");
    fixture.write("brew_list.txt", "python312\n");

    let output = fixture.run(&["info", "python312"]);
    assert_eq!(code(&output), 0, "stderr: {}", stderr(&output));
    assert!(
        stdout(&output).contains("Installed"),
        "stdout: {}",
        stdout(&output)
    );
}

#[test]
fn leading_v_is_verbose_not_version() {
    let fixture = Fixture::new();
    fixture.write("search_exact.txt", "wget @1.24.5_0 (www)\n");

    let output = fixture.run(&["-v", "install", "wget"]);
    assert_eq!(code(&output), 0, "stderr: {}", stderr(&output));
    assert!(
        !stdout(&output).contains("Homebrew 7.0.13"),
        "stdout: {}",
        stdout(&output)
    );
    let port_log = fixture.log("port.log").expect("port was not called");
    assert!(port_log.contains("-b install wget"), "port log: {}", port_log);
}

#[test]
fn versions_keep_every_installed_revision() {
    let fixture = Fixture::new();
    fixture.write(
        "installed.txt",
        "  wget @1.21.4_0 (active)\n  wget @1.21.5_0\n",
    );

    let output = fixture.run(&["list", "--versions"]);
    assert_eq!(code(&output), 0, "stderr: {}", stderr(&output));
    assert_eq!(stdout(&output), "wget 1.21.4 1.21.5\n");
}

#[test]
fn revision_only_outdated_keeps_raw_versions() {
    let fixture = Fixture::new();
    fixture.write("outdated.txt", "python312  3.12.7_0 < 3.12.7_1\n");

    let output = fixture.run(&["outdated"]);
    assert_eq!(code(&output), 0, "stderr: {}", stderr(&output));
    assert_eq!(stdout(&output), "python312 (3.12.7_0) < 3.12.7_1\n");
}

#[test]
fn dependency_archive_miss_does_not_fall_back() {
    let fixture = Fixture::new();
    fixture.write("search_exact.txt", "wget @1.24.5_0 (www)\n");
    fixture.write(
        "install_failure.txt",
        "Error: Failed to archivefetch libdep: version @2.0_0: The requested URL returned error: 404\n",
    );

    let output = fixture.run(&["install", "wget"]);
    assert_eq!(code(&output), 1, "stderr: {}", stderr(&output));
    assert!(!fixture.log_exists("brew.log"), "a dependency miss must not call brew");
}

#[test]
fn repeated_verbose_is_not_a_version_request() {
    let fixture = Fixture::new();
    let output = fixture.run(&["-v", "-v"]);
    assert_eq!(code(&output), 0);
    assert!(stdout(&output).contains("Usage: brew"), "stdout: {}", stdout(&output));
    assert!(!stdout(&output).contains("Homebrew 7.0.13"));
}

#[test]
fn versions_keep_same_version_different_revision() {
    let fixture = Fixture::new();
    fixture.write(
        "installed.txt",
        "  wget @1.21.4_0 (active)\n  wget @1.21.4_1\n",
    );

    let output = fixture.run(&["list", "--versions"]);
    assert_eq!(code(&output), 0, "stderr: {}", stderr(&output));
    assert_eq!(stdout(&output), "wget 1.21.4 1.21.4_1\n");
}

#[test]
fn dependency_name_extension_does_not_fall_back() {
    let fixture = Fixture::new();
    fixture.write("search_exact.txt", "libidn @1.0_0 (mail)\n");
    fixture.write(
        "install_failure.txt",
        "Error: Failed to archivefetch libidn2: version @2.0_0: The requested URL returned error: 404\n",
    );

    let output = fixture.run(&["install", "libidn"]);
    assert_eq!(code(&output), 1, "stderr: {}", stderr(&output));
    assert!(!fixture.log_exists("brew.log"), "must not call brew");
}

#[test]
fn solo_v_still_prints_the_version() {
    let fixture = Fixture::new();
    let output = fixture.run(&["-v"]);
    assert_eq!(code(&output), 0, "stderr: {}", stderr(&output));
    assert_eq!(stdout(&output), "Homebrew 7.0.13\n");
}
