# Secure SSH Script 

A robust, interactive Bash script to secure your SSH server on Linux systems. This tool guides you step-by-step through industry-standard hardening practices, making it easy to protect your server from unauthorized access and automated attacks.

## Features 

- **INTERACTIVE SETUP**: logic that asks you for every important decision.
- **AUTOMATIC BACKUP**: Creates timestamped backups of your `sshd_config` before any changes.
- **CUSTOM PORT**: Easily change your SSH port to avoid port scanning bots (recommended range 1024-65535).
- **USER MANAGEMENT**:
    - Optional creation of a dedicated `sudo` user for SSH access.
    - Prevents `root` login by default.
- **KEY AUTHENTICATION**:
    - Guided setup for SSH keys (Import from file, Paste directly, or Generate new).
    - Disables password authentication to prevent brute-force attacks.
- **FIREWALL INTEGRATION**: Automatically configures `UFW` to allow the new SSH port and deny the old one.
- **SAFETY NET**:
    - Validates configuration syntax before restarting the service.
    - Includes a connection verification step: if you can't connect in a new session, it automatically reverts changes.

## Prerequisites

- A Linux server (Debian/Ubuntu based systems recommended, as it uses `apt` and `ufw`).
- Root privileges (run with `sudo`).

## Supported Systems 

The script automatically detects the operating system and adjusts commands (package manager, firewall) accordingly.

| Family | Distributions (Tested/Supported) | Package Manager | Firewall |
| :--- | :--- | :--- | :--- |
| **Debian** | Debian, Ubuntu, Linux Mint, Kali, Pop!_OS | `apt` | `ufw` |
| **RHEL** | RHEL, CentOS, Fedora, Rocky, AlmaLinux | `dnf` / `yum` | `firewalld` |
| **Arch** | Arch Linux, Manjaro, EndeavourOS | `pacman` | `ufw` (preferred) / `firewalld` |
| **SUSE** | openSUSE (Leap/Tumbleweed), SLES | `zypper` | `firewalld` |

## Usage 

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/yourusername/secure-ssh.git
    cd secure-ssh
    ```

2.  **Make the script executable:**
    ```bash
    chmod +x secure_ssh.sh
    ```

3.  **Run with sudo:**
    ```bash
    sudo ./secure_ssh.sh
    ```

4.  **Follow the on-screen prompts.**
    > **Important:** Do not close your current terminal session until you have verified that you can connect in a *new* terminal window.

## Security Controls Applied

- `Port`: Changed from default 22 (optional).
- `PermitRootLogin`: Set to `no`.
- `PasswordAuthentication`: Set to `no`.
- `PubkeyAuthentication`: Set to `yes`.
- `MaxAuthTries`: Limited to 3.
- `X11Forwarding`: Disabled.
- `AllowUsers`: Restricts SSH access to the specific configured user.

## Disclaimer 

This script modifies core system configuration files (`/etc/ssh/sshd_config`) and firewall rules. While it includes safety checks and backup mechanisms, **always ensure you have a way to access your server (e.g., via a cloud provider's web console) in case of emergency.**

## License

MIT
