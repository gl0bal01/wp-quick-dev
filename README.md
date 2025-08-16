# WP Quick Dev 🚀

[![Docker](https://img.shields.io/badge/Docker-20.10+-blue?logo=docker&logoColor=white)](https://www.docker.com/)
[![WordPress](https://img.shields.io/badge/WordPress-6.0+-21759B?logo=wordpress&logoColor=white)](https://wordpress.org/)
[![PHP](https://img.shields.io/badge/PHP-8.2-777BB4?logo=php&logoColor=white)](https://php.net/)
[![MariaDB](https://img.shields.io/badge/MariaDB-11.0-003545?logo=mariadb&logoColor=white)](https://mariadb.org/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)
[![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey)](README.md)

> ⚡ **Lightning-fast WordPress development environment for rapid plugin and theme prototyping**

**WP Quick Dev** is a Docker-based WordPress development environment designed for **quick prototyping and development only**. Get a fully functional WordPress setup with plugin/theme development workflow in under 60 seconds.

## ⚠️ Important Notice

**This environment is NOT intended for production use.** It's optimized for speed and convenience in development, with relaxed security settings and permissive file permissions.

## ✨ Features

- 🐳 **Containerized** - Docker-based, runs anywhere
- ⚡ **Fast Setup** - One command to get started
- 🔧 **Plugin Development** - Each plugin can be its own git repository
- 🎨 **Theme Development** - Streamlined theme creation and management
- 📦 **Database Management** - Easy backup and restore
- 🔄 **WP-CLI Integration** - Command-line WordPress management
- 📧 **Email Testing** - Built-in Mailpit for email debugging
- 🛠️ **Development Tools** - phpMyAdmin, logs, health checks

## 🚀 Quick Start

### Prerequisites

Before you begin, ensure you have the following installed:

- [Docker](https://docs.docker.com/get-docker/) (20.10 or higher)
- [Docker Compose](https://docs.docker.com/compose/install/) (2.0 or higher)
- [Make](https://www.gnu.org/software/make/) (usually pre-installed on Linux/macOS)
- [Git](https://git-scm.com/downloads)

### Installation

1. **Clone or download the setup script:**
   ```bash
   curl -O https://raw.githubusercontent.com/gl0bal01/wp-quick-dev/main/setup.sh
   chmod +x setup.sh
   ```

2. **Create your development environment:**
   ```bash
   ./setup.sh my-awesome-project
   cd my-awesome-project
   ```

3. **Start the environment:**
   ```bash
   make up
   ```

4. **Install WordPress:**
   ```bash
   make install
   ```

🎉 **That's it!** Your WordPress development environment is ready.

### Access Your Site

After installation, you can access:

- 🌐 **WordPress**: http://localhost:8080
- 🗄️ **phpMyAdmin**: http://localhost:8081
- 📧 **Mailpit** (email testing): http://localhost:8025

## 📖 Complete Command Reference

### 🏗️ Environment Management

| Command | Description | Example |
|---------|-------------|---------|
| `make up` | Start all containers | `make up` |
| `make down` | Stop all containers | `make down` |
| `make restart` | Restart all containers | `make restart` |
| `make install` | Install WordPress (first time only) | `make install` |
| `make clean` | **⚠️ Reset everything** (deletes all data!) | `make clean` |
| `make health` | Check if all services are running | `make health` |

### 🔌 Plugin Development

| Command | Description | Example |
|---------|-------------|---------|
| `make plugin name=<name>` | Create a new plugin | `make plugin name=my-awesome-plugin` |
| `make plugin-repo name=<name>` | Initialize plugin as git repository | `make plugin-repo name=my-awesome-plugin` |
| `make plugin-clone repo=<url>` | Clone existing plugin from repository | `make plugin-clone repo=https://github.com/user/plugin.git` |
| `make plugin-list` | List all plugins with git status | `make plugin-list` |

**Plugin Development Workflow:**
```bash
# 1. Create a new plugin
make plugin name=awesome-feature

# 2. Initialize as git repository
make plugin-repo name=awesome-feature

# 3. Connect to your remote repository
cd plugins/awesome-feature
git remote add origin https://github.com/username/awesome-feature.git
git push -u origin main

# 4. Develop your plugin...
# Files are automatically synced with WordPress
```

### 🎨 Theme Development

| Command | Description | Example |
|---------|-------------|---------|
| `make theme name=<name>` | Create a new theme | `make theme name=my-beautiful-theme` |
| `make theme-repo name=<name>` | Initialize theme as git repository | `make theme-repo name=my-beautiful-theme` |
| `make theme-clone repo=<url>` | Clone existing theme from repository | `make theme-clone repo=https://github.com/user/theme.git` |

### 💾 Database Management

| Command | Description | Example |
|---------|-------------|---------|
| `make backup` | Create database backup | `make backup` |
| `make restore file=<backup>` | Restore from backup | `make restore file=backup-20240116-143022.sql.gz` |
| `make list-backups` | List available backups | `make list-backups` |

**Backup files are stored in the `backups/` directory and are automatically compressed and timestamped.**

### 🛠️ WordPress Management (WP-CLI)

| Command | Description | Example |
|---------|-------------|---------|
| `make wp cmd="<command>"` | Run any WP-CLI command | `make wp cmd="plugin list"` |
| `make sr old=<url> new=<url>` | Search and replace URLs | `make sr old=http://old.local new=http://new.local` |
| `make cron-run` | Run WordPress cron events | `make cron-run` |

**Common WP-CLI Examples:**
```bash
# List all plugins
make wp cmd="plugin list"

# Install and activate a plugin
make wp cmd="plugin install contact-form-7 --activate"

# Create a new user
make wp cmd="user create john john@example.com --role=administrator"

# Update WordPress core
make wp cmd="core update"

# List all posts
make wp cmd="post list"
```

### 🔧 Development Tools

| Command | Description | Example |
|---------|-------------|---------|
| `make fix-permissions` | Fix file permissions for development | `make fix-permissions` |
| `make shell` | Access WordPress container shell | `make shell` |
| `make db-shell` | Access database container shell | `make db-shell` |
| `make logs` | View all container logs | `make logs` |
| `make logs service=<name>` | View specific service logs | `make logs service=wordpress` |
| `make phpinfo` | Create phpinfo.php file | `make phpinfo` |

## 📁 Project Structure

```
my-awesome-project/
├── 📂 plugins/              # Plugin development (git-ignored)
│   ├── 📁 my-plugin/        # Each plugin = separate git repo
│   └── 📁 another-plugin/
├── 📂 themes/               # Theme development (git-ignored)
│   └── 📁 my-theme/         # Each theme = separate git repo
├── 📂 uploads/              # WordPress uploads
├── 📂 backups/              # Database backups
├── 📂 wordpress/            # WordPress core (git-ignored)
├── 📄 .env                  # Environment configuration
├── 📄 docker-compose.yml    # Docker services definition
├── 📄 Makefile              # Development commands
└── 📄 README.md             # This file
```

## ⚙️ Configuration

### Environment Variables

Edit the `.env` file to customize your environment:

```bash
# Ports (change if needed)
WP_PORT=8080                 # WordPress port
PMA_PORT=8081               # phpMyAdmin port
MAILPIT_HTTP_PORT=8025      # Mailpit web interface

# WordPress URL
WP_URL=http://localhost:8080

# Database credentials (auto-generated)
DB_NAME=wordpress
DB_USER=wordpress
DB_PASSWORD=wordpress_secure_[random]
```

### PHP Configuration

PHP settings are configured for development in `.docker/php/php.ini`:

- Memory limit: 512M
- Upload max filesize: 128M
- Error reporting: Enabled
- OPcache: Enabled with revalidation

## 🛡️ Security Notice

**⚠️ This environment uses development-friendly settings that are NOT secure for production:**

- File permissions set to 0777 for cross-platform compatibility
- Database with default credentials
- Debug mode enabled
- File editing allowed
- Permissive CORS settings

**Never use this setup for production websites.**

## 🔧 Troubleshooting

### Common Issues

**Port already in use:**
```bash
# Change ports in .env file
WP_PORT=8090
PMA_PORT=8091
```

**Permission issues:**
```bash
# Fix file permissions
make fix-permissions

# Or reset everything
make clean
```

**Database connection issues:**
```bash
# Check service health
make health

# View database logs
make logs service=db
```

**WordPress not loading:**
```bash
# Check all logs
make logs

# Restart containers
make restart
```

### Health Check

Run the health check script to diagnose issues:
```bash
./health-check.sh
```

### Development Setup

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Commit your changes: `git commit -m 'Add amazing feature'`
4. Push to the branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

## 📋 Requirements

- **Docker**: 20.10 or higher
- **Docker Compose**: 2.0 or higher  
- **Make**: Any recent version
- **Operating System**: Linux, macOS, or Windows (with WSL2)
- **Memory**: At least 2GB RAM available for Docker
- **Disk Space**: At least 2GB free space

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## ⭐ Show Your Support

If this project helped you, please consider giving it a ⭐ on GitHub!

---

**Happy Coding!** 🎉

*Built with ❤️ for the WordPress developer community*
