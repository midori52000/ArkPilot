#[cfg(all(target_os = "linux", not(target_env = "ohos")))]
mod bwrap;
pub mod landlock;
mod manager;
pub mod policy_transforms;
#[cfg(target_os = "macos")]
pub mod seatbelt;

#[cfg(all(target_os = "linux", not(target_env = "ohos")))]
pub use bwrap::find_system_bwrap_in_path;
#[cfg(all(target_os = "linux", not(target_env = "ohos")))]
pub use bwrap::system_bwrap_warning;
pub use manager::SandboxCommand;
pub use manager::SandboxExecRequest;
pub use manager::SandboxManager;
pub use manager::SandboxTransformError;
pub use manager::SandboxTransformRequest;
pub use manager::SandboxType;
pub use manager::SandboxablePreference;
pub use manager::get_platform_sandbox;

#[cfg(any(not(target_os = "linux"), target_env = "ohos"))]
pub fn system_bwrap_warning() -> Option<String> {
    None
}
