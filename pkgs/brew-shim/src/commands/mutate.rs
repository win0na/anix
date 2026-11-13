use crate::brew;
use crate::config::Config;
use crate::exec::{self, CliError};
use crate::formula;
use crate::port;

const NO_ARCHIVE: &str = "not found, required when binary-only is set";

pub fn install(config: &Config, args: &[String]) -> Result<(), CliError> {
    let mut force = false;
    let mut dry_run = false;
    let mut formulas = Vec::new();

    for arg in args {
        match arg.as_str() {
            "-f" | "--force" => force = true,
            "--dry-run" => dry_run = true,
            // Homebrew's default already means formula; accept the explicit flag.
            "--formula" => {}
            other if other.starts_with('-') => {
                return Err(CliError::new(format!(
                    "unsupported option \"{}\" for install",
                    other
                )))
            }
            other => formulas.push(other.to_string()),
        }
    }

    if formulas.is_empty() {
        return Err(CliError::new("install requires at least one formula"));
    }

    if dry_run {
        for formula in &formulas {
            let port_name = formula::preview(formula);
            let force_flag = if force { " -f" } else { "" };
            println!("sudo -n port -b{} install {}", force_flag, port_name);
        }
        return Ok(());
    }

    for formula in &formulas {
        let port_name = formula::resolve(formula)?;
        let mut port_args = vec!["-b".to_string()];
        if force {
            port_args.push("-f".to_string());
        }
        port_args.push("install".to_string());
        port_args.push(port_name.clone());
        let hint = format!("-b{} install {}", if force { " -f" } else { "" }, port_name);
        let out = sudo_port_output(&port_args)?;
        let stdout = exec::text(&out.stdout);
        let stderr = exec::text(&out.stderr);

        if out.status.success() {
            print!("{}", stdout);
            eprint!("{}", stderr);
            continue;
        }

        if exec::needs_password(&stdout, &stderr) {
            return Err(password_error(&hint));
        }

        if stdout.contains(NO_ARCHIVE) || stderr.contains(NO_ARCHIVE) {
            eprintln!(
                "==> No MacPorts archive for {}; installing with Homebrew.",
                formula
            );
            brew::delegate(config, &["install".into(), formula.clone()])?;
            continue;
        }

        print!("{}", stdout);
        eprint!("{}", stderr);
        return Err(CliError::silent(out.status.code().unwrap_or(1)));
    }

    Ok(())
}

pub fn uninstall(config: &Config, args: &[String]) -> Result<(), CliError> {
    let mut force = false;
    let mut formulas = Vec::new();
    for arg in args {
        match arg.as_str() {
            "-f" | "--force" => force = true,
            other if other.starts_with('-') => {
                return Err(CliError::new(format!(
                    "unsupported option \"{}\" for uninstall",
                    other
                )))
            }
            other => formulas.push(other.to_string()),
        }
    }
    if formulas.is_empty() {
        return Err(CliError::new("uninstall requires at least one formula"));
    }

    let installed = port::installed()?;
    let brew_formulae = brew::formulae(config);

    for formula in &formulas {
        let curated_name = formula::curated(formula);
        let port_installed = installed.iter().any(|entry| {
            entry.name == *formula || curated_name.map(|name| entry.name == name).unwrap_or(false)
        });

        if port_installed {
            let port_name = curated_name.unwrap_or(formula);
            uninstall_port(port_name, force)?;
        } else if brew_formulae.iter().any(|name| name == formula) {
            brew::delegate(config, &["uninstall".into(), formula.clone()])?;
        } else {
            let port_name = formula::resolve(formula)?;
            uninstall_port(&port_name, force)?;
        }
    }
    Ok(())
}

fn uninstall_port(port_name: &str, force: bool) -> Result<(), CliError> {
    let mut port_args = Vec::new();
    if force {
        port_args.push("-f".to_string());
    }
    port_args.push("uninstall".to_string());
    port_args.push(port_name.to_string());
    let hint = format!("{}uninstall {}", if force { "-f " } else { "" }, port_name);
    sudo_port(&port_args, &hint)
}

pub fn reinstall(args: &[String]) -> Result<(), CliError> {
    let formulas = plain_args(args, "reinstall")?;
    if formulas.is_empty() {
        return Err(CliError::new("reinstall requires at least one formula"));
    }

    for formula in &formulas {
        let port_name = formula::resolve(formula)?;
        println!(
            "==> MacPorts has no reinstall; running: sudo -n port -n upgrade --force {}",
            port_name
        );
        sudo_port(
            &[
                "-n".to_string(),
                "upgrade".to_string(),
                "--force".to_string(),
                port_name.clone(),
            ],
            &format!("-n upgrade --force {}", port_name),
        )?;
    }
    Ok(())
}

pub fn synchronize(subcommand: &str, extra: &[&str]) -> Result<(), CliError> {
    let mut port_args = vec![subcommand.to_string()];
    port_args.extend(extra.iter().map(|arg| arg.to_string()));
    let hint = port_args.join(" ");
    sudo_port(&port_args, &hint)
}

pub fn link(args: &[String], activate: bool) -> Result<(), CliError> {
    let action = if activate { "activate" } else { "deactivate" };
    let formulas = plain_args(args, action)?;
    if formulas.is_empty() {
        return Err(CliError::new(format!(
            "{} requires at least one formula",
            action
        )));
    }
    for formula in &formulas {
        let port_name = formula::resolve(formula)?;
        sudo_port(
            &[action.to_string(), port_name.clone()],
            &format!("{} {}", action, port_name),
        )?;
    }
    Ok(())
}

pub fn fetch(args: &[String]) -> Result<(), CliError> {
    let formulas = plain_args(args, "fetch")?;
    if formulas.is_empty() {
        return Err(CliError::new("fetch requires at least one formula"));
    }
    for formula in &formulas {
        let port_name = formula::resolve(formula)?;
        let out = exec::output("port", &["fetch".to_string(), port_name.to_string()])?;
        let stdout = exec::text(&out.stdout);
        let stderr = exec::text(&out.stderr);
        print!("{}", stdout);
        eprint!("{}", stderr);
        if !out.status.success() {
            return Err(CliError::silent(out.status.code().unwrap_or(1)));
        }
    }
    Ok(())
}

pub(super) fn sudo_port(port_args: &[String], hint: &str) -> Result<(), CliError> {
    let out = sudo_port_output(port_args)?;
    let stdout = exec::text(&out.stdout);
    let stderr = exec::text(&out.stderr);

    if out.status.success() {
        print!("{}", stdout);
        eprint!("{}", stderr);
        return Ok(());
    }
    if exec::needs_password(&stdout, &stderr) {
        return Err(password_error(hint));
    }
    print!("{}", stdout);
    eprint!("{}", stderr);
    Err(CliError::silent(out.status.code().unwrap_or(1)))
}

fn sudo_port_output(port_args: &[String]) -> Result<std::process::Output, CliError> {
    let mut argv = vec!["-n".to_string(), "port".to_string()];
    argv.extend(port_args.iter().cloned());
    exec::output("sudo", &argv)
}

fn password_error(hint: &str) -> CliError {
    CliError::new(format!(
        "sudo requires a password.\nrun: sudo port {}",
        hint
    ))
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
