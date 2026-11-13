mod mutate;
mod read;
mod services;

use crate::brew;
use crate::config::Config;
use crate::exec::CliError;

const UNSUPPORTED: &[&str] = &["tap", "untap", "pin", "unpin", "bundle", "switch"];

pub fn run(args: &[String]) -> Result<(), CliError> {
    let config = Config::from_env();

    if let Some(flag) = args
        .iter()
        .find(|arg| *arg == "--json" || arg.starts_with("--json="))
    {
        return Err(CliError::new(format!(
            "\"{}\" is not supported by brew-shim",
            flag
        )));
    }

    let Some(command) = args.first().map(String::as_str) else {
        print_help();
        return Ok(());
    };

    let cask = has_flag(args, "--cask");
    let rest = &args[1..];

    match command {
        "-h" | "--help" | "help" => {
            print_help();
            Ok(())
        }
        "-v" | "--version" => {
            println!("Homebrew {}", config.version);
            Ok(())
        }
        "--prefix" => read::prefix(&config, rest.first().map(String::as_str)),
        "--cellar" => read::cellar(&config, rest.first().map(String::as_str)),
        "--repository" => {
            println!("{}", config.prefix_str());
            Ok(())
        }
        "--caskroom" => brew::delegate(&config, args),
        "list" if cask => brew::delegate(&config, args),
        "info" if cask => brew::delegate(&config, args),
        "install" if cask => brew::delegate(&config, args),
        "uninstall" | "remove" | "rm" if cask => brew::delegate(&config, args),
        "list" => read::list(&config, rest),
        "leaves" => read::leaves(&config),
        "info" => read::info(&config, rest),
        "search" => read::search(&config, rest),
        "outdated" => read::outdated(),
        "deps" => read::deps(&config, rest),
        "uses" => read::uses(&config, rest),
        "config" => read::config(&config),
        "doctor" => read::doctor(&config),
        "shellenv" => read::shellenv(&config, rest),
        "install" => mutate::install(&config, rest),
        "uninstall" | "remove" | "rm" => mutate::uninstall(&config, rest),
        "reinstall" => mutate::reinstall(rest),
        "upgrade" if rest.is_empty() => mutate::synchronize("upgrade", &["outdated"]),
        "update" if rest.is_empty() => mutate::synchronize("sync", &[]),
        "cleanup" if rest.is_empty() => mutate::synchronize("reclaim", &[]),
        "upgrade" | "update" | "cleanup" => {
            Err(CliError::new(format!("{} takes no arguments", command)))
        }
        "link" => mutate::link(rest, true),
        "unlink" => mutate::link(rest, false),
        "fetch" => mutate::fetch(rest),
        "services" => services::run(rest),
        other if UNSUPPORTED.contains(&other) => Err(CliError::new(format!(
            "\"{}\" is not supported by brew-shim; use port directly",
            other
        ))),
        other => Err(CliError::new(format!(
            "unknown command: \"{}\" (run brew --help)",
            other
        ))),
    }
}

fn has_flag(args: &[String], flag: &str) -> bool {
    args.iter().any(|arg| arg == flag)
}

fn print_help() {
    println!(
        "\
brew-shim {}: Homebrew front end for MacPorts

Usage: brew <command> [options]

Read-only:
  --version, --prefix [formula], --cellar [formula], --repository, --caskroom
  list [--formula|--versions|--cask], leaves, info <formula>, search <term>
  outdated, deps <formula>, uses <formula>, config, doctor, shellenv [shell]

Mutating:
  install [-f] [--dry-run] <formula>..., uninstall|remove|rm [-f] <formula>...
  reinstall <formula>..., upgrade, update, cleanup, link|unlink <formula>
  fetch <formula>..., services [list|start|stop] [name]

Casks are delegated to the real Homebrew at ANIX_BREW_REAL.
",
        env!("CARGO_PKG_VERSION")
    );
}
