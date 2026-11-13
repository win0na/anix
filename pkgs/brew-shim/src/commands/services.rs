use crate::exec::{self, CliError};

use super::mutate;

pub fn run(args: &[String]) -> Result<(), CliError> {
    match args.first().map(String::as_str) {
        None => list(),
        Some("list") => {
            if args.len() > 1 {
                return Err(CliError::new("services list takes no arguments"));
            }
            list()
        }
        Some("start") => control(args.get(1), "load"),
        Some("stop") => control(args.get(1), "unload"),
        Some(other) => Err(CliError::new(format!(
            "unsupported services command \"{}\"; use list, start or stop",
            other
        ))),
    }
}

fn list() -> Result<(), CliError> {
    let out = exec::output("launchctl", &["list".to_string()])?;
    if !out.status.success() {
        return Err(CliError::new("launchctl list failed"));
    }

    let mut services = Vec::new();
    for line in exec::text(&out.stdout).lines() {
        let fields: Vec<&str> = line.split_whitespace().collect();
        if fields.len() < 3 {
            continue;
        }
        let label = fields[fields.len() - 1];
        let Some(name) = label.strip_prefix("org.macports.") else {
            continue;
        };
        let started = fields[0] != "-";
        services.push((name.to_string(), started));
    }

    services.sort_by(|left, right| left.0.cmp(&right.0));
    for (name, started) in services {
        println!("{} {}", name, if started { "started" } else { "stopped" });
    }
    Ok(())
}

fn control(name: Option<&String>, action: &str) -> Result<(), CliError> {
    let Some(name) = name else {
        return Err(CliError::new(format!(
            "services {} requires a service name",
            if action == "load" { "start" } else { "stop" }
        )));
    };
    let port_name = name
        .strip_prefix("org.macports.")
        .unwrap_or(name)
        .to_string();
    mutate::sudo_port(
        &[action.to_string(), port_name.clone()],
        &format!("{} {}", action, port_name),
    )
}
