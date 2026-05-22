# Security Policy

## Reporting

Report suspected vulnerabilities privately through GitHub Security Advisories for
this repository. If GHSA is unavailable to you, email security@openclaw.ai.

Do not open public issues for vulnerabilities or include secrets, private local
data, credentials, or exploit details in public reports.

## Scope

In scope:

- CLI input parsing, local filesystem handling, and config loading
- command output that could disclose private local data
- release workflows and package integrity
- dependency behavior that materially affects safe execution

Out of scope:

- upstream service outages or API changes outside this CLI's control
- compromise of a trusted local account, shell, filesystem, or device
- scanner-only findings without a reachable exploit path in supported usage

## Expectations

We prioritize reachable issues that affect private data, package integrity, or
safe execution. Include the affected commit, platform, minimal reproduction
steps, and sanitized impact details.
