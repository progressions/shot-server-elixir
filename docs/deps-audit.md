# Dependency Audit: shot-elixir

## Scope

This report covers direct dependencies listed in `mix.exs` and their current locked versions in `mix.lock`, compared against the latest versions reported by `mix hex.outdated`.

## Summary

- 10 dependencies have patch/minor upgrades available within current version constraints.
- 4 dependencies have newer major versions that are blocked by current constraints.
- Remaining direct dependencies are up-to-date.

## Inventory (direct dependencies)

| Dependency | Current | Latest | Status | Env |
| --- | --- | --- | --- | --- |
| phoenix | 1.8.1 | 1.8.3 | update possible | all |
| phoenix_ecto | 4.6.5 | 4.7.0 | update possible | all |
| ecto_sql | 3.13.2 | 3.13.4 | update possible | all |
| postgrex | 0.21.1 | 0.22.0 | update possible | all |
| phoenix_live_view | 1.1.13 | 1.1.19 | update possible | all |
| oban | 2.20.1 | 2.20.2 | update possible | all |
| swoosh | 1.19.8 | 1.20.0 | update possible | all |
| req | 0.5.15 | 0.5.17 | update possible | all |
| image | 0.62.0 | 0.62.1 | update possible | all |
| tidewave | 0.5.2 | 0.5.4 | update possible | dev |
| bandit | 1.5.7 | 1.10.1 | blocked by mix.exs | all |
| cachex | 3.6.0 | 4.1.1 | blocked by mix.exs | all |
| dotenvy | 0.9.0 | 1.1.1 | blocked by mix.exs | dev,test |
| gettext | 0.26.2 | 1.0.2 | blocked by mix.exs | all |
| arc | 0.11.0 | 0.11.0 | up-to-date | all |
| arc_ecto | 0.11.3 | 0.11.3 | up-to-date | all |
| bcrypt_elixir | 3.3.2 | 3.3.2 | up-to-date | all |
| cors_plug | 3.0.3 | 3.0.3 | up-to-date | all |
| dns_cluster | 0.2.0 | 0.2.0 | up-to-date | all |
| gen_smtp | 1.3.0 | 1.3.0 | up-to-date | all |
| guardian | 2.4.0 | 2.4.0 | up-to-date | all |
| jason | 1.4.4 | 1.4.4 | up-to-date | all |
| multipart | 0.4.0 | 0.4.0 | up-to-date | all |
| nostrum | 0.10.4 | 0.10.4 | up-to-date | all |
| phoenix_swoosh | 1.2.1 | 1.2.1 | up-to-date | all |
| phoenix_view | 2.0.4 | 2.0.4 | up-to-date | all |
| sweet_xml | 0.7.5 | 0.7.5 | up-to-date | all |
| telemetry_metrics | 1.1.0 | 1.1.0 | up-to-date | all |
| telemetry_poller | 1.3.0 | 1.3.0 | up-to-date | all |
| wax_ | 0.7.0 | 0.7.0 | up-to-date | all |
| yaml_elixir | 2.12.0 | 2.12.0 | up-to-date | all |

## Risk Assessment

- Low risk: Up-to-date dependencies; no immediate action.
- Low to medium risk: Patch/minor upgrades available for core runtime deps (Phoenix, Ecto, Postgres, LiveView, Swoosh, Oban). Staying behind can miss bugfixes and security patches.
- Medium risk: Major updates blocked by version constraints (`bandit`, `cachex`, `gettext`, `dotenvy`). These are more likely to introduce breaking changes; delaying increases divergence and upgrade cost.

## Recommendations

1. Apply patch/minor upgrades now for the update-possible set.
2. Schedule a separate pass for major upgrades:
   - `bandit` 1.5.7 -> 1.10.x (web server)
   - `cachex` 3.6 -> 4.x (caching)
   - `gettext` 0.26 -> 1.x (i18n)
   - `dotenvy` 0.9 -> 1.x (dev/test only)
3. For major upgrades, review changelogs and run targeted smoke tests (HTTP, auth, email, Discord, uploads).
