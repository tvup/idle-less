# Changelog

All notable changes to idle-less are documented here.

## [1.10.0] - 2026-03-02

### Added
- Quick Start section on landing page with one-click install commands
- Visual FAQ section with 4 expandable questions (WoL basics, server support, wake times, Raspberry Pi)
- Container smoke test in CI (builds and health-checks reverse-proxy)
- Install script `--help` validation in CI

### Changed
- CI workflow now triggers on `docker/**` file changes

## [1.9.2] - 2026-03-02

### Security
- Replaced `eval` with bash indirect variable expansion in reverse-proxy entrypoint (eliminates shell injection vector)

### Documentation
- Added variable mapping table to Wakeforce Docker Hub README
- Corrected misleading CHANGELOG entry about DOMAIN_CONFIG values

## [1.9.1] - 2026-03-02

### Fixed
- Removed hardcoded personal domain (`chat.christianogfars.online`) from Wakeforce PHP files
- Added temp file cleanup trap to reverse-proxy entrypoint
- nginx config test now outputs generated config on failure for debugging

### Changed
- All Danish code comments translated to English

## [1.9.0] - 2026-03-02

### Added
- Wakeforce health check endpoint (`/__gateway/api/health.php`) with Docker HEALTHCHECK
- `DOMAIN_{i}_IDLE_SERVICE` environment variable auto-configured during installation

### Fixed
- **Critical**: WoL routing broken — installer set `DOMAIN_CONFIG=backend` but nginx expects `wakeforce` for gateway redirect locations
- `DOMAIN_IDLE_SERVICE` was never written to `.env`, preventing reverse-proxy from redirecting to Wakeforce on backend errors

## [1.8.0] - 2026-03-02

### Added
- Health check endpoint (`/health` on port 8080) with Docker HEALTHCHECK
- `--help` / `-h` flag for install script with usage documentation
- IP address validation during installation
- Custom 404 page for GitHub Pages ("This server is sleeping")

### Changed
- Wakeforce splash page: professional status messages replacing casual text
- Wakeforce about.php: removed broken AI endpoint and debug features
- Wakeforce CSS: deduplicated (842 → 200 lines)
- Changed `lang="da"` to `lang="en"` across Wakeforce pages

## [1.7.1] - 2026-03-02

### Added
- Interactive power savings calculator on landing page (shows annual EUR/kWh savings)
- Smooth scroll behavior for anchor navigation

## [1.7.0] - 2026-03-02

### Added
- MIT license for open-source components (install scripts, docs, configuration)
- Contributing guide (CONTRIBUTING.md) for community engagement
- Mobile hamburger menu on landing page
- Links section in README with landing page, demo, changelog, and security policy

### Fixed
- Updated `DOMAIN_1_CONFIG` example in README (see v1.9.0 for correct value: `wakeforce`)
- Pre-filled Wakeforce inquiry email with qualifying questions (use case, server count)
- Bottom CTA differentiated from pricing CTA (free GitHub start vs contact)

## [1.6.1] - 2026-03-02

### Added
- Landing page with professional dark theme at [tvup.github.io/idle-less](https://tvup.github.io/idle-less/)
- Interactive Wakeforce demo page simulating the boot sequence
- Social sharing card (Open Graph + Twitter Card meta tags)
- FAQ structured data for Google rich snippets
- Docker Hub README documentation for both images
- GitHub issue templates (bug report, feature request)
- CI workflow for install script validation and Docker build testing
- Security policy (SECURITY.md) with vulnerability disclosure process
- SEO files: robots.txt, sitemap.xml, canonical URL, favicon

### Fixed
- Installer default hostname changed from personal domain to `app.example.com`
- Pages workflow removed from private repo (only runs in public repo)

## [1.5.0] - 2026-03-02

### Added
- Static IP assignment for Wakeforce containers on macvlan networks
- Automatic LAN subnet and gateway detection during install
- `DOMAIN_{i}_WF_IP`, `DOMAIN_{i}_SUBNET`, `DOMAIN_{i}_GATEWAY` configuration variables
- Professional ASCII banner in installer

### Fixed
- Use `upstream_name` variable instead of hardcoded "backend" in wf locations
- Pass correct parameters to `generate_wf_locations`

### Changed
- Modularized nginx config generation into separate library scripts
- Renamed variables for clarity across reverse-proxy scripts
- Simplified upstream and location configuration

## [1.4.0] - 2026-03-01

### Added
- Wakeforce Wake-on-LAN gateway integration
- Multi-domain support with independent WoL configuration per domain
- License key validation against validate.torbenit.dk
- Macvlan Docker network for Layer 2 WoL packet delivery
- `--wakeforce` and `--wakeforce-only` install modes
- Interactive installer with domain configuration prompts

### Changed
- Reverse proxy now supports error-triggered gateway redirect
- Docker Compose generation includes Wakeforce service definitions
