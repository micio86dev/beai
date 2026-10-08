# Delta for Project Configuration

## ADDED Requirements

### Requirement: Project Creation Requires An Organization Context

`POST /api/projects` MUST carry the `org.context` middleware. A caller with no organization context (a superadmin
with no acting organization) MUST receive HTTP 409 `organization_context_required` before validation runs, never
HTTP 422 (a validation rule resolved against no organization) and never HTTP 404. A superadmin acting as an
organization MUST create the project in that organization, with the avatar template, framework version and slug
uniqueness rules resolved against it. The read and update/delete verbs of the resource are unchanged.

#### Scenario: A superadmin with no acting organization is refused

- GIVEN a superadmin with no acting organization
- WHEN they call `POST /api/projects` with an otherwise valid payload
- THEN the response is HTTP 409 `organization_context_required`
- AND no project is created

#### Scenario: A superadmin acting as an organization creates a project in it

- GIVEN a superadmin has organization A as their acting organization
- WHEN they call `POST /api/projects` with organization A's framework version
- THEN the response is HTTP 201 and the project belongs to organization A

#### Scenario: An org-bound admin's project creation is unchanged

- GIVEN an admin of organization B
- WHEN they call `POST /api/projects` with a valid payload
- THEN the project is created in organization B, and a framework version of another organization is refused
