# {{title}}: development rules

`{{name}}` is an Odoo {{odoo_series}} module of odoo-base, installed from `custom-addons/{{name}}`. These rules apply
to every change, whether a person or an agent (Claude Code, Codex) writes it. When a rule and a request conflict,
stop and ask: do not guess.

## Language and commits

- Everything in the repository is in English: code, comments, docstrings, field labels, help texts, XML, tests,
  README, and commit messages. Users see Spanish (or another language) only through translations (`i18n/`).
- Commit messages: `[ACTION] Description`, with an uppercase action and a short imperative description.
  - Actions: `ADD` (new feature or file), `FIX` (bug fix), `IMP` (improvement of existing behavior), `REF`
    (refactoring without behavior change), `REM` (removal), `TEST` (tests only), `DOC` (documentation only),
    `I18N` (translations).
  - Example: `[ADD] Job alert model and daily cron`.
  - One logical change per commit.

## Structure

```
__manifest__.py        version {{odoo_series}}.X.Y.Z, depends, data (in load order)
__init__.py            imports models (and controllers, wizards when they exist)
models/<model>.py      one file per model, imported in models/__init__.py
views/<model>_views.xml, views/menus.xml
security/ir.model.access.csv, security/<name>_security.xml (groups, record rules)
data/                  default records, crons, sequences (noupdate="1" when users may edit them)
wizards/, controllers/, report/ when needed
i18n/{{name}}.pot      exported terms; <lang>.po per language
tests/test_<feature>.py
```

## Models

- `_name` starts with the module's prefix: `{{name}}.<thing>`, for example `{{name}}.alert`. Set `_description` on
  every model.
- Field names: `<name>_id` for many2one, `<name>_ids` for one2many and many2many; booleans read as questions
  (`is_active`, `has_cv`).
- Compute methods are `_compute_<field>`, with `@api.depends` listing everything they read. Constraints are
  `_check_<rule>`. Onchanges are only for the UI, never for business rules.
- Use ORM methods (`create`, `write`, `search`, `read_group`) in batches; never call `search` or `browse` inside a
  loop over records when one query can do it.

## Security

- Every new model gets lines in `security/ir.model.access.csv` (at least one group).
- Data owned by a user also gets record rules.
- Never use `sudo()` to get around access rights. When it is truly needed, keep it minimal and write a comment
  saying why.
- Never build SQL with string formatting. Use the ORM, or `self.env.cr.execute(query, params)` with parameters.
- Controllers check access, validate their input, and use `auth="user"` unless they are deliberately public.
- No secrets in the repository (API keys, passwords, tokens). Read them from system parameters or the environment
  configured outside the code.

## Views and texts

- XML ids are unique and descriptive: `view_<model>_form`, `action_<model>`, `menu_<thing>`. Records go in data
  files listed in `__manifest__.py`.
- User-facing strings are translatable:
  - in Python, `self.env._("Text")`;
  - in fields, `string=`;
  - in XML, plain text (exported automatically).
- No inline JavaScript in views. Web assets go in `static/` and the manifest's `assets`.

## Tests (required)

- Every feature and bug fix comes with tests in `tests/`, imported in `tests/__init__.py`:
  - `TransactionCase` for models and business rules;
  - `HttpCase` (or a tour) for views and controllers.
- Tag tests with `@tagged("post_install", "-at_install")` unless they must run during installation.
- Test both the expected behavior and the refused cases: access rights, constraints, and invalid input.
- `ho-odoo-test {{name}}` must pass before a change is done. It installs the module into a real Odoo
  {{odoo_series}} with a throwaway database and fails when the module does not install, when no test ran, or when
  any test fails.

## Manifest and dependencies

- Bump `version` in `__manifest__.py` whenever models, fields, or data change:
  - `{{odoo_series}}.X.Y.Z`: Z for fixes, Y for features, X for breaking changes;
  - write a migration script in `migrations/<version>/` when existing data must change.
- `depends` lists every Odoo module this one uses.
- External Python packages go in `external_dependencies`. Tests run without network access, so a new package must
  also be added to the platform's Odoo toolchain (hermes-orchestrator `workers/versions.env`, `ODOO_EXTRA_PYTHON`):
  say so in the change.

## Working with hermes-orchestrator

- `.hermes/project.yaml` holds this module's commands and quality gate. A change there is a configuration change
  that a person approves.
- Keep each change focused on the task.
- Update `README.md` when behavior visible to users changes.
