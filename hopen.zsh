#!/bin/zsh

# hopen - Start a Python HTTP server for HTML files
# Add this function to your .zshrc by sourcing this file or copying the function
#
# Usage: hopen [-e] [-m] [-p] [-r site_home] [filename]
#
# Options:
#   -e             Exit/kill any running server on port 8000 and exit
#
#   -m             Show interactive menu when a server is already running.
#                  Without this flag, hopen will reuse the existing server.
#
#   -p             Prompt before opening browser. By default, the browser opens
#                  automatically when the server starts.
#
#   -r site_home   Specify the site root directory where the server will run.
#                  This is useful when working with static site mirrors (e.g., from SiteSucker)
#                  where you want to browse files in subdirectories while maintaining
#                  correct relative paths.
#
#   filename       Optional HTML file to open in the browser. Requires site_home to be set
#                  (via -r flag or HOPEN_SITE_HOME environment variable).
#
# Environment Variables:
#   HOPEN_SITE_HOME   Default site root directory. Used when -r is not specified.
#
# Examples:
#   hopen                                    # Start server in current directory
#   hopen -r /path/to/site                   # Start server from site root
#   hopen -r /path/to/site index.html        # Start server and open specific file
#   export HOPEN_SITE_HOME=/path/to/site
#   cd /path/to/site/subdir
#   hopen page.html                          # Opens http://localhost:8000/subdir/page.html
#
# How site_home works:
#   When site_home is set, the HTTP server runs from that directory (the site root).
#   The URL path is calculated as: (relative path from site_home to PWD) + filename
#
#   Example:
#     site_home = /Users/me/www.example.com
#     PWD       = /Users/me/www.example.com/blog/posts
#     filename  = article.html
#     Server runs from: /Users/me/www.example.com
#     URL: http://localhost:8000/blog/posts/article.html

hopen() {
    # Save current shell options
    local old_nullglob=$(setopt | grep nullglob)

    # Enable null_glob to prevent errors when globs don't match
    setopt null_glob

    # Parse command-line arguments
    # -e: Exit/kill any running server and exit
    # -m: Show interactive menu when server is already running
    # -p: Prompt before opening browser (default: auto-open)
    # -r site_home: The root directory of the site (where the server will run)
    # filename: Optional file to open in browser (requires site_home)
    local site_home=""
    local filename=""
    local exit_flag=false
    local menu_flag=false
    local prompt_flag=false
    local OPTIND=1

    while getopts "empr:" opt; do
        case "$opt" in
            e)
                exit_flag=true
                ;;
            m)
                menu_flag=true
                ;;
            p)
                prompt_flag=true
                ;;
            r)
                site_home="$OPTARG"
                ;;
            *)
                echo "Usage: hopen [-e] [-m] [-p] [-r site_home] [filename]"
                [[ -z "$old_nullglob" ]] && unsetopt null_glob
                return 1
                ;;
        esac
    done
    shift $((OPTIND - 1))

    # Optional filename argument - the specific HTML file to open in browser
    if [[ $# -gt 0 ]]; then
        filename="$1"
    fi

    # Fall back to HOPEN_SITE_HOME environment variable if -r not provided
    if [[ -z "$site_home" && -n "$HOPEN_SITE_HOME" ]]; then
        site_home="$HOPEN_SITE_HOME"
    fi

    # Filename argument only makes sense when we know the site root,
    # so we can calculate the correct URL path
    if [[ -n "$filename" && -z "$site_home" ]]; then
        echo "Error: filename argument requires either -r flag or HOPEN_SITE_HOME to be set"
        [[ -z "$old_nullglob" ]] && unsetopt null_glob
        return 1
    fi

    # Color codes
    local RED='\033[0;31m'
    local GREEN='\033[0;32m'
    local YELLOW='\033[1;33m'
    local BLUE='\033[0;34m'
    local MAGENTA='\033[0;35m'
    local CYAN='\033[0;36m'
    local NC='\033[0m' # No Color
    local BOLD='\033[1m'

    # =========================================================================
    # Handle -e/--exit Flag (Kill Server and Exit)
    # =========================================================================
    if [[ "$exit_flag" == true ]]; then
        local server_info=$(ps aux | grep -E 'python.*http\.server|python.*SimpleHTTPServer' | grep -v grep | head -1)
        if [[ -n "$server_info" ]]; then
            local server_pid=$(echo "$server_info" | awk '{print $2}')
            local server_port=$(lsof -Pan -p "$server_pid" -i 2>/dev/null | grep LISTEN | awk '{print $9}' | cut -d: -f2 | head -1)
            kill "$server_pid" 2>/dev/null
            if [[ $? -eq 0 ]]; then
                echo -e "${GREEN}✓ Server stopped (PID: $server_pid, port: ${server_port:-unknown})${NC}"
            else
                echo -e "${RED}✗ Failed to stop server${NC}"
                [[ -z "$old_nullglob" ]] && unsetopt null_glob
                return 1
            fi
        else
            echo -e "${YELLOW}No server running on port 8000.${NC}"
        fi
        [[ -z "$old_nullglob" ]] && unsetopt null_glob
        return 0
    fi

    # HTML file patterns constant
    local -a HTML_PATTERNS
    HTML_PATTERNS=('*.htm' '*.html')

    # =========================================================================
    # URL Path Construction (when site_home is specified)
    # =========================================================================
    # When site_home is set, we need to calculate the URL path that the browser
    # should open. The server will run from site_home, so the URL path must be
    # the relative path from site_home to the file we want to view.
    #
    # Example:
    #   site_home = /Users/me/www.example.com       (server runs here)
    #   PWD       = /Users/me/www.example.com/blog  (user is here)
    #   filename  = post.html                       (file to view)
    #
    #   relative_path = "blog"                      (PWD minus site_home)
    #   url_path      = "/blog/post.html"           (what browser opens)
    #   Server finds  = blog/post.html              (relative to site_home) ✓
    # =========================================================================
    local url_path=""
    local relative_path=""
    if [[ -n "$site_home" ]]; then
        # Normalize site_home: convert to absolute path and remove trailing slash
        site_home="${site_home%/}"
        if [[ "$site_home" != /* ]]; then
            site_home="$(cd "$site_home" 2>/dev/null && pwd)" || {
                echo -e "${RED}Error: site_home directory does not exist: $site_home${NC}"
                [[ -z "$old_nullglob" ]] && unsetopt null_glob
                return 1
            }
        fi

        # Ensure current directory is within site_home (required for relative path calculation)
        if [[ "$PWD" != "$site_home"* ]]; then
            echo -e "${RED}Error: Current directory is not under site_home${NC}"
            echo -e "${CYAN}Site home: ${MAGENTA}$site_home${NC}"
            echo -e "${CYAN}Current directory: ${MAGENTA}$PWD${NC}"
            [[ -z "$old_nullglob" ]] && unsetopt null_glob
            return 1
        fi

        # Calculate relative path: strip site_home prefix from PWD
        # e.g., PWD="/a/b/c", site_home="/a/b" -> relative_path="c"
        if [[ "$PWD" == "$site_home" ]]; then
            relative_path=""
        else
            relative_path="${PWD#$site_home/}"
        fi

        # Build the final URL path from relative_path and filename
        if [[ -n "$relative_path" && -n "$filename" ]]; then
            filename="${filename#/}"  # Normalize: remove leading slash if present
            url_path="/${relative_path}/${filename}"
        elif [[ -n "$relative_path" ]]; then
            url_path="/${relative_path}"
        elif [[ -n "$filename" ]]; then
            filename="${filename#/}"
            url_path="/${filename}"
        fi
    fi

    # 1. Check if a Python web server is already running
    local server_count=$(ps aux | grep -E 'python.*http\.server|python.*SimpleHTTPServer' | grep -v grep | wc -l)

    if [[ $server_count -gt 1 ]]; then
        echo -e "${RED}${BOLD}✗ Multiple Python web servers are running!${NC}"
        echo -e "${YELLOW}Please resolve manually. Running servers:${NC}"
        echo ""
        ps aux | grep -E 'python.*http\.server|python.*SimpleHTTPServer' | grep -v grep | while read line; do
            local pid=$(echo "$line" | awk '{print $2}')
            local dir=$(lsof -p "$pid" 2>/dev/null | grep cwd | awk '{print $NF}')
            echo -e "${CYAN}PID ${MAGENTA}$pid${CYAN}: ${MAGENTA}$dir${NC}"
        done
        echo ""
        echo -e "${YELLOW}To stop a server, run: ${CYAN}kill <PID>${NC}"
        return 1
    elif [[ $server_count -eq 1 ]]; then
        local existing_server=$(ps aux | grep -E 'python.*http\.server|python.*SimpleHTTPServer' | grep -v grep)
        local server_pid=$(echo "$existing_server" | awk '{print $2}')
        local server_dir=$(lsof -p "$server_pid" 2>/dev/null | grep cwd | awk '{print $NF}')

        # Try to detect the port number from the process
        local server_port=$(lsof -Pan -p "$server_pid" -i 2>/dev/null | grep LISTEN | awk '{print $9}' | cut -d: -f2 | head -1)

        # Default behavior: reuse existing server and open browser
        # With -m flag: show interactive menu
        if [[ "$menu_flag" == false ]]; then
            # Default: Just open browser with existing server
            if [[ -n "$server_port" ]]; then
                echo -e "${YELLOW}⚠ Reusing existing server (PID: $server_pid, port: $server_port)${NC}"
                open "http://localhost:$server_port${url_path}"
                echo -e "${GREEN}✓ Browser opened at ${BLUE}http://localhost:$server_port${url_path}${NC}"
            else
                echo -e "${RED}${BOLD}✗ Could not detect server port${NC}"
                echo -e "${YELLOW}Try manually at: ${CYAN}http://localhost:8000${NC}"
            fi
            [[ -z "$old_nullglob" ]] && unsetopt null_glob
            return 0
        fi

        # -m flag: Show interactive menu
        echo -e "${YELLOW}${BOLD}⚠ A Python web server is already running!${NC}"
        echo -e "${CYAN}Directory: ${MAGENTA}$server_dir${NC}"
        echo -e "${CYAN}PID: ${MAGENTA}$server_pid${NC}"
        if [[ -n "$server_port" ]]; then
            echo -e "${CYAN}Port: ${MAGENTA}$server_port${NC}"
            echo -e "${CYAN}URL: ${BLUE}${BOLD}http://localhost:$server_port${url_path}${NC}"
        fi
        echo ""
        echo -e "${BOLD}What would you like to do?${NC}"
        echo -e "  ${GREEN}1${NC}) Open in browser"
        echo -e "  ${GREEN}2${NC}) Quit the existing server"
        echo -e "  ${GREEN}3${NC}) Quit and restart here (${BLUE}$PWD${NC})"
        echo -e "  ${GREEN}4${NC}) Cancel and leave everything unchanged"
        echo ""
        echo -n -e "${BOLD}Enter your choice [1-4]: ${NC}"

        read choice

        case "$choice" in
            1)
                # Open existing server in browser
                if [[ -n "$server_port" ]]; then
                    open "http://localhost:$server_port${url_path}"
                    echo -e "${GREEN}✓ Browser opened at ${BLUE}http://localhost:$server_port${url_path}${NC}"
                else
                    echo -e "${RED}${BOLD}✗ Could not detect server port${NC}"
                    echo -e "${YELLOW}Try manually at: ${CYAN}http://localhost:8000${NC}"
                fi
                return 0
                ;;
            2)
                # Quit the existing server
                kill "$server_pid" 2>/dev/null
                if [[ $? -eq 0 ]]; then
                    echo -e "${GREEN}✓ Server stopped successfully${NC}"
                else
                    echo -e "${RED}✗ Failed to stop server${NC}"
                    return 1
                fi
                return 0
                ;;
            3)
                # Quit and restart here
                kill "$server_pid" 2>/dev/null
                if [[ $? -eq 0 ]]; then
                    echo -e "${GREEN}✓ Server stopped successfully${NC}"
                else
                    echo -e "${RED}✗ Failed to stop server${NC}"
                    return 1
                fi
                # Continue to start new server - need to check HTML files in new location
                echo ""
                echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                echo -e "${CYAN}Checking for HTML files in: ${MAGENTA}$PWD${NC}"
                echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                echo ""

                # Re-check for HTML files in current directory
                local -a new_html_files
                local new_has_html=false

                for pattern in "${HTML_PATTERNS[@]}"; do
                    for file in ${~pattern}; do
                        if [[ -f "$file" ]]; then
                            new_html_files+=("$file")
                            new_has_html=true
                        fi
                    done
                done

                if [[ "$new_has_html" == false ]]; then
                    echo -e "${RED}${BOLD}✗ No HTML files found!${NC}"
                    echo -e "${YELLOW}This script requires at least one HTML file (*.htm or *.html)${NC}"
                    echo -e "${CYAN}Current directory: ${MAGENTA}$PWD${NC}"
                    echo ""
                    [[ -z "$old_nullglob" ]] && unsetopt null_glob
                    return 1
                fi
                echo -e "${GREEN}✓ Found HTML files${NC}"
                echo ""
                ;;
            4)
                # Cancel
                echo -e "${YELLOW}Cancelled - no changes made${NC}"
                return 0
                ;;
            *)
                echo -e "${RED}Invalid choice - cancelling${NC}"
                return 1
                ;;
        esac
    fi

    # 2. Check if Python is available
    local python_cmd=""
    if command -v python3 &> /dev/null; then
        python_cmd="python3"
    elif command -v python &> /dev/null; then
        python_cmd="python"
    else
        echo -e "${RED}${BOLD}✗ Python is not installed${NC}"
        echo -e "${YELLOW}Please install Python via Homebrew:${NC}"
        echo -e "  ${CYAN}brew install python${NC}"
        echo -e "${YELLOW}If you don't have Homebrew, install it from:${NC}"
        echo -e "  ${CYAN}https://brew.sh${NC}"
        echo ""
        [[ -z "$old_nullglob" ]] && unsetopt null_glob
        return 1
    fi

    # 3. Check if Python has the http.server module
    if ! $python_cmd -m http.server --help &> /dev/null; then
        echo -e "${RED}${BOLD}✗ Python http.server module not found${NC}"
        echo -e "${YELLOW}Your Python installation appears to be incomplete.${NC}"
        echo -e "${YELLOW}Try reinstalling Python:${NC}"
        echo -e "  ${CYAN}brew reinstall python${NC}"
        echo -e "${YELLOW}Or if using system Python, ensure the full installation is present.${NC}"
        echo ""
        [[ -z "$old_nullglob" ]] && unsetopt null_glob
        return 1
    fi

    # 4. Check if PWD contains at least 1 HTML file
    local -a html_files
    local has_html=false

    # Populate array with actual matching files
    for pattern in "${HTML_PATTERNS[@]}"; do
        for file in ${~pattern}; do
            if [[ -f "$file" ]]; then
                html_files+=("$file")
                has_html=true
            fi
        done
    done

    if [[ "$has_html" == false ]]; then
        echo -e "${RED}${BOLD}✗ No HTML files found in current directory${NC}"
        echo -e "${YELLOW}This script requires at least one HTML file (*.htm or *.html)${NC}"
        echo -e "${CYAN}Current directory: ${MAGENTA}$PWD${NC}"
        echo ""
        [[ -z "$old_nullglob" ]] && unsetopt null_glob
        return 1
    fi

    # 5. Start the HTTP server
    local port=8000

    # Find an available port if 8000 is taken
    while lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; do
        ((port++))
    done

    # =========================================================================
    # Server Directory Selection
    # =========================================================================
    # When site_home is specified, the server must run from site_home (the site root)
    # so that URL paths like /subdir/file.html resolve correctly.
    # Without site_home, the server runs from the current directory (PWD).
    # =========================================================================
    local server_dir="$PWD"
    if [[ -n "$site_home" ]]; then
        server_dir="$site_home"
    fi

    # =========================================================================
    # Startup Menu (when -m flag is passed and no server is running)
    # =========================================================================
    if [[ "$menu_flag" == true ]]; then
        echo -e "${CYAN}No server currently running.${NC}"
        echo -e "${CYAN}Directory: ${MAGENTA}$server_dir${NC}"
        echo -e "${CYAN}Port: ${MAGENTA}$port${NC}"
        echo -e "${CYAN}URL: ${BLUE}${BOLD}http://localhost:$port${url_path}${NC}"
        echo ""
        echo -e "${BOLD}What would you like to do?${NC}"
        echo -e "  ${GREEN}1${NC}) Start server in background"
        echo -e "  ${GREEN}2${NC}) Start server in foreground"
        echo -e "  ${GREEN}3${NC}) Cancel"
        echo ""
        echo -n -e "${BOLD}Enter your choice [1-3]: ${NC}"

        read startup_choice

        case "$startup_choice" in
            1)
                # Start in background (default behavior)
                ;;
            2)
                # Start in foreground (blocking)
                echo -e "${GREEN}${BOLD}✓ All checks passed!${NC}"
                echo -e "${CYAN}Starting HTTP server in: ${MAGENTA}$server_dir${NC}"
                echo -e "${CYAN}Port: ${MAGENTA}$port${NC}"
                echo -e "${CYAN}Access at: ${BLUE}${BOLD}http://localhost:$port${url_path}${NC}"
                echo ""

                # Auto-open browser unless -p flag
                if [[ "$prompt_flag" == true ]]; then
                    echo -n -e "${BOLD}Open in browser now? [y/N]: ${NC}"
                    read -r open_browser
                    if [[ "$open_browser" =~ ^[Yy]$ ]]; then
                        open "http://localhost:$port${url_path}"
                        echo -e "${GREEN}✓ Browser opened at ${BLUE}http://localhost:$port${url_path}${NC}"
                    fi
                else
                    open "http://localhost:$port${url_path}"
                    echo -e "${GREEN}✓ Browser opened at ${BLUE}http://localhost:$port${url_path}${NC}"
                fi

                echo -e "${CYAN}Server running (press Ctrl+C to stop)${NC}"
                # Run in foreground (blocking)
                (cd "$server_dir" && $python_cmd -m http.server $port)
                [[ -z "$old_nullglob" ]] && unsetopt null_glob
                return 0
                ;;
            3|*)
                echo -e "${YELLOW}Cancelled - no server started${NC}"
                [[ -z "$old_nullglob" ]] && unsetopt null_glob
                return 0
                ;;
        esac
    fi

    # =========================================================================
    # Start Server in Background (default)
    # =========================================================================
    echo -e "${GREEN}${BOLD}✓ All checks passed!${NC}"
    echo -e "${CYAN}Starting HTTP server in: ${MAGENTA}$server_dir${NC}"
    echo -e "${CYAN}Port: ${MAGENTA}$port${NC}"
    echo -e "${CYAN}Access at: ${BLUE}${BOLD}http://localhost:$port${url_path}${NC}"
    echo ""

    # Start server in background with unique log file
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local log_file="/tmp/hopen-server-${timestamp}-$$.log"

    # Launch the HTTP server from server_dir (site_home if specified, otherwise PWD)
    # The subshell (cd ...) ensures the server's working directory is correct
    (cd "$server_dir" && $python_cmd -m http.server $port) &> "$log_file" &
    local server_pid=$!

    # Disown the process so it survives terminal closure
    disown $server_pid

    # Give it a moment to start
    sleep 0.5

    # Verify it started successfully
    if kill -0 $server_pid 2>/dev/null; then
        echo -e "${GREEN}${BOLD}✓ Server started successfully!${NC} ${CYAN}(PID: $server_pid)${NC}"
        echo -e "${YELLOW}To stop the server, run: ${CYAN}kill $server_pid${NC}"
        echo -e "${CYAN}Logs: ${MAGENTA}$log_file${NC}"
        echo ""

        # Open browser: auto by default, prompt with -p flag
        if [[ "$prompt_flag" == true ]]; then
            echo -n -e "${BOLD}Open in browser now? [y/N]: ${NC}"
            read -r open_browser
            if [[ "$open_browser" =~ ^[Yy]$ ]]; then
                open "http://localhost:$port${url_path}"
                echo -e "${GREEN}✓ Browser opened at ${BLUE}http://localhost:$port${url_path}${NC}"
            fi
        else
            # Default: auto-open browser
            open "http://localhost:$port${url_path}"
            echo -e "${GREEN}✓ Browser opened at ${BLUE}http://localhost:$port${url_path}${NC}"
        fi
    else
        echo -e "${RED}${BOLD}✗ Failed to start server${NC}"
        echo -e "${YELLOW}Check logs at: ${CYAN}$log_file${NC}"
        [[ -z "$old_nullglob" ]] && unsetopt null_glob
        return 1
    fi

    # Restore original null_glob setting
    [[ -z "$old_nullglob" ]] && unsetopt null_glob
}
