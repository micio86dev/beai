# Delta for Admin Backoffice

## ADDED Requirements

### Requirement: Navigation And Route Guards Follow The Suppressed Abilities Without A Client Change

The ability suppression of `superadmin-clients-console` MUST be consumed by the existing mechanism with no
client-side role or `is_superadmin` check: the `requires` map of the sidebar and the `REQUIRED` map of the route
guard read the published abilities, and `scope: 'platform'` keeps narrowing the sidebar for a superadmin with no
acting client. Because `users.viewAny`, `llmCredentials.viewAny` and `avatarTemplates.*` are not suppressed, a
superadmin with no acting client MUST still reach Settings (platform user list, credentials, platform settings) and
the avatar-template pages, while the organization-scoped Settings tabs (profile, branding, webhooks, API keys) stay
absent.

#### Scenario: Settings stays reachable without an acting client

- GIVEN a superadmin with no acting client
- WHEN the sidebar renders and they open `/settings`
- THEN Settings is present, the guard lets them in, and only the platform sections are listed

#### Scenario: The organization-scoped tabs are absent

- GIVEN the same superadmin
- WHEN the Settings rail renders
- THEN the profile, branding, webhooks and API-keys sections are not offered

#### Scenario: Selecting a client reveals them

- GIVEN the superadmin selects organization A and the page reloads
- WHEN the Settings rail renders
- THEN the organization-scoped sections appear as for an admin of A
