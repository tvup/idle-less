# Changelog

All notable changes to idle-less are documented here.

## [1.7.0] - 2026-03-02

### Added
- MIT license for open-source components (install scripts, docs, configuration)
- Contributing guide (CONTRIBUTING.md) for community engagement
- Mobile hamburger menu on landing page
- Links section in README with landing page, demo, changelog, and security policy

### Fixed
- Corrected `DOMAIN_1_CONFIG` example in README from invalid "wakeforce" to correct "backend"
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
