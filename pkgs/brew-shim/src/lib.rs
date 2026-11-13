pub mod brew;
mod commands;
pub mod config;
pub mod exec;
pub mod formula;
pub mod port;

pub use exec::CliError;

pub fn main_entry() -> i32 {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match commands::run(&args) {
        Ok(()) => 0,
        Err(err) => {
            if !err.message.is_empty() {
                eprintln!("{}", err.message);
            }
            err.code
        }
    }
}
