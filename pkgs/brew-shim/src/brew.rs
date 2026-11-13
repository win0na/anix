use std::process::{Command, ExitStatus};

use crate::config::Config;
use crate::exec::{self, CliError};

fn ensure_real(config: &Config) -> Result<(), CliError> {
    if config.brew_real.exists() {
        Ok(())
    } else {
        Err(CliError::new(format!(
            "Homebrew not found at {} (set ANIX_BREW_REAL)",
            config.brew_real.display()
        )))
    }
}

fn command(config: &Config, args: &[String]) -> Command {
    let mut command = Command::new(&config.brew_real);
    command.args(args);
    // Nested Homebrew invocations otherwise inherit the shim's own install
    // location and try to run themselves recursively.
    command.env_remove("HOMEBREW_PATH");
    command.env_remove("HOMEBREW_BREW_FILE");
    command
}

/// Run the real Homebrew with inherited stdio. Used for casks and bottle
/// fallbacks, where the user should see Homebrew's own output.
pub fn delegate(config: &Config, args: &[String]) -> Result<(), CliError> {
    ensure_real(config)?;
    let status = command(config, args)
        .status()
        .map_err(|err| exec::spawn_error(&config.brew_real.to_string_lossy(), err))?;
    status_result(status)
}

/// Run the real Homebrew and capture stdout. Missing or failing Homebrew is
/// treated as "no output", which keeps port-only commands usable.
pub fn capture(config: &Config, args: &[String]) -> Option<String> {
    if !config.brew_real.exists() {
        return None;
    }
    let output = command(config, args).output().ok()?;
    if !output.status.success() {
        return None;
    }
    Some(exec::text(&output.stdout))
}

pub fn formulae(config: &Config) -> Vec<String> {
    capture(config, &["list".into(), "--formula".into()])
        .map(|text| {
            text.lines()
                .map(str::trim)
                .filter(|line| !line.is_empty() && !line.contains(char::is_whitespace))
                .map(str::to_string)
                .collect()
        })
        .unwrap_or_default()
}

pub fn has_formula(config: &Config, name: &str) -> bool {
    formulae(config).iter().any(|formula| formula == name)
}

fn status_result(status: ExitStatus) -> Result<(), CliError> {
    if status.success() {
        Ok(())
    } else {
        Err(CliError::silent(status.code().unwrap_or(1)))
    }
}
