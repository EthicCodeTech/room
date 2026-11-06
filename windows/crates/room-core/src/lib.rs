//! Room's engine. Everything here is plain Rust so it can be tested on any OS; the few Windows-only calls
//! live in `platform`. The rules mirror the macOS app: three risk tiers, nothing in `yours` is touched without
//! a named confirmation, and anything that might be someone's work waits in an undo vault for 7 days.

pub mod catalog;
pub mod cleaner;
pub mod decision;
pub mod discover;
pub mod env;
pub mod git;
pub mod map;
pub mod model;
pub mod planner;
pub mod platform;
pub mod safety;
pub mod scan;
pub mod scorer;
pub mod settings;
pub mod vault;

pub use model::*;

pub const APP_VERSION: &str = env!("CARGO_PKG_VERSION");

/// Formats bytes the way people read them ("2.1 GB"). Decimal units, like Windows Explorer and Finder.
pub fn format_bytes(bytes: u64) -> String {
    const UNITS: [&str; 5] = ["bytes", "KB", "MB", "GB", "TB"];
    if bytes < 1000 {
        return format!("{bytes} bytes");
    }
    let mut value = bytes as f64;
    let mut unit = 0;
    while value >= 1000.0 && unit < UNITS.len() - 1 {
        value /= 1000.0;
        unit += 1;
    }
    if value >= 100.0 { format!("{value:.0} {}", UNITS[unit]) } else { format!("{value:.1} {}", UNITS[unit]) }
}
