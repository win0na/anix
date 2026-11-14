use crate::exec::CliError;
use crate::port;

/// Homebrew names that do not exist verbatim in MacPorts.
const CURATED: &[(&str, &str)] = &[
    ("python@3.10", "python310"),
    ("python@3.11", "python311"),
    ("python@3.12", "python312"),
    ("python@3.13", "python313"),
    ("node", "nodejs22"),
    ("node@20", "nodejs20"),
    ("node@22", "nodejs22"),
    ("openssl@3", "openssl3"),
    ("openssl@1.1", "openssl11"),
    ("gnu-sed", "gsed"),
    ("gnu-tar", "gnutar"),
    ("gnu-grep", "ggrep"),
    ("gnu-coreutils", "coreutils"),
    ("gnu-findutils", "findutils"),
    ("postgresql@14", "postgresql14"),
    ("postgresql@15", "postgresql15"),
    ("postgresql@16", "postgresql16"),
    ("ruby@3.2", "ruby32"),
    ("ruby@3.3", "ruby33"),
    ("php@8.3", "php83"),
    ("mysql", "mysql8"),
];

pub fn curated(name: &str) -> Option<&'static str> {
    CURATED
        .iter()
        .find(|(formula, _)| *formula == name)
        .map(|(_, port_name)| *port_name)
}

/// The Homebrew name a port stands in for, when the map has one. Used by
/// `brew list` so a script grepping for `openssl@3` sees an installed
/// `openssl3`.
pub fn brew_name(port_name: &str) -> Option<&'static str> {
    CURATED
        .iter()
        .find(|(_, port)| *port == port_name)
        .map(|(formula, _)| *formula)
}

/// Translate a Homebrew formula name into a MacPorts port name, consulting
/// the curated map, then the installed set, then an exact name search.
/// Unknown names produce an error listing fuzzy-search candidates.
pub fn resolve(formula: &str) -> Result<String, CliError> {
    if let Some(port_name) = curated(formula) {
        return Ok(port_name.to_string());
    }

    let installed = port::installed()?;
    if installed.iter().any(|entry| entry.name == formula) {
        return Ok(formula.to_string());
    }

    let exact = port::search_exact(formula)?;
    if let Some(name) = exact
        .iter()
        .find(|name| name.as_str() == formula)
        .or_else(|| exact.first())
    {
        return Ok(name.clone());
    }

    let candidates = port::search(formula)?;
    let hint = if candidates.is_empty() {
        String::new()
    } else {
        format!("\nCandidates: {}", candidates.join(", "))
    };
    Err(CliError::new(format!(
        "No available formula with the name \"{}\".{}",
        formula, hint
    )))
}

/// Resolution used by dry runs: never touches port, so a preview cannot
/// mutate or even query the system.
pub fn preview(formula: &str) -> String {
    curated(formula)
        .map(str::to_string)
        .unwrap_or_else(|| formula.to_string())
}
