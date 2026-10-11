# Delta for Superadmin Clients Console

## ADDED Requirements

### Requirement: Org-Scoped Abilities Are Suppressed With No Acting Organization

Extends "Platform Capabilities Answer Through One Mechanism". `UserAbilities::for()` MUST derive the organization it
answers for as the caller's own organization when they have one, and otherwise the acting organization resolved by
`TenantResolver`. When the caller has no organization context at all (a superadmin with no acting organization),
every ability of the groups `organization`, `apiClients`, `projects` and `participants` MUST be `false`.
Suppression MUST live in `UserAbilities`, because `Gate::before` grants a superadmin every policy before any policy
body runs, so no policy can answer "no organization is selected".

The groups `users`, `llmCredentials`, `avatarTemplates`, `clients`, `platformSettings` and `catalogue` MUST NOT be
suppressed: with no organization context they are platform-scope (the Users section lists BEAI's own people, the
credentials are platform rows, the avatar-template pages are platform nav entries) and `users.viewAny` is the ability
that guards `/settings`. The response shape is unchanged: the same groups and keys, only the values differ.

#### Scenario: A superadmin with no acting organization has the org-scoped groups suppressed

- GIVEN a superadmin with no acting organization
- WHEN `GET /api/auth/me` is called
- THEN every key of `abilities.organization`, `.apiClients`, `.projects` and `.participants` is `false`

#### Scenario: Platform groups survive suppression

- GIVEN the same superadmin
- WHEN `GET /api/auth/me` is called
- THEN `abilities.clients.viewAny`, `.platformSettings.viewAny`, `.catalogue.manage`, `.users.viewAny`,
  `.llmCredentials.viewAny` and `.avatarTemplates.manageGlobal` are `true`

#### Scenario: Selecting an acting organization restores the groups

- GIVEN the same superadmin selects organization A as their acting organization
- WHEN `GET /api/auth/me` is called again
- THEN `abilities.organization`, `.apiClients`, `.projects` and `.participants` are `true`, as for an admin of A

#### Scenario: An org-bound user is never subject to suppression

- GIVEN an admin, operator or viewer of an organization
- WHEN `GET /api/auth/me` is called
- THEN the abilities are exactly those they had before this change
