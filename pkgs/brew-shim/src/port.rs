use std::process::Output;

use crate::exec::{self, CliError};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InstalledPort {
    pub name: String,
    pub version: String,
    pub active: bool,
}

pub fn installed() -> Result<Vec<InstalledPort>, CliError> {
    let out = run(&["-q", "installed"])?;
    if !out.status.success() {
        return Err(CliError::new("failed to list installed ports"));
    }
    Ok(parse_installed(&exec::text(&out.stdout)))
}

/// Names printed by `port search --name --exact`.
pub fn search_exact(name: &str) -> Result<Vec<String>, CliError> {
    let out = run(&["-q", "search", "--name", "--exact", name])?;
    if !out.status.success() {
        return Ok(Vec::new());
    }
    Ok(parse_name_lines(&exec::text(&out.stdout), None))
}

/// Names printed by a fuzzy `port search --name`.
pub fn search(name: &str) -> Result<Vec<String>, CliError> {
    let out = run(&["-q", "search", "--name", name])?;
    if !out.status.success() {
        return Ok(Vec::new());
    }
    Ok(parse_name_lines(&exec::text(&out.stdout), None))
}

pub fn leaves() -> Result<Vec<String>, CliError> {
    let out = run(&["-q", "echo", "leaves"])?;
    if !out.status.success() {
        return Ok(Vec::new());
    }
    Ok(parse_name_lines(&exec::text(&out.stdout), None))
}

pub fn deps(name: &str) -> Result<Vec<String>, CliError> {
    port_relation("deps", name)
}

pub fn dependents(name: &str) -> Result<Vec<String>, CliError> {
    port_relation("dependents", name)
}

fn port_relation(subcommand: &str, name: &str) -> Result<Vec<String>, CliError> {
    let out = run(&["-q", subcommand, name])?;
    if !out.status.success() {
        return Err(CliError::new(format!(
            "failed to query {} for {}",
            subcommand, name
        )));
    }
    Ok(parse_name_lines(&exec::text(&out.stdout), Some(name)))
}

pub fn outdated() -> Result<Vec<(String, String, String)>, CliError> {
    let out = run(&["-q", "outdated"])?;
    if !out.status.success() {
        return Ok(Vec::new());
    }
    Ok(parse_outdated(&exec::text(&out.stdout)))
}

pub fn version() -> Option<String> {
    let out = run(&["version"]).ok()?;
    if !out.status.success() {
        return None;
    }
    let text = exec::text(&out.stdout);
    let line = text.lines().next()?.trim();
    Some(
        line.strip_prefix("Version:")
            .map(str::trim)
            .unwrap_or(line)
            .to_string(),
    )
}

fn run(args: &[&str]) -> Result<Output, CliError> {
    let owned: Vec<String> = args.iter().map(|arg| arg.to_string()).collect();
    exec::output("port", &owned)
}

/// Parse `port -q installed` output:
///
/// ```text
///   python312 @3.12.7_0+universal (active)
///   nodejs22 @22.9.0_0
/// ```
pub fn parse_installed(text: &str) -> Vec<InstalledPort> {
    let mut ports = Vec::new();
    for line in text.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.ends_with(':') {
            continue;
        }
        let mut fields = trimmed.split_whitespace();
        let Some(name) = fields.next() else { continue };
        if !is_port_name(name) || name.eq_ignore_ascii_case("none") {
            continue;
        }
        let version = fields
            .next()
            .map(|token| token.trim_start_matches('@').to_string())
            .unwrap_or_default();
        if version.is_empty() {
            continue;
        }
        ports.push(InstalledPort {
            name: name.to_string(),
            version,
            active: trimmed.contains("(active)"),
        });
    }
    ports
}

/// `port -q info --line --name --version --revision <port>` prints the fields
/// on one line, but accept newline-separated output as well.
pub fn parse_info(text: &str) -> Option<(String, String)> {
    let fields: Vec<&str> = text.split_whitespace().collect();
    let name = fields.first()?.to_string();
    if !is_port_name(&name) {
        return None;
    }
    let version = match fields.as_slice() {
        [_, version, revision, ..] if *revision != "0" => format!("{}_{}", version, revision),
        [_, version, ..] => (*version).to_string(),
        _ => return None,
    };
    Some((name, version))
}

/// Parse `port outdated` lines shaped `name old < new`.
pub fn parse_outdated(text: &str) -> Vec<(String, String, String)> {
    let mut rows = Vec::new();
    for line in text.lines() {
        let fields: Vec<&str> = line.split_whitespace().collect();
        let Some(arrow) = fields.iter().position(|field| *field == "<") else {
            continue;
        };
        if arrow == 0 || arrow + 1 >= fields.len() {
            continue;
        }
        let name = fields[0];
        if !is_port_name(name) {
            continue;
        }
        rows.push((
            name.to_string(),
            fields[arrow - 1].trim_start_matches('@').to_string(),
            fields[arrow + 1].trim_start_matches('@').to_string(),
        ));
    }
    rows
}

/// Extract port names from `port search`, `port deps`, `port echo leaves`
/// listings. The first whitespace-delimited field is the port name; headers,
/// version-only continuations and the queried port itself are dropped.
pub fn parse_name_lines(text: &str, exclude: Option<&str>) -> Vec<String> {
    let mut names = Vec::new();
    for line in text.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        if trimmed.ends_with(':') || trimmed.starts_with("The following") {
            continue;
        }
        let Some(token) = trimmed.split_whitespace().next() else {
            continue;
        };
        let name = token.trim_start_matches('@');
        if !is_port_name(name) {
            continue;
        }
        if Some(name) == exclude {
            continue;
        }
        if !names.iter().any(|existing| existing == name) {
            names.push(name.to_string());
        }
    }
    names
}

pub fn is_port_name(name: &str) -> bool {
    !name.is_empty()
        && name
            .chars()
            .all(|ch| ch.is_ascii_alphanumeric() || "-_.+".contains(ch))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_installed_variants_and_active_marker() {
        let text = "\
The following ports are currently installed:
  python312 @3.12.7_0+universal (active)
  nodejs22 @22.9.0_0
  openssl3 @3.3.2_0 (active)
";
        let ports = parse_installed(text);
        assert_eq!(ports.len(), 3);
        assert_eq!(ports[0].name, "python312");
        assert_eq!(ports[0].version, "3.12.7_0+universal");
        assert!(ports[0].active);
        assert_eq!(ports[1].version, "22.9.0_0");
        assert!(!ports[1].active);
        assert!(ports[2].active);
    }

    #[test]
    fn parses_info_on_one_line_and_indented_fields() {
        assert_eq!(
            parse_info("python312 3.12.7 0"),
            Some(("python312".into(), "3.12.7".into()))
        );
        assert_eq!(
            parse_info("python312 3.12.7 2"),
            Some(("python312".into(), "3.12.7_2".into()))
        );
    }

    #[test]
    fn parses_outdated_into_brew_shape() {
        let rows = parse_outdated("python312 3.12.7_0 < 3.12.8_0\n");
        assert_eq!(
            rows,
            vec![("python312".into(), "3.12.7_0".into(), "3.12.8_0".into())]
        );
    }
}
