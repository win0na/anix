use std::collections::{BTreeMap, BTreeSet};

use crate::brew;
use crate::config::Config;
use crate::exec::{self, CliError};
use crate::formula;
use crate::port;

pub fn prefix(config: &Config, formula: Option<&str>) -> Result<(), CliError> {
    let Some(formula) = formula else {
        println!("{}", config.prefix_str());
        return Ok(());
    };

    match formula::resolve(formula) {
        Ok(port_name) => {
            let installed = port::installed()?;
            if installed.iter().any(|entry| entry.name == port_name) {
                // The activation step refreshes the brew layout, so a port
                // installed moments ago may not have its link yet.
                let opt = config.opt(&port_name);
                if opt.exists() {
                    println!("{}", opt.display());
                } else {
                    println!("{}", config.prefix_str());
                }
                return Ok(());
            }
            if brew::has_formula(config, formula) {
                return brew::delegate(config, &["--prefix".into(), formula.into()]);
            }
            Err(CliError::new(format!(
                "Formula \"{}\" is not installed ({})",
                formula, port_name
            )))
        }
        Err(err) => {
            // Homebrew may own this name; let the real brew answer.
            if brew::has_formula(config, formula) {
                return brew::delegate(config, &["--prefix".into(), formula.into()]);
            }
            Err(err)
        }
    }
}

pub fn cellar(config: &Config, formula: Option<&str>) -> Result<(), CliError> {
    match formula {
        None => println!("{}", config.cellar().display()),
        Some(formula) => {
            let installed = port::installed()?;
            let from_port = formula::resolve(formula)
                .map(|name| installed.iter().any(|entry| entry.name == name))
                .unwrap_or(false);
            if !from_port && brew::has_formula(config, formula) {
                return brew::delegate(config, &["--cellar".into(), formula.into()]);
            }
            let port_name = formula::resolve(formula)?;
            println!("{}", config.cellar().join(port_name).display());
        }
    }
    Ok(())
}

pub fn list(config: &Config, args: &[String]) -> Result<(), CliError> {
    let mut versions = false;
    for arg in args {
        match arg.as_str() {
            "--formula" | "-f" => {}
            "--versions" => versions = true,
            other => {
                return Err(CliError::new(format!(
                    "unsupported option \"{}\" for list",
                    other
                )))
            }
        }
    }

    let ports = port::installed()?;
    if versions {
        let brew_versions =
            brew::capture(config, &["list".into(), "--versions".into()]).unwrap_or_default();
        versions_union(&ports, &brew_versions);
    } else {
        let brew_formulae =
            brew::capture(config, &["list".into(), "--formula".into()]).unwrap_or_default();
        let mut names: BTreeSet<String> = ports.iter().map(|entry| entry.name.clone()).collect();
        for line in brew_formulae.lines() {
            let name = line.trim();
            if is_brew_name(name) {
                names.insert(name.to_string());
            }
        }
        for name in names {
            println!("{}", name);
        }
    }
    Ok(())
}

fn versions_union(ports: &[port::InstalledPort], brew_versions: &str) {
    let mut versions: BTreeMap<String, String> = BTreeMap::new();
    for entry in ports {
        versions
            .entry(entry.name.clone())
            .or_insert_with(|| entry.version.clone());
    }
    for line in brew_versions.lines() {
        let line = line.trim();
        let Some((name, version)) = line.split_once(char::is_whitespace) else {
            continue;
        };
        if !is_brew_name(name) {
            continue;
        }
        versions
            .entry(name.to_string())
            .or_insert_with(|| version.trim().to_string());
    }
    for (name, version) in versions {
        println!("{} {}", name, version);
    }
}

pub fn leaves(config: &Config) -> Result<(), CliError> {
    let ports = port::leaves()?;
    let brew_leaves = brew::capture(config, &["leaves".into()]).unwrap_or_default();
    let mut names: BTreeSet<String> = ports.into_iter().collect();
    for line in brew_leaves.lines() {
        let name = line.trim();
        if is_brew_name(name) {
            names.insert(name.to_string());
        }
    }
    for name in names {
        println!("{}", name);
    }
    Ok(())
}

pub fn info(config: &Config, args: &[String]) -> Result<(), CliError> {
    let formulas = plain_args(args, "info")?;
    if formulas.is_empty() {
        return Err(CliError::new("info requires a formula name"));
    }

    let installed = port::installed()?;
    for formula in formulas {
        let port_name = match formula::resolve(&formula) {
            Ok(name) => name,
            Err(err) => {
                if brew::has_formula(config, &formula) {
                    return brew::delegate(config, &["info".into(), formula.clone()]);
                }
                return Err(err);
            }
        };
        let out = exec::output(
            "port",
            &[
                "-q".into(),
                "info".into(),
                "--line".into(),
                "--name".into(),
                "--version".into(),
                "--revision".into(),
                port_name.clone(),
            ],
        )?;
        if !out.status.success() {
            return Err(CliError::new(format!(
                "No available formula with the name \"{}\"",
                formula
            )));
        }
        let Some((name, version)) = port::parse_info(&exec::text(&out.stdout)) else {
            return Err(CliError::new(format!(
                "No available formula with the name \"{}\"",
                formula
            )));
        };
        println!("==> {}: stable {}", name, version);
        if installed.iter().any(|entry| entry.name == port_name)
            || brew::has_formula(config, &formula)
        {
            println!("Installed");
        } else {
            println!("Not installed");
        }
    }
    Ok(())
}

pub fn search(config: &Config, args: &[String]) -> Result<(), CliError> {
    let terms = plain_args(args, "search")?;
    let Some(term) = terms.first() else {
        return Err(CliError::new("search requires a term"));
    };
    if terms.len() > 1 {
        return Err(CliError::new("search accepts one term"));
    }

    let ports = port::search(term)?;
    let brew_results = brew::capture(config, &["search".into(), term.clone()]).unwrap_or_default();
    let mut names: BTreeSet<String> = ports.into_iter().collect();
    for line in brew_results.lines() {
        let name = line.trim();
        if is_brew_name(name) {
            names.insert(name.to_string());
        }
    }
    for name in names {
        println!("{}", name);
    }
    Ok(())
}

pub fn outdated() -> Result<(), CliError> {
    let mut rows = port::outdated()?;
    rows.sort_by(|left, right| left.0.cmp(&right.0));
    for (name, old, new) in rows {
        println!("{} ({}) < {}", name, old, new);
    }
    Ok(())
}

pub fn deps(config: &Config, args: &[String]) -> Result<(), CliError> {
    relation(config, args, "deps", port::deps, "deps")
}

pub fn uses(config: &Config, args: &[String]) -> Result<(), CliError> {
    relation(config, args, "uses", port::dependents, "uses")
}

fn relation(
    config: &Config,
    args: &[String],
    label: &str,
    lookup: fn(&str) -> Result<Vec<String>, CliError>,
    brew_command: &str,
) -> Result<(), CliError> {
    let formulas = plain_args(args, label)?;
    let Some(formula) = formulas.first() else {
        return Err(CliError::new(format!("{} requires a formula name", label)));
    };
    let port_name = match formula::resolve(formula) {
        Ok(name) => name,
        Err(err) => {
            if brew::has_formula(config, formula) {
                return brew::delegate(
                    config,
                    &[brew_command.to_string(), formula.clone()],
                );
            }
            return Err(err);
        }
    };
    let mut names = lookup(&port_name)?;
    names.sort();
    names.dedup();
    for name in names {
        println!("{}", name);
    }
    Ok(())
}

pub fn config(config: &Config) -> Result<(), CliError> {
    println!("HOMEBREW_PREFIX: {}", config.prefix_str());
    println!("HOMEBREW_CELLAR: {}", config.cellar().display());
    println!("HOMEBREW_REPOSITORY: {}", config.prefix_str());
    println!("HOMEBREW_VERSION: {}", config.version);
    println!(
        "MacPorts version: {}",
        port::version().unwrap_or_else(|| "unknown".to_string())
    );
    Ok(())
}

pub fn doctor(config: &Config) -> Result<(), CliError> {
    println!("==> Checking MacPorts");
    let Some(port_bin) = exec::find_in_path("port") else {
        return Err(CliError::new(
            "MacPorts port not found on PATH; install MacPorts first",
        ));
    };
    let version = port::version().unwrap_or_else(|| "unknown".to_string());
    println!("port: {} ({})", port_bin.display(), version);
    if config.prefix.is_dir() {
        println!("prefix: {} (found)", config.prefix.display());
    } else {
        println!("prefix: {} (missing)", config.prefix.display());
    }

    println!("==> Checking Homebrew");
    if config.brew_real.exists() {
        println!("brew: {} (found)", config.brew_real.display());
    } else {
        println!("brew: {} (missing)", config.brew_real.display());
    }

    println!("==> Checking sudo");
    if exec::find_in_path("sudo").is_some() {
        println!("sudo: found");
    } else {
        println!("sudo: missing");
    }

    Ok(())
}

pub fn shellenv(config: &Config, args: &[String]) -> Result<(), CliError> {
    let shell = shell_from_args(args);
    let prefix = config.prefix_str();
    let cellar = config.cellar().to_string_lossy().into_owned();

    match shell {
        Shell::Fish => {
            println!("set -gx HOMEBREW_PREFIX \"{}\";", prefix);
            println!("set -gx HOMEBREW_CELLAR \"{}\";", cellar);
            println!("set -gx HOMEBREW_REPOSITORY \"{}\";", prefix);
            println!("set -gx PATH \"{0}/bin\" \"{0}/sbin\" $PATH;", prefix);
            println!("set -gx MANPATH \"{}/share/man\" $MANPATH;", prefix);
            println!("set -gx INFOPATH \"{}/share/info\" $INFOPATH;", prefix);
        }
        Shell::Sh => {
            println!("export HOMEBREW_PREFIX=\"{}\";", prefix);
            println!("export HOMEBREW_CELLAR=\"{}\";", cellar);
            println!("export HOMEBREW_REPOSITORY=\"{}\";", prefix);
            println!("export PATH=\"{0}/bin:{0}/sbin${{PATH+:$PATH}}\";", prefix);
            println!(
                "export MANPATH=\"{0}/share/man${{MANPATH+:$MANPATH}}:\";",
                prefix
            );
            println!(
                "export INFOPATH=\"{0}/share/info:${{INFOPATH:-}}\";",
                prefix
            );
        }
    }
    Ok(())
}

enum Shell {
    Sh,
    Fish,
}

fn shell_from_args(args: &[String]) -> Shell {
    if let Some(arg) = args.first() {
        let name = arg
            .strip_prefix("--shell=")
            .unwrap_or(arg)
            .rsplit('/')
            .next()
            .unwrap_or(arg);
        if name == "fish" {
            return Shell::Fish;
        }
    }
    let from_env = std::env::var("SHELL").unwrap_or_default();
    if from_env.rsplit('/').next() == Some("fish") {
        Shell::Fish
    } else {
        Shell::Sh
    }
}

fn plain_args(args: &[String], command: &str) -> Result<Vec<String>, CliError> {
    let mut values = Vec::new();
    for arg in args {
        if arg.starts_with('-') {
            return Err(CliError::new(format!(
                "unsupported option \"{}\" for {}",
                arg, command
            )));
        }
        values.push(arg.clone());
    }
    Ok(values)
}

fn is_brew_name(name: &str) -> bool {
    !name.is_empty()
        && !name.contains(char::is_whitespace)
        && !name.starts_with("==>")
        && !name.starts_with('#')
        && name
            .chars()
            .all(|ch| ch.is_ascii_alphanumeric() || "-_.+@/".contains(ch))
}
