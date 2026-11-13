use std::io;
use std::process::{Command, Output};

#[derive(Debug)]
pub struct CliError {
    pub message: String,
    pub code: i32,
}

impl CliError {
    pub fn new(message: impl Into<String>) -> Self {
        Self {
            message: format!("Error: {}", message.into()),
            code: 1,
        }
    }

    pub fn silent(code: i32) -> Self {
        Self {
            message: String::new(),
            code,
        }
    }
}

/// Run a command, capturing stdout and stderr. Missing programs become a
/// user-facing error naming the command.
pub fn output(program: &str, args: &[String]) -> Result<Output, CliError> {
    Command::new(program)
        .args(args)
        .output()
        .map_err(|err| spawn_error(program, err))
}

pub fn spawn_error(program: &str, err: io::Error) -> CliError {
    if err.kind() == io::ErrorKind::NotFound {
        if program == "port" {
            CliError::new("MacPorts port not found on PATH")
        } else {
            CliError::new(format!("{} not found", program))
        }
    } else {
        CliError::new(format!("failed to run {}: {}", program, err))
    }
}

pub fn text(bytes: &[u8]) -> String {
    String::from_utf8_lossy(bytes).into_owned()
}

/// sudo reports a missing terminal or password in a handful of ways.
pub fn needs_password(stdout: &str, stderr: &str) -> bool {
    let combined = format!("{}\n{}", stdout, stderr).to_ascii_lowercase();
    combined.contains("a password is required")
        || combined.contains("no tty present")
        || combined.contains("a terminal is required")
        || combined.contains("askpass")
}

/// Locate an executable on PATH without spawning anything.
pub fn find_in_path(program: &str) -> Option<std::path::PathBuf> {
    use std::os::unix::fs::PermissionsExt;

    let path = std::env::var_os("PATH")?;
    std::env::split_paths(&path)
        .map(|dir| dir.join(program))
        .find(|candidate| {
            candidate
                .metadata()
                .map(|meta| meta.is_file() && meta.permissions().mode() & 0o111 != 0)
                .unwrap_or(false)
        })
}
