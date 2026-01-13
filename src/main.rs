use anyhow::{bail, Context, Result};
use clap::Parser;
use colored::*;
use inquire::Select;
use std::env;
use std::fs;
use std::net::{IpAddr, Ipv4Addr, SocketAddr, TcpListener};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use sysinfo::{Pid, System};

const DEFAULT_PORT: u16 = 8000;
const MAX_PORT: u16 = 8100;

/// hopen - Start a local HTTP server for HTML files
///
/// Usage: hopen [-e] [-f] [-m] [-p] [-r site_home] [filename]
///
/// When site_home is set (via -r or HOPEN_SITE_HOME), the server runs from that directory.
/// The URL path is calculated as: (relative path from site_home to PWD) + filename
///
/// Example:
///   site_home = /Users/me/www.example.com
///   PWD       = /Users/me/www.example.com/blog
///   filename  = post.html
///   Server runs from: /Users/me/www.example.com
///   URL: http://localhost:8000/blog/post.html
#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
struct Args {
    /// Optional HTML file to open in the browser
    filename: Option<String>,

    /// Specify the site root directory where the server will run.
    /// Useful for static site mirrors (e.g., from SiteSucker) where you want
    /// to browse files in subdirectories while maintaining correct relative paths.
    #[arg(short = 'r', long = "root")]
    site_home: Option<String>,

    /// Quit any running server on the port and exit
    #[arg(short = 'e', long = "exit")]
    exit: bool,

    /// Run server in foreground (blocking). By default, the server runs in background.
    #[arg(short = 'f', long = "foreground")]
    foreground: bool,

    /// Show interactive menu when a server is already running.
    /// Without this flag, hopen will reuse the existing server.
    #[arg(short = 'm', long = "menu")]
    menu: bool,

    /// Prompt before opening browser. By default, the browser opens automatically.
    #[arg(short = 'p', long = "prompt")]
    prompt: bool,

    /// Internal flag: run as a background server (used when spawning ourselves)
    #[arg(long = "internal-serve", hide = true)]
    internal_serve: bool,

    /// Internal flag: port to serve on (used with --internal-serve)
    #[arg(long = "internal-port", hide = true)]
    internal_port: Option<u16>,

    /// Internal flag: directory to serve (used with --internal-serve)
    #[arg(long = "internal-dir", hide = true)]
    internal_dir: Option<String>,
}

/// Menu choices when a server is already running
#[derive(Debug, Clone)]
enum ExistingServerMenu {
    OpenBrowser,
    QuitServer,
    QuitAndRestart,
    Cancel,
}

impl std::fmt::Display for ExistingServerMenu {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self {
            ExistingServerMenu::OpenBrowser => write!(f, "1) Open in browser"),
            ExistingServerMenu::QuitServer => write!(f, "2) Quit the existing server"),
            ExistingServerMenu::QuitAndRestart => write!(f, "3) Quit and restart here"),
            ExistingServerMenu::Cancel => write!(f, "4) Cancel and leave everything unchanged"),
        }
    }
}

/// Menu choices when starting a new server (with -m flag)
#[derive(Debug, Clone)]
enum StartupMenu {
    StartBackground,
    StartForeground,
    Cancel,
}

impl std::fmt::Display for StartupMenu {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self {
            StartupMenu::StartBackground => write!(f, "1) Start server in background"),
            StartupMenu::StartForeground => write!(f, "2) Start server in foreground"),
            StartupMenu::Cancel => write!(f, "3) Cancel"),
        }
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    let args = Args::parse();

    // =========================================================================
    // Internal Server Mode (spawned by ourselves for background operation)
    // =========================================================================
    if args.internal_serve {
        let port = args.internal_port.unwrap_or(DEFAULT_PORT);
        let dir = args.internal_dir
            .map(PathBuf::from)
            .unwrap_or_else(|| env::current_dir().unwrap_or_default());

        run_server(&dir, port).await?;
        return Ok(());
    }

    // =========================================================================
    // 1. Resolve Paths (Site Home vs Current Directory)
    // =========================================================================
    let current_dir = env::current_dir().context("Failed to get current directory")?;

    // Determine site_home: -r flag -> HOPEN_SITE_HOME env var -> None
    let site_home: Option<PathBuf> = args
        .site_home
        .clone()
        .or_else(|| env::var("HOPEN_SITE_HOME").ok())
        .map(|p| {
            let path = PathBuf::from(&p);
            path.canonicalize().unwrap_or(path)
        });

    // Validate: filename requires site_home
    if args.filename.is_some() && site_home.is_none() {
        bail!(
            "Error: filename argument requires either -r flag or HOPEN_SITE_HOME to be set"
        );
    }

    // =========================================================================
    // 2. URL Path Construction (when site_home is specified)
    // =========================================================================
    // When site_home is set, we calculate the URL path as:
    // (relative path from site_home to PWD) + filename
    let (server_dir, url_path) = if let Some(ref sh) = site_home {
        // Validate: PWD must be under site_home
        if !current_dir.starts_with(sh) {
            eprintln!("{}", "Error: Current directory is not under site_home".red());
            eprintln!("{} {}", "Site home:".cyan(), sh.display().to_string().magenta());
            eprintln!(
                "{} {}",
                "Current directory:".cyan(),
                current_dir.display().to_string().magenta()
            );
            std::process::exit(1);
        }

        // Calculate relative path from site_home to PWD
        let relative = current_dir
            .strip_prefix(sh)
            .unwrap_or(Path::new(""))
            .to_path_buf();

        // Build URL path
        let mut url = relative.clone();
        if let Some(ref f) = args.filename {
            url.push(f);
        }

        (sh.clone(), url)
    } else {
        // No site_home: server runs from PWD, URL path is just the filename (if any)
        let url = args
            .filename
            .as_ref()
            .map(PathBuf::from)
            .unwrap_or_default();
        (current_dir.clone(), url)
    };

    // =========================================================================
    // 3. Check for HTML Files
    // =========================================================================
    if !has_html_files(&current_dir) {
        eprintln!(
            "{}",
            "✗ No HTML files found in current directory".red().bold()
        );
        eprintln!(
            "{}",
            "This tool requires at least one HTML file (*.htm or *.html)".yellow()
        );
        eprintln!(
            "{} {}",
            "Current directory:".cyan(),
            current_dir.display().to_string().magenta()
        );
        std::process::exit(1);
    }

    // =========================================================================
    // 4. Find Available Port
    // =========================================================================
    let port = find_available_port(DEFAULT_PORT)?;

    // Check if our preferred port range has a server already running
    let existing_server = find_existing_server();

    // =========================================================================
    // 5. Handle -e/--exit Flag (Kill and Exit)
    // =========================================================================
    if args.exit {
        if let Some((pid, existing_port)) = existing_server {
            kill_process(pid)?;
            println!(
                "{}",
                format!("✓ Server stopped (PID: {}, port: {})", pid, existing_port).green()
            );
        } else {
            println!("{}", "No server running on port 8000.".yellow());
        }
        return Ok(());
    }

    // Build full URL
    let url_path_str = if url_path.as_os_str().is_empty() {
        String::new()
    } else {
        format!("/{}", url_path.display())
    };

    // =========================================================================
    // 6. Handle Existing Server
    // =========================================================================
    if let Some((pid, existing_port)) = existing_server {
        let full_url = format!("http://localhost:{}{}", existing_port, url_path_str);

        // Default behavior: reuse existing server and open browser
        // With -m/--menu flag: show interactive menu
        if !args.menu {
            println!(
                "{}",
                format!("⚠ Reusing existing server (PID: {}, port: {})", pid, existing_port).yellow()
            );
            open::that(&full_url)?;
            println!("{}", format!("✓ Browser opened at {}", full_url).green());
            return Ok(());
        }

        // -m/--menu flag: Show interactive menu
        println!(
            "{}",
            "⚠ An HTTP server is already running!".yellow().bold()
        );
        if let Some(dir) = get_process_cwd(pid) {
            println!("{} {}", "Directory:".cyan(), dir.magenta());
        }
        println!("{} {}", "PID:".cyan(), pid.to_string().magenta());
        println!("{} {}", "Port:".cyan(), existing_port.to_string().magenta());
        println!(
            "{} {}",
            "URL:".cyan(),
            full_url.blue().bold()
        );
        println!();

        // Interactive menu
        let options = vec![
            ExistingServerMenu::OpenBrowser,
            ExistingServerMenu::QuitServer,
            ExistingServerMenu::QuitAndRestart,
            ExistingServerMenu::Cancel,
        ];

        println!("{}", "What would you like to do?".bold());
        let choice = Select::new("", options).prompt()?;

        match choice {
            ExistingServerMenu::OpenBrowser => {
                open::that(&full_url)?;
                println!(
                    "{}",
                    format!("✓ Browser opened at {}", full_url).green()
                );
            }
            ExistingServerMenu::QuitServer => {
                kill_process(pid)?;
                println!("{}", "✓ Server stopped successfully".green());
            }
            ExistingServerMenu::QuitAndRestart => {
                kill_process(pid)?;
                println!("{}", "✓ Server stopped successfully".green());
                println!();

                // Wait for port to be released
                tokio::time::sleep(std::time::Duration::from_millis(500)).await;

                // Re-check for HTML files (we're restarting in current dir context)
                println!(
                    "{}",
                    "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                        .cyan()
                        .bold()
                );
                println!(
                    "{} {}",
                    "Checking for HTML files in:".cyan(),
                    current_dir.display().to_string().magenta()
                );
                println!(
                    "{}",
                    "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                        .cyan()
                        .bold()
                );
                println!();

                if !has_html_files(&current_dir) {
                    eprintln!("{}", "✗ No HTML files found!".red().bold());
                    std::process::exit(1);
                }
                println!("{}", "✓ Found HTML files".green());
                println!();

                // Find new available port and start
                let new_port = find_available_port(DEFAULT_PORT)?;
                let new_url = format!("http://localhost:{}{}", new_port, url_path_str);
                start_server(&server_dir, new_port, &new_url, args.prompt, args.foreground).await?;
            }
            ExistingServerMenu::Cancel => {
                println!("{}", "Cancelled - no changes made".yellow());
            }
        }
    } else {
        // =========================================================================
        // 7. No Existing Server - Start New One
        // =========================================================================
        let full_url = format!("http://localhost:{}{}", port, url_path_str);

        if args.menu {
            // -m/--menu flag: Show startup menu
            println!("{}", "No server currently running.".cyan());
            println!(
                "{} {}",
                "Directory:".cyan(),
                server_dir.display().to_string().magenta()
            );
            println!("{} {}", "Port:".cyan(), port.to_string().magenta());
            println!(
                "{} {}",
                "URL:".cyan(),
                full_url.blue().bold()
            );
            println!();

            let options = vec![
                StartupMenu::StartBackground,
                StartupMenu::StartForeground,
                StartupMenu::Cancel,
            ];

            println!("{}", "What would you like to do?".bold());
            let choice = Select::new("", options).prompt()?;

            match choice {
                StartupMenu::StartBackground => {
                    start_server(&server_dir, port, &full_url, args.prompt, false).await?;
                }
                StartupMenu::StartForeground => {
                    start_server(&server_dir, port, &full_url, args.prompt, true).await?;
                }
                StartupMenu::Cancel => {
                    println!("{}", "Cancelled - no server started".yellow());
                }
            }
        } else {
            // Default: start server based on -f flag
            start_server(&server_dir, port, &full_url, args.prompt, args.foreground).await?;
        }
    }

    Ok(())
}

/// Check if there are any HTML files in the directory
fn has_html_files(dir: &Path) -> bool {
    if let Ok(entries) = fs::read_dir(dir) {
        for entry in entries.flatten() {
            if let Some(name) = entry.path().file_name() {
                let name = name.to_string_lossy().to_lowercase();
                if name.ends_with(".html") || name.ends_with(".htm") {
                    return true;
                }
            }
        }
    }
    false
}

/// Find an available port starting from the given port
fn find_available_port(start_port: u16) -> Result<u16> {
    for port in start_port..=MAX_PORT {
        if !is_port_in_use(port) {
            return Ok(port);
        }
    }
    bail!(
        "No available ports found in range {}-{}",
        start_port,
        MAX_PORT
    );
}

/// Check if a port is in use (using lsof for reliable detection on macOS)
fn is_port_in_use(port: u16) -> bool {
    // Use lsof to check if anything is listening on the port
    // This is more reliable than TcpListener::bind as it detects both IPv4 and IPv6
    let output = Command::new("lsof")
        .arg("-i")
        .arg(format!(":{}", port))
        .arg("-sTCP:LISTEN")
        .output();

    match output {
        Ok(o) => !o.stdout.is_empty(),
        Err(_) => {
            // Fallback to bind check if lsof fails
            TcpListener::bind(("127.0.0.1", port)).is_err()
        }
    }
}

/// Find an existing HTTP server on our port range
fn find_existing_server() -> Option<(u32, u16)> {
    // Try to find a process listening on our port range
    for port in DEFAULT_PORT..=MAX_PORT {
        if is_port_in_use(port) {
            if let Some(pid) = get_pid_on_port(port) {
                return Some((pid, port));
            }
        }
    }
    None
}

/// Get the PID of the process listening on a port (macOS specific using lsof)
fn get_pid_on_port(port: u16) -> Option<u32> {
    let output = Command::new("lsof")
        .arg("-t")
        .arg(format!("-i:{}", port))
        .arg("-sTCP:LISTEN")
        .output()
        .ok()?;

    let pid_str = String::from_utf8(output.stdout).ok()?;
    // lsof -t may return multiple PIDs, take the first one
    pid_str.lines().next()?.trim().parse().ok()
}

/// Get the current working directory of a process (macOS specific using lsof)
fn get_process_cwd(pid: u32) -> Option<String> {
    let output = Command::new("lsof")
        .arg("-p")
        .arg(pid.to_string())
        .output()
        .ok()?;

    let output_str = String::from_utf8(output.stdout).ok()?;
    for line in output_str.lines() {
        if line.contains("cwd") {
            // lsof output: COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 9 {
                return Some(parts[8..].join(" "));
            }
        }
    }
    None
}

/// Kill a process by PID
fn kill_process(pid: u32) -> Result<()> {
    let s = System::new_all();
    if let Some(process) = s.process(Pid::from(pid as usize)) {
        process.kill();
    } else {
        // Fallback to command line kill
        Command::new("kill")
            .arg("-9")
            .arg(pid.to_string())
            .output()?;
    }
    Ok(())
}

/// Run the warp HTTP server (used for both foreground and background modes)
async fn run_server(root: &Path, port: u16) -> Result<()> {
    // Set up Ctrl+C handler for graceful shutdown
    let should_exit = Arc::new(AtomicBool::new(false));
    let s_exit = should_exit.clone();

    ctrlc::set_handler(move || {
        s_exit.store(true, Ordering::SeqCst);
        std::process::exit(0);
    })
    .ok(); // Ignore error if handler already set

    // Serve files using warp
    let route = warp::fs::dir(root.to_path_buf());
    let addr = SocketAddr::new(IpAddr::V4(Ipv4Addr::new(127, 0, 0, 1)), port);

    warp::serve(route).run(addr).await;

    Ok(())
}

/// Start the HTTP server and open the browser
async fn start_server(root: &Path, port: u16, url: &str, prompt: bool, foreground: bool) -> Result<()> {
    println!("{}", "✓ All checks passed!".green().bold());
    println!(
        "{} {}",
        "Starting HTTP server in:".cyan(),
        root.display().to_string().magenta()
    );
    println!("{} {}", "Port:".cyan(), port.to_string().magenta());
    println!("{} {}", "Access at:".cyan(), url.blue().bold());
    println!();

    // Check if root exists
    if !root.exists() {
        bail!("Root path {:?} does not exist", root);
    }

    if foreground {
        // =========================================================================
        // Foreground Mode (-f): Run warp server in foreground (blocking)
        // =========================================================================

        // Open browser: auto by default, prompt with -p flag
        if prompt {
            print!("{}", "Open in browser now? [y/N]: ".bold());
            use std::io::Write;
            std::io::stdout().flush()?;
            let mut input = String::new();
            std::io::stdin().read_line(&mut input)?;
            if input.trim().eq_ignore_ascii_case("y") {
                open::that(url)?;
                println!("{}", format!("✓ Browser opened at {}", url).green());
            }
        } else {
            // Default: auto-open browser after a short delay
            let url_string = url.to_string();
            tokio::spawn(async move {
                tokio::time::sleep(std::time::Duration::from_millis(300)).await;
                if let Err(e) = open::that(&url_string) {
                    eprintln!("Failed to open browser: {}", e);
                }
            });
            println!("{}", format!("✓ Browser opened at {}", url).green());
        }

        println!(
            "{}",
            "Server running (press Ctrl+C to stop)".cyan()
        );

        run_server(root, port).await?;
    } else {
        // =========================================================================
        // Background Mode (default): Spawn ourselves as a background server
        // =========================================================================
        // We spawn a new instance of ourselves with --internal-serve flag
        // This uses native Rust/warp instead of Python

        let log_file = format!("/tmp/hopen-server-{}.log", std::process::id());
        let exe_path = env::current_exe().context("Failed to get current executable path")?;

        // Spawn ourselves with internal-serve flag
        // Use nohup to ensure the process survives parent exit
        let child = Command::new("nohup")
            .arg(&exe_path)
            .arg("--internal-serve")
            .arg("--internal-port")
            .arg(port.to_string())
            .arg("--internal-dir")
            .arg(root.to_string_lossy().to_string())
            .stdin(std::process::Stdio::null())
            .stdout(std::fs::File::create(&log_file)?)
            .stderr(std::fs::File::create(&log_file)?)
            .spawn()
            .context("Failed to start background server")?;

        let pid = child.id();

        // Give it a moment to start and bind to the port
        tokio::time::sleep(std::time::Duration::from_millis(500)).await;

        // Verify the server started
        if !is_port_in_use(port) {
            eprintln!("{}", "✗ Failed to start server".red().bold());
            eprintln!("{} {}", "Check logs:".yellow(), log_file.cyan());
            std::process::exit(1);
        }

        println!(
            "{} {}",
            "✓ Server started successfully!".green().bold(),
            format!("(PID: {})", pid).cyan()
        );
        println!(
            "{} {}",
            "To stop the server, run:".yellow(),
            format!("kill {}", pid).cyan()
        );
        println!("{} {}", "Logs:".cyan(), log_file.magenta());
        println!();

        // Open browser: auto by default, prompt with -p flag
        if prompt {
            print!("{}", "Open in browser now? [y/N]: ".bold());
            use std::io::Write;
            std::io::stdout().flush()?;
            let mut input = String::new();
            std::io::stdin().read_line(&mut input)?;
            if input.trim().eq_ignore_ascii_case("y") {
                open::that(url)?;
                println!("{}", format!("✓ Browser opened at {}", url).green());
            }
        } else {
            // Default: auto-open browser
            open::that(url)?;
            println!("{}", format!("✓ Browser opened at {}", url).green());
        }
    }

    Ok(())
}
