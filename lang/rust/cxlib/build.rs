use std::path::PathBuf;

fn main() {
    // 1. Explicit directory override
    if let Ok(dir) = std::env::var("LIBCX_LIB_DIR") {
        let p = PathBuf::from(&dir);
        println!("cargo:rustc-link-search=native={dir}");
        println!("cargo:rustc-link-lib=dylib=cx");
        rpath(&p);
        println!("cargo:rerun-if-env-changed=LIBCX_LIB_DIR");
        return;
    }

    // 2. pkg-config (set by `make install`)
    if pkg_config_works() {
        println!("cargo:rerun-if-env-changed=LIBCX_LIB_DIR");
        return;
    }

    // 3. System paths
    let sys_dirs = [
        "/usr/local/lib",
        "/opt/homebrew/lib",
        "/usr/lib",
        "/usr/lib/x86_64-linux-gnu",
        "/usr/lib/aarch64-linux-gnu",
    ];
    for dir in &sys_dirs {
        let p = PathBuf::from(dir);
        if p.join("libcx.dylib").exists() || p.join("libcx.so").exists() {
            println!("cargo:rustc-link-search=native={dir}");
            println!("cargo:rustc-link-lib=dylib=cx");
            rpath(&p);
            println!("cargo:rerun-if-env-changed=LIBCX_LIB_DIR");
            return;
        }
    }

    // 4. Repo-relative fallback (development)
    let manifest = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap());
    let repo = manifest.parent().unwrap().parent().unwrap().parent().unwrap();
    let dev_candidates = [
        repo.join("vcx").join("target"),
        repo.join("dist").join("lib"),
    ];
    if let Some(lib_dir) = dev_candidates.iter().find(|p| {
        p.join("libcx.dylib").exists() || p.join("libcx.so").exists()
    }) {
        println!("cargo:rustc-link-search=native={}", lib_dir.display());
        println!("cargo:rustc-link-lib=dylib=cx");
        rpath(lib_dir);
        rerun_if(lib_dir);
        println!("cargo:rerun-if-env-changed=LIBCX_LIB_DIR");
        return;
    }

    panic!(
        "libcx not found. Run 'sudo make install' from the repo root, \
         set LIBCX_LIB_DIR, or run 'make build' for development use."
    );
}

fn rpath(dir: &PathBuf) {
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap();
    if target_os == "macos" || target_os == "linux" {
        println!("cargo:rustc-link-arg=-Wl,-rpath,{}", dir.display());
    }
}

fn rerun_if(dir: &PathBuf) {
    println!("cargo:rerun-if-changed=build.rs");
    for name in &["libcx.dylib", "libcx.so", "libcx.dll"] {
        println!("cargo:rerun-if-changed={}", dir.join(name).display());
    }
}

fn pkg_config_works() -> bool {
    if let Ok(output) = std::process::Command::new("pkg-config")
        .args(["--libs", "--cflags", "cx"])
        .output()
    {
        if output.status.success() {
            let flags = String::from_utf8_lossy(&output.stdout);
            for flag in flags.split_whitespace() {
                if let Some(path) = flag.strip_prefix("-L") {
                    println!("cargo:rustc-link-search=native={path}");
                }
                if let Some(lib) = flag.strip_prefix("-l") {
                    println!("cargo:rustc-link-lib=dylib={lib}");
                }
            }
            return true;
        }
    }
    false
}
