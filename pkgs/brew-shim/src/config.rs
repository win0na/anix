use std::env;
use std::path::PathBuf;

#[derive(Debug, Clone)]
pub struct Config {
    pub prefix: PathBuf,
    pub brew_real: PathBuf,
    pub version: String,
}

impl Config {
    pub fn from_env() -> Self {
        Self {
            prefix: env::var_os("ANIX_MACPORTS_PREFIX")
                .map(PathBuf::from)
                .unwrap_or_else(|| PathBuf::from("/opt/local")),
            brew_real: env::var_os("ANIX_BREW_REAL")
                .map(PathBuf::from)
                .unwrap_or_else(|| PathBuf::from("/usr/local/bin/brew")),
            version: env::var("ANIX_BREW_VERSION").unwrap_or_else(|_| "7.0.13".to_string()),
        }
    }

    pub fn prefix_str(&self) -> String {
        self.prefix.to_string_lossy().into_owned()
    }

    pub fn cellar(&self) -> PathBuf {
        self.prefix.join("Cellar")
    }

    pub fn opt(&self, port_name: &str) -> PathBuf {
        self.prefix.join("opt").join(port_name)
    }
}
