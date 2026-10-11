# {{title}}

{{description}}

An Odoo {{odoo_series}} module of [odoo-base](https://github.com/geparedesm/odoo-base), installed from
`custom-addons/{{name}}`. Development rules for people and agents: [AGENTS.md](AGENTS.md).

## Tests

Tests run in a real Odoo {{odoo_series}} with a throwaway PostgreSQL:

```bash
ho-odoo-test {{name}}        # what hermes-orchestrator runs for every change
```
