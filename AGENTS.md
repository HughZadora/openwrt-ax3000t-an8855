# Agent Instructions

## Scope

This file applies to the entire repository.

More specific `AGENTS.md` files deeper in the repository take precedence within their directory scope.

## Working Rules

- Treat the repository, committed configuration, tests, and documentation as the source of truth. Do not let chat history override facts already present in the repository.
- Before non-trivial changes, inspect the relevant implementation, tests, documentation, and configuration.
- Follow existing project conventions before introducing new patterns.
- Prefer established standards, mature upstream solutions, and existing project capabilities over custom implementations.
- Keep changes focused on the requested outcome and avoid unrelated refactoring.
- Do not introduce new dependencies, infrastructure, or abstractions without a concrete need.
- Update tests and documentation when behavior or public interfaces change.
- Run the repository-defined validation relevant to the change before declaring completion.
- Report validation failures accurately and distinguish change-related failures from pre-existing or environmental failures.
- Never commit secrets, credentials, or sensitive local configuration.

## Repository Knowledge

Use `README.md` as the project entry point and `docs/` for durable project knowledge.

Record materially important architectural decisions in `docs/adr/`.

## Documentation

Use `docs/INDEX.yaml` as the documentation routing source of truth.

Before creating durable project documentation:

1. Route it to an existing section defined in `docs/INDEX.yaml`.
2. Prefer updating an existing source of truth over creating another document.
3. Do not create ad hoc top-level documentation files without a concrete reason.
4. Keep generated outputs and transient artifacts out of `docs/`.

## Branch Discipline

On a protected default branch (such as `main` or `master`), do not implement
a non-trivial feature directly on it: create a focused working branch, keep
commits scoped to the task, and land through a pull request.

Approvals default to zero required reviewers so a solo repository can merge
without approvals. GitHub does not let a pull request author approve their
own pull request, so never depend on self-approval.

## Validation

Before claiming completion, find the repository-defined validation entry point,
run the checks relevant to the change, and report failures accurately,
distinguishing change-related, pre-existing, and environment failures.

If this repository provides `scripts/repository-check`, it is part of the base
repository validation.

## Working rules

- Read `README.md` and `STANDARD.md` before making non-trivial changes.
- Verify a reported problem before fixing it and prefer the smallest systemic
  fix that addresses the root cause.
- Never commit secrets, credentials, or sensitive local configuration.
- Never edit a shared file locally; change the canon and roll it out.
