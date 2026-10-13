# @beai/sdk@0.72.7

A TypeScript SDK client for the api.beai.example API.

## Usage

First, install the SDK from npm.

```bash
npm install @beai/sdk --save
```

Next, try it out.


```ts
import {
  Configuration,
  ExportApi,
} from '@beai/sdk';
import type { PublicApiExportsIndexRequest } from '@beai/sdk';

async function example() {
  console.log("🚀 Testing @beai/sdk SDK...");
  const config = new Configuration({ 
    // Configure HTTP bearer authorization: apiKey
    accessToken: "YOUR BEARER TOKEN",
  });
  const api = new ExportApi(config);

  const body = {
    // string | Opaque pagination cursor from a previous page\'s next_cursor. Omit for the first page. A present but malformed value answers 400 invalid_cursor. (optional)
    cursor: cursor_example,
    // number | Page size, 1-100 (default 25). Out of range answers 400 validation_failed. (optional)
    limit: 56,
  } satisfies PublicApiExportsIndexRequest;

  try {
    const data = await api.publicApiExportsIndex(body);
    console.log(data);
  } catch (error) {
    console.error(error);
  }
}

// Run the test
example().catch(console.error);
```


## Documentation

### API Endpoints

All URIs are relative to *https://api.beai.example/v1*

| Class | Method | HTTP request | Description
| ----- | ------ | ------------ | -------------
*ExportApi* | [**publicApiExportsIndex**](docs/ExportApi.md#publicapiexportsindex) | **GET** /exports | List exports
*ExportApi* | [**publicApiExportsShow**](docs/ExportApi.md#publicapiexportsshow) | **GET** /exports/{id} | Get an export
*ExportApi* | [**publicApiExportsStore**](docs/ExportApi.md#publicapiexportsstore) | **POST** /exports | Create an export
*HealthApi* | [**publicApiHealth**](docs/HealthApi.md#publicapihealth) | **GET** /health | Check that the API answers
*InterviewApi* | [**publicApiInterviewsAnswers**](docs/InterviewApi.md#publicapiinterviewsanswers) | **GET** /interviews/{interview}/answers | Get the answers
*InterviewApi* | [**publicApiInterviewsEvents**](docs/InterviewApi.md#publicapiinterviewsevents) | **GET** /interviews/{interview}/events | List interview events
*InterviewApi* | [**publicApiInterviewsIndex**](docs/InterviewApi.md#publicapiinterviewsindex) | **GET** /interviews | List interviews
*InterviewApi* | [**publicApiInterviewsScoring**](docs/InterviewApi.md#publicapiinterviewsscoring) | **GET** /interviews/{interview}/scoring | Get the scoring
*InterviewApi* | [**publicApiInterviewsShow**](docs/InterviewApi.md#publicapiinterviewsshow) | **GET** /interviews/{interview} | Get an interview
*InterviewApi* | [**publicApiInterviewsStore**](docs/InterviewApi.md#publicapiinterviewsstore) | **POST** /interviews | Create an interview
*InterviewApi* | [**publicApiInterviewsTranscript**](docs/InterviewApi.md#publicapiinterviewstranscript) | **GET** /interviews/{interview}/transcript | Get the transcript
*OrganizationApi* | [**publicApiOrganizationShow**](docs/OrganizationApi.md#publicapiorganizationshow) | **GET** /organization | Get the organization
*ProjectApi* | [**publicApiProjectsIndex**](docs/ProjectApi.md#publicapiprojectsindex) | **GET** /projects | List projects
*ProjectApi* | [**publicApiProjectsShow**](docs/ProjectApi.md#publicapiprojectsshow) | **GET** /projects/{project} | Get a project
*RecordingApi* | [**publicApiInterviewsRecording**](docs/RecordingApi.md#publicapiinterviewsrecording) | **GET** /interviews/{interview}/recording | Get the recording
*SessionTokenApi* | [**publicApiInterviewsSessionTokensStore**](docs/SessionTokenApi.md#publicapiinterviewssessiontokensstore) | **POST** /interviews/{interview}/session-tokens | Create a session token
*UsageApi* | [**publicApiUsageShow**](docs/UsageApi.md#publicapiusageshow) | **GET** /usage | Get usage
*WebhookDeliveryApi* | [**publicApiWebhooksDeliveriesIndex**](docs/WebhookDeliveryApi.md#publicapiwebhooksdeliveriesindex) | **GET** /webhooks/deliveries | List webhook deliveries
*WebhookDeliveryApi* | [**publicApiWebhooksDeliveriesRedeliver**](docs/WebhookDeliveryApi.md#publicapiwebhooksdeliveriesredeliver) | **POST** /webhooks/deliveries/{id}/redeliver | Redeliver a webhook delivery


### Models

- [CreateExportRequest](docs/CreateExportRequest.md)
- [CreateInterviewRequest](docs/CreateInterviewRequest.md)
- [CreateInterviewRequestCandidate](docs/CreateInterviewRequestCandidate.md)
- [PublicApiExportsIndex200Response](docs/PublicApiExportsIndex200Response.md)
- [PublicApiHealth200Response](docs/PublicApiHealth200Response.md)
- [PublicApiInterviewsAnswers200Response](docs/PublicApiInterviewsAnswers200Response.md)
- [PublicApiInterviewsAnswers200ResponseAnswersInner](docs/PublicApiInterviewsAnswers200ResponseAnswersInner.md)
- [PublicApiInterviewsEvents200Response](docs/PublicApiInterviewsEvents200Response.md)
- [PublicApiInterviewsEvents200ResponseDataInner](docs/PublicApiInterviewsEvents200ResponseDataInner.md)
- [PublicApiInterviewsIndex200Response](docs/PublicApiInterviewsIndex200Response.md)
- [PublicApiInterviewsRecording200Response](docs/PublicApiInterviewsRecording200Response.md)
- [PublicApiInterviewsScoring200Response](docs/PublicApiInterviewsScoring200Response.md)
- [PublicApiInterviewsScoring200ResponseCompetenciesValue](docs/PublicApiInterviewsScoring200ResponseCompetenciesValue.md)
- [PublicApiInterviewsScoring200ResponseCompetenciesValueBehaviorsInner](docs/PublicApiInterviewsScoring200ResponseCompetenciesValueBehaviorsInner.md)
- [PublicApiInterviewsSessionTokensStore201Response](docs/PublicApiInterviewsSessionTokensStore201Response.md)
- [PublicApiInterviewsStore201Response](docs/PublicApiInterviewsStore201Response.md)
- [PublicApiInterviewsTranscript200Response](docs/PublicApiInterviewsTranscript200Response.md)
- [PublicApiInterviewsTranscript200ResponseTurnsInner](docs/PublicApiInterviewsTranscript200ResponseTurnsInner.md)
- [PublicApiProjectsIndex200Response](docs/PublicApiProjectsIndex200Response.md)
- [PublicApiUsageShow200Response](docs/PublicApiUsageShow200Response.md)
- [PublicApiUsageShow200ResponseEvaluations](docs/PublicApiUsageShow200ResponseEvaluations.md)
- [PublicApiUsageShow200ResponseInterviews](docs/PublicApiUsageShow200ResponseInterviews.md)
- [PublicApiUsageShow200ResponseLlmTokens](docs/PublicApiUsageShow200ResponseLlmTokens.md)
- [PublicApiWebhooksDeliveriesIndex200Response](docs/PublicApiWebhooksDeliveriesIndex200Response.md)
- [PublicExport](docs/PublicExport.md)
- [PublicInterview](docs/PublicInterview.md)
- [PublicInterviewProgressAnswer](docs/PublicInterviewProgressAnswer.md)
- [PublicInterviewProgressCompetency](docs/PublicInterviewProgressCompetency.md)
- [PublicInterviewProject](docs/PublicInterviewProject.md)
- [PublicInterviewProjectCompetenciesInner](docs/PublicInterviewProjectCompetenciesInner.md)
- [PublicInterviewProjectFrameworkVersion](docs/PublicInterviewProjectFrameworkVersion.md)
- [PublicMessageError](docs/PublicMessageError.md)
- [PublicOrganization](docs/PublicOrganization.md)
- [PublicProblem](docs/PublicProblem.md)
- [PublicProblemError](docs/PublicProblemError.md)
- [PublicProject](docs/PublicProject.md)
- [PublicWebhookDelivery](docs/PublicWebhookDelivery.md)

### Authorization


Authentication schemes defined for the API:
<a id="apiKey"></a>
#### apiKey


- **Type**: HTTP Bearer Token authentication (beai_live_… | beai_test_…)

## About

This TypeScript SDK client supports the [Fetch API](https://fetch.spec.whatwg.org/)
and is automatically generated by the
[OpenAPI Generator](https://openapi-generator.tech) project:

- API version: `0.72.7`
- Package version: `0.72.7`
- Generator version: `7.25.0`
- Build package: `org.openapitools.codegen.languages.TypeScriptFetchClientCodegen`

The generated npm module supports the following:

- Environments
  * Node.js
  * Webpack
  * Browserify
- Language levels
  * ES5 - you must have a Promises/A+ library installed
  * ES6
- Module systems
  * CommonJS
  * ES6 module system


## Development

### Building

To build the TypeScript source code, you need to have Bun installed.
After cloning the repository, navigate to the project directory and run:

```bash
bun install
bun run build
```

### Publishing

Once you've built the package, you can publish it to npm:

```bash
bun publish
```

## License

[]()
